#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-skala3-finalproj-class2-team7}"
JOB_NAME="${JOB_NAME:-data-stack-rabbitmq}"
VHOST="${VHOST:-/}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://127.0.0.1:9090}"
MAIN_QUEUE_RE="${MAIN_QUEUE_RE:-lina\.data-ingestion\.ingest|lina\.admin\.ingest\.completion}"
DLQ_QUEUE_RE="${DLQ_QUEUE_RE:-lina\.admin\.ingest\.dlq|lina\.admin\.ingest\.completion\.dlq}"
DASHBOARD_CM_NAME="${DASHBOARD_CM_NAME:-rabbitmq-ingest-dlq-dashboard}"
ALERT_RULE_NAME="${ALERT_RULE_NAME:-rabbitmq-ingest-dlq-alerts}"
DATASOURCE_UID="${DATASOURCE_UID:-prometheus}"
PROM_URL="${PROM_URL:-${PROMETHEUS_URL}}"

die() {
  echo "${1}" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need kubectl
need curl
need jq
need cat
need mktemp

if ! curl -fsS "${PROM_URL}/-/ready" >/dev/null; then
  die "Prometheus is not reachable: ${PROM_URL}. port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 first."
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "[1/4] validate queue labels on ${JOB_NAME} (${NAMESPACE})"
QUEUE_KEYS=$(curl -fsS --get "${PROM_URL}/api/v1/label/queue/values" \
  --data-urlencode "match[]=rabbitmq_queue_messages_ready{job=\"${JOB_NAME}\",namespace=\"${NAMESPACE}\",vhost=\"${VHOST}\"}")

echo "${QUEUE_KEYS}" | jq -e '.status=="success"' >/dev/null || die "Prometheus label API did not return success"

echo "[2/4] create dashboard configmap: ${DASHBOARD_CM_NAME}"
cat > "${TMP_DIR}/rabbitmq-detail-dlq.json" <<EOF_JSON
{
  "annotations": {"list": [{"builtIn": 1,"datasource": {"type": "grafana", "uid": "-- Grafana --"},"enable": true,"hide": true,"iconColor": "rgba(0, 211, 255, 1)","name": "Annotations & Alerts","type": "dashboard"}]},
  "editable": true,
  "id": null,
  "schemaVersion": 39,
  "style": "dark",
  "tags": ["skala", "data-stack", "rabbitmq", "dlq"],
  "timezone": "browser",
  "title": "RabbitMQ DLQ (Ingest)",
  "uid": "rabbitmq-ingest-dlq",
  "time": {"from": "now-30m", "to": "now"},
  "refresh": "30s",
  "panels": [
    {
      "type": "stat",
      "title": "DLQ total ready messages",
      "datasource": {"type": "prometheus", "uid": "${DATASOURCE_UID}"},
      "gridPos": {"h": 4, "w": 8, "x": 0, "y": 0},
      "targets": [{"refId": "A", "expr": "sum(rabbitmq_queue_messages_ready{job=\"${JOB_NAME}\",namespace=\"${NAMESPACE}\",vhost=\"${VHOST}\",queue=~\"${DLQ_QUEUE_RE}\"})"}],
      "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "palette-classic"}}, "overrides": []}
    },
    {
      "type": "timeseries",
      "title": "DLQ ready messages by queue",
      "datasource": {"type": "prometheus", "uid": "${DATASOURCE_UID}"},
      "gridPos": {"h": 8, "w": 16, "x": 8, "y": 0},
      "targets": [{"refId": "A", "legendFormat": "{{queue}}", "expr": "rabbitmq_queue_messages_ready{job=\"${JOB_NAME}\",namespace=\"${NAMESPACE}\",vhost=\"${VHOST}\",queue=~\"${DLQ_QUEUE_RE}\"}"}]
    },
    {
      "type": "timeseries",
      "title": "Main queue ready messages (ingest)",
      "datasource": {"type": "prometheus", "uid": "${DATASOURCE_UID}"},
      "gridPos": {"h": 8, "w": 16, "x": 0, "y": 4},
      "targets": [{"refId": "A", "legendFormat": "{{queue}}", "expr": "rabbitmq_queue_messages_ready{job=\"${JOB_NAME}\",namespace=\"${NAMESPACE}\",vhost=\"${VHOST}\",queue=~\"${MAIN_QUEUE_RE}\"}"}]
    }
  ]
}
EOF_JSON

cat > "${TMP_DIR}/rabbitmq-dashboard-cm.yaml" <<EOF_CM
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${DASHBOARD_CM_NAME}
  namespace: ${NAMESPACE}
  labels:
    grafana_dashboard: "1"
data:
  rabbitmq-ingest-dlq.json: |
$(sed 's/^/    /' "${TMP_DIR}/rabbitmq-detail-dlq.json")
EOF_CM

kubectl apply -f "${TMP_DIR}/rabbitmq-dashboard-cm.yaml"

echo "[3/4] create/update PrometheusRule: ${ALERT_RULE_NAME}"
cat > "${TMP_DIR}/rabbitmq-dlq-alerts.yaml" <<EOF_RULE
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: ${ALERT_RULE_NAME}
  namespace: ${NAMESPACE}
spec:
  groups:
    - name: rabbitmq-ingest-dlq.rules
      rules:
        - alert: RabbitMQIngestDLQMessagesPresent
          expr: |
            sum by (queue) (rabbitmq_queue_messages_ready{job="${JOB_NAME}",namespace="${NAMESPACE}",vhost="${VHOST}",queue=~"${DLQ_QUEUE_RE}"}) > 0
          for: 5m
          labels:
            severity: critical
            component: rabbitmq
          annotations:
            summary: "RabbitMQ DLQ has ready messages"
            description: "DLQ queue {{ $labels.queue }} has messages for more than 5m. Check ingest consumer failures and retry/DLQ flow."
        - alert: RabbitMQIngestDLQQueueingUp
          expr: |
            sum by (queue) (increase(rabbitmq_queue_messages_ready{job="${JOB_NAME}",namespace="${NAMESPACE}",vhost="${VHOST}",queue=~"${DLQ_QUEUE_RE}"}[5m])) > 0
          for: 2m
          labels:
            severity: warning
            component: rabbitmq
          annotations:
            summary: "RabbitMQ DLQ queue is increasing"
            description: "DLQ messages increased for {{ $labels.queue }} in last 5m. Potential processing failure or retry overflow."
EOF_RULE

kubectl apply -f "${TMP_DIR}/rabbitmq-dlq-alerts.yaml"

echo "[4/4] verify resources"
kubectl -n "${NAMESPACE}" get configmap ${DASHBOARD_CM_NAME} --no-headers >/dev/null && \
echo "  - ConfigMap ok" || true
kubectl -n "${NAMESPACE}" get prometheusrule ${ALERT_RULE_NAME} --no-headers >/dev/null && \
echo "  - PrometheusRule ok" || true

echo "done."
