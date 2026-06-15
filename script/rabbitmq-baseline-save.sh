#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-skala3-finalproj-class2-team7}"
POD="${POD:-data-stack-rabbitmq-0}"
VHOST="${VHOST:-/}"
OUT_ROOT="${OUT_ROOT:-/tmp/rabbitmq-baseline}"
LABEL_FILTER="${LABEL_FILTER:-admin\.ingest|data-ingestion\.ingest|dlq}"
DRY_RUN="${DRY_RUN:-false}"

if [[ "${DRY_RUN}" != "false" ]]; then
  echo "DRY_RUN is enabled. Commands are printed without running against RabbitMQ."
  echo "NS=${NS}"
  echo "POD=${POD}"
  echo "VHOST=${VHOST}"
  echo "OUT_ROOT=${OUT_ROOT}"
  echo "LABEL_FILTER=${LABEL_FILTER}"
  exit 0
fi

TS=$(date -u +"%Y%m%dT%H%M%SZ")
OUT_DIR="${OUT_ROOT}/rabbitmq-baseline-${TS}"

mkdir -p "${OUT_DIR}"

kubectl -n "${NS}" exec "${POD}" -- \
  rabbitmqctl list_bindings --no-table-headers \
    source_name source_kind destination_name destination_kind routing_key arguments \
| rg "${LABEL_FILTER}" > "${OUT_DIR}/bindings.txt"

kubectl -n "${NS}" exec "${POD}" -- \
  rabbitmqctl list_queues -p "${VHOST}" name messages arguments > "${OUT_DIR}/queues_messages_and_args.txt"

kubectl -n "${NS}" exec "${POD}" -- \
  rabbitmqctl list_exchanges -p "${VHOST}" name type > "${OUT_DIR}/exchanges.txt"

printf 'Baseline capture complete\n' > "${OUT_DIR}/status.txt"
{
  echo "captured_at_utc: ${TS}"
  echo "namespace: ${NS}"
  echo "pod: ${POD}"
  echo "vhost: ${VHOST}"
  echo "out_dir: ${OUT_DIR}"
} > "${OUT_DIR}/metadata.txt"

echo "Saved baseline to: ${OUT_DIR}"
