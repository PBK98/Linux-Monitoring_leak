#!/usr/bin/env bash
set -u
LOG_FILE="/var/log/agent-app/monitor.log"
APP_NAME="agent-app"
APP_PORT="15034"
CPU_THRESHOLD=20
MEM_THRESHOLD=10
DISK_THRESHOLD=80

ts() { date '+%Y-%m-%d %H:%M:%S'; }

PID=$(pgrep -f "${APP_NAME}" | head -n 1 || true)
echo "====== SYSTEM MONITOR RESULT ======"
echo
echo "[HEALTH CHECK]"
if [[ -n "$PID" ]]; then
  echo "Checking process '${APP_NAME}'... [OK] (PID: ${PID})"
else
  echo "Checking process '${APP_NAME}'... [ERROR]"
  exit 1
fi

if ss -tulnp | grep -q ":${APP_PORT} "; then
  echo "Checking port ${APP_PORT}... [OK]"
else
  echo "Checking port ${APP_PORT}... [ERROR]"
  exit 1
fi

echo
echo "[RESOURCE MONITORING]"
CPU=$(ps -p "$PID" -o %cpu= | awk '{printf "%.2f", $1}')
MEM=$(ps -p "$PID" -o %mem= | awk '{printf "%.1f", $1}')
DISK=$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')
MEM_RSS=$(ps -p "$PID" -o rss= | awk '{print $1}')

echo "CPU Usage : ${CPU}%"
echo "MEM Usage : ${MEM}%"
echo "DISK Used : ${DISK}%"
echo "MEM RSS : ${MEM_RSS}"

awk "BEGIN{exit !($CPU > $CPU_THRESHOLD)}" && echo "[WARNING] CPU threshold exceeded (${CPU}% > ${CPU_THRESHOLD}%)"
awk "BEGIN{exit !($MEM > $MEM_THRESHOLD)}" && echo "[WARNING] MEM threshold exceeded (${MEM}% > ${MEM_THRESHOLD}%)"
[[ "$DISK" -gt "$DISK_THRESHOLD" ]] && echo "[WARNING] DISK threshold exceeded (${DISK}% > ${DISK_THRESHOLD}%)"

mkdir -p "$(dirname "$LOG_FILE")"
printf '[%s] PID:%s CPU:%s%% MEM:%s%% DISK_USED:%s%% MEM_RSS:%s KB\n' "$(ts)" "$PID" "$CPU" "$MEM" "$DISK" "$MEM_RSS" >> "$LOG_FILE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$SCRIPT_DIR/report.sh" ]]; then
  "$SCRIPT_DIR/report.sh"
fi

echo
echo "[INFO] Log appended: ${LOG_FILE}"
