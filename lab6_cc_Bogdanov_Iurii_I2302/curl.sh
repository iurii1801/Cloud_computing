#!/usr/bin/env bash
set -euo pipefail

# ALB DNS
ALB_DNS="project-alb-1356575818.us-east-1.elb.amazonaws.com"

# Настройки нагрузки
THREADS=${1:-10}         # если не передать параметр — будет 10 потоков
SECONDS_LOAD=${2:-60}    # если не передать параметр — будет 60 секунд
TOOL=${3:-curl}          # по умолчанию: curl

TARGET="http://${ALB_DNS}/load?seconds=${SECONDS_LOAD}"

echo "========================================="
echo " Target:   ${TARGET}"
echo " Threads:  ${THREADS}"
echo " Seconds:  ${SECONDS_LOAD}"
echo " Tool:     ${TOOL}"
echo "========================================="

case "${TOOL}" in
  curl)
    echo "[*] Generating load with curl (infinite loop per thread)..."
    for i in $(seq 1 "${THREADS}"); do
      (
        while true; do
          curl -s "${TARGET}" > /dev/null
        done
      ) &
    done
    echo "Load started. Press CTRL+C to stop."
    wait
    ;;

  ab)
    if ! command -v ab >/dev/null 2>&1; then
      echo "Error: 'ab' is not installed."
      exit 1
    fi
    echo "[*] Generating load with ab..."
    TOTAL=$(( THREADS * 100 ))
    ab -n "${TOTAL}" -c "${THREADS}" "${TARGET}/"
    ;;

  hey)
    if ! command -v hey >/dev/null 2>&1; then
      echo "Error: 'hey' is not installed."
      exit 1
    fi
    echo "[*] Generating load with hey..."
    hey -z "${SECONDS_LOAD}s" -c "${THREADS}" "${TARGET}"
    ;;

  *)
    echo "Unknown tool '${TOOL}'. Use: curl | ab | hey"
    exit 1
    ;;
esac
