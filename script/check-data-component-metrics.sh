#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-skala3-finalproj-class2-team7}"
PROM_URL="${PROM_URL:-http://localhost:9090}"
PROM_SVC="${PROM_SVC:-monitoring-kube-prometheus-prometheus}"
LOCAL_PORT="${LOCAL_PORT:-9090}"
COMPONENT="${1:-all}"
PORT_FORWARD="${PORT_FORWARD:-false}"

usage() {
  cat <<'EOF'
Usage:
  script/check-data-component-metrics.sh [all|qdrant|rabbitmq|mysql|mongodb]

Environment:
  NAMESPACE      Kubernetes namespace. Default: skala3-finalproj-class2-team7
  PROM_URL       Prometheus URL. Default: http://localhost:9090
  PROM_SVC       Prometheus service name for port-forward mode.
  LOCAL_PORT     Local port for port-forward mode. Default: 9090
  PORT_FORWARD   Set to true to run kubectl port-forward automatically.

Examples:
  kubectl -n skala3-finalproj-class2-team7 port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
  script/check-data-component-metrics.sh all

  PORT_FORWARD=true script/check-data-component-metrics.sh rabbitmq
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

start_port_forward() {
  require_cmd kubectl
  PROM_URL="http://localhost:${LOCAL_PORT}"

  echo "Starting port-forward: svc/${PROM_SVC} ${LOCAL_PORT}:9090"
  kubectl -n "$NAMESPACE" port-forward "svc/${PROM_SVC}" "${LOCAL_PORT}:9090" >/tmp/data-stack-prometheus-port-forward.log 2>&1 &
  PF_PID="$!"

  cleanup() {
    kill "$PF_PID" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  for _ in $(seq 1 20); do
    if curl -fsS "${PROM_URL}/-/ready" >/dev/null 2>&1; then
      return
    fi
    sleep 0.5
  done

  echo "Prometheus port-forward did not become ready." >&2
  echo "Log: /tmp/data-stack-prometheus-port-forward.log" >&2
  exit 1
}

query() {
  local title="$1"
  local promql="$2"

  echo
  echo "## ${title}"
  echo "PromQL: ${promql}"

  local response
  response="$(curl -fsS --get "${PROM_URL}/api/v1/query" --data-urlencode "query=${promql}")"

  local count
  count="$(jq '.data.result | length' <<<"$response")"

  if [[ "$count" == "0" ]]; then
    echo "NO DATA"
    return
  fi

  jq -r '
    .data.result[]
    | {
        metric: .metric,
        value: .value[1]
      }
  ' <<<"$response"
}

metric_names() {
  local title="$1"
  local pattern="$2"

  echo
  echo "## ${title} metric names"
  curl -fsS "${PROM_URL}/api/v1/label/__name__/values" \
    | jq -r '.data[]' \
    | grep -E "$pattern" \
    | sort \
    | head -n 80 || true
}

series_labels() {
  local title="$1"
  local metric="$2"

  echo
  echo "## ${title} series labels"
  curl -fsS --get "${PROM_URL}/api/v1/series" \
    --data-urlencode "match[]={__name__=\"${metric}\"}" \
    | jq -r '.data[:10][]'
}

check_qdrant() {
  echo
  echo "================ Qdrant ================"
  query "Qdrant scrape status" 'up{job="data-stack-qdrant-headless"}'
  query "Qdrant collections" 'collections_total{job="data-stack-qdrant-headless"}'
  query "Qdrant vectors" 'collections_vector_total{job="data-stack-qdrant-headless"}'
  query "Qdrant cluster peers" 'cluster_peers_total{job="data-stack-qdrant-headless"}'
  query "Qdrant memory allocated" 'memory_allocated_bytes{job="data-stack-qdrant-headless"}'
  query "Qdrant scrape duration" 'scrape_duration_seconds{job="data-stack-qdrant-headless"}'
  metric_names "Qdrant" '^(collections_|cluster_|memory_allocated|qdrant_)'
}

check_rabbitmq() {
  echo
  echo "================ RabbitMQ ================"
  query "RabbitMQ scrape status" 'up{job="data-stack-rabbitmq"}'
  query "RabbitMQ memory" 'erlang_vm_memory_bytes_total{job="data-stack-rabbitmq"}'
  query "RabbitMQ process count" 'erlang_vm_process_count{job="data-stack-rabbitmq"}'
  query "RabbitMQ queues" 'rabbitmq_queues{job="data-stack-rabbitmq"}'
  query "RabbitMQ connections" 'rabbitmq_connections{job="data-stack-rabbitmq"}'
  query "RabbitMQ channels" 'rabbitmq_channels{job="data-stack-rabbitmq"}'
  query "RabbitMQ queue messages" 'rabbitmq_queue_messages{job="data-stack-rabbitmq"}'
  query "RabbitMQ ready messages" 'rabbitmq_queue_messages_ready{job="data-stack-rabbitmq"}'
  query "RabbitMQ unacked messages" 'rabbitmq_queue_messages_unacked{job="data-stack-rabbitmq"}'
  query "RabbitMQ publish rate" 'rate(rabbitmq_global_messages_published_total{job="data-stack-rabbitmq"}[5m])'
  metric_names "RabbitMQ" '^(rabbitmq_|erlang_vm_)'
}

check_mysql() {
  echo
  echo "================ MySQL ================"
  query "MySQL exporter scrape status" 'up{job="data-stack-mysql-metrics"}'
  query "MySQL connection status" 'mysql_up{job="data-stack-mysql-metrics"}'
  query "MySQL threads connected" 'mysql_global_status_threads_connected{job="data-stack-mysql-metrics"}'
  query "MySQL threads running" 'mysql_global_status_threads_running{job="data-stack-mysql-metrics"}'
  query "MySQL total connections" 'mysql_global_status_connections{job="data-stack-mysql-metrics"}'
  query "MySQL question rate" 'rate(mysql_global_status_questions{job="data-stack-mysql-metrics"}[5m])'
  query "MySQL command rate" 'sum by (command) (rate(mysql_global_status_commands_total{job="data-stack-mysql-metrics"}[5m]))'
  query "MySQL slow query rate" 'rate(mysql_global_status_slow_queries{job="data-stack-mysql-metrics"}[5m])'
  query "MySQL InnoDB buffer pool hit ratio" 'clamp_min(clamp_max(1 - (increase(mysql_global_status_innodb_buffer_pool_reads{job="data-stack-mysql-metrics"}[5m]) / clamp_min(increase(mysql_global_status_innodb_buffer_pool_read_requests{job="data-stack-mysql-metrics"}[5m]), 1)), 1), 0)'
  metric_names "MySQL" '^mysql_'
}

check_mongodb() {
  echo
  echo "================ MongoDB ================"
  query "MongoDB exporter scrape status" 'up{job="data-stack-mongodb-metrics"}'
  query "MongoDB connection status" 'mongodb_up{job="data-stack-mongodb-metrics"}'
  query "MongoDB connections" "mongodb_connections{job=\"data-stack-mongodb-metrics\"} or mongodb_connections{namespace=\"${NAMESPACE}\"}"
  query "MongoDB operation rate" 'sum by (type) (rate(mongodb_mongod_metrics_operation_total{job="data-stack-mongodb-metrics"}[5m])) or sum by (type) (rate(mongodb_op_counters_total{job="data-stack-mongodb-metrics"}[5m]))'
  query "MongoDB replica member health" 'mongodb_mongod_replset_member_health{job="data-stack-mongodb-metrics"}'
  query "MongoDB replica state" "mongodb_mongod_replset_my_state{job=\"data-stack-mongodb-metrics\"} or mongodb_mongod_replset_my_state{namespace=\"${NAMESPACE}\"}"
  query "MongoDB scrape duration" 'scrape_duration_seconds{job="data-stack-mongodb-metrics"}'
  series_labels "MongoDB connections" "mongodb_connections"
  series_labels "MongoDB operation counters" "mongodb_op_counters_total"
  series_labels "MongoDB replica state" "mongodb_mongod_replset_my_state"
  metric_names "MongoDB" '^mongodb_'
}

main() {
  case "$COMPONENT" in
    -h|--help|help)
      usage
      exit 0
      ;;
    all|qdrant|rabbitmq|mysql|mongodb)
      ;;
    *)
      echo "Unknown component: ${COMPONENT}" >&2
      usage
      exit 1
      ;;
  esac

  require_cmd curl
  require_cmd jq

  if [[ "$PORT_FORWARD" == "true" ]]; then
    start_port_forward
  fi

  echo "Prometheus URL: ${PROM_URL}"
  echo "Namespace: ${NAMESPACE}"

  case "$COMPONENT" in
    all)
      check_qdrant
      check_rabbitmq
      check_mysql
      check_mongodb
      ;;
    qdrant) check_qdrant ;;
    rabbitmq) check_rabbitmq ;;
    mysql) check_mysql ;;
    mongodb) check_mongodb ;;
  esac
}

main "$@"
