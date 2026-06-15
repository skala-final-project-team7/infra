#!/usr/bin/env bash
set -euo pipefail

BEFORE=""
AFTER=""
FILTER="${FILTER:-.*}"

usage() {
  cat <<EOF
Usage:
  rabbitmq-baseline-compare.sh --before <before_dir> --after <after_dir> [--filter <regex>]

Options:
  --before   Path to baseline snapshot directory saved before test
  --after    Path to baseline snapshot directory saved after test
  --filter   Regex filter for queue names in message delta report (default: .*)
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --before)
      BEFORE="$2"
      shift 2
      ;;
    --after)
      AFTER="$2"
      shift 2
      ;;
    --filter)
      FILTER="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${BEFORE}" || -z "${AFTER}" ]]; then
  usage
  exit 1
fi

for f in bindings.txt queues_messages_and_args.txt exchanges.txt; do
  if [[ ! -f "${BEFORE}/${f}" ]]; then
    echo "Missing file: ${BEFORE}/${f}"
    exit 1
  fi
  if [[ ! -f "${AFTER}/${f}" ]]; then
    echo "Missing file: ${AFTER}/${f}"
    exit 1
  fi
done

echo "RabbitMQ baseline compare"
echo "Before : ${BEFORE}"
echo "After  : ${AFTER}"
echo "Filter : ${FILTER}"
echo

compare_file() {
  local file=$1
  echo "===== ${file} ====="
  if cmp -s "${BEFORE}/${file}" "${AFTER}/${file}"; then
    echo "No changes."
  else
    diff -u "${BEFORE}/${file}" "${AFTER}/${file}"
  fi
  echo
}

compare_file bindings.txt
compare_file queues_messages_and_args.txt
compare_file exchanges.txt

TMP_BEFORE=$(mktemp)
TMP_AFTER=$(mktemp)
TMP_DELTA=$(mktemp)
trap 'rm -f "${TMP_BEFORE}" "${TMP_AFTER}" "${TMP_DELTA}"' EXIT

awk -F'\t' '{
  if ($1 == "name" || $1 == "") {
    next
  }
  gsub(/\r/, "", $1)
  gsub(/\r/, "", $2)
  if ($1 != "") {
    printf "%s\t%s\n", $1, $2
  }
}' "${BEFORE}/queues_messages_and_args.txt" | sort > "${TMP_BEFORE}"

awk -F'\t' '{
  if ($1 == "name" || $1 == "") {
    next
  }
  gsub(/\r/, "", $1)
  gsub(/\r/, "", $2)
  if ($1 != "") {
    printf "%s\t%s\n", $1, $2
  }
}' "${AFTER}/queues_messages_and_args.txt" | sort > "${TMP_AFTER}"

awk -F'\t' -v filter="${FILTER}" '
  NR==FNR {
    before[$1] = $2
    queues[$1] = 1
    next
  }
  {
    after[$1] = $2
    queues[$1] = 1
  }
  END {
    for (q in queues) {
      if (q !~ filter) {
        continue
      }
      b = (q in before) ? before[q] : "MISSING"
      a = (q in after) ? after[q] : "MISSING"
      if (b == "MISSING" || a == "MISSING") {
        delta = "N/A"
      } else {
        delta = a - b
      }
      if ((b != "MISSING" && a != "MISSING" && delta != 0) || b == "MISSING" || a == "MISSING") {
        printf "%s\t%s\t%s\t%s\n", q, b, a, delta
      }
    }
  }
' "${TMP_BEFORE}" "${TMP_AFTER}" > "${TMP_DELTA}"

echo "===== Queue message delta (changed rows) ====="
if [[ -s "${TMP_DELTA}" ]]; then
  printf "queue\tbefore_messages\tafter_messages\tdelta\n"
  sort -t$'\t' -k1,1 "${TMP_DELTA}"
else
  echo "No message count changes."
fi
