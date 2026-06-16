#!/usr/bin/env bash
set -u

ts() { date '+%Y-%m-%d %H:%M:%S'; }

# 포트번호가 APP_PORT(15034)인 프로세스 APP_NAME(agent-app-leak)의 PID 찾기
PID=$(ss -lntp | grep ":${APP_PORT}" | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -n 1)

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
# Process resource usage
# ps pcpu is based on CPU time and can exceed 100 on multi-core systems.
# PRO_CPU is normalized to the process share of total CPU capacity.
CPU_CORES=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
PRO_CPU_RAW=$(ps -p "$PID" -o pcpu= | awk '{print $1}')
[[ -z "${PRO_CPU_RAW}" || "${PRO_CPU_RAW}" == "-" ]] && PRO_CPU_RAW="0.0"
PRO_CPU=$(awk "BEGIN {
  if ($CPU_CORES > 0)
    printf \"%.2f\", ($PRO_CPU_RAW / $CPU_CORES)
  else
    printf \"%.2f\", $PRO_CPU_RAW
}")
MEM_RSS=$(ps -p "$PID" -o rss= | awk '{print $1}')
MEM_TOTAL=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)

PRO_MEM=$(awk "BEGIN {
  if ($MEM_TOTAL > 0)
    printf \"%.3f\", ($MEM_RSS / $MEM_TOTAL) * 100
  else
    printf \"0.000\"
}")

# Disk usage
DISK=$(df -P "$AGENT_HOME" | awk 'NR==2 {gsub("%","",$5); print $5}')

# System memory usage
SYS_MEM_TOTAL=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
SYS_MEM_AVAILABLE=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
SYS_MEM_USED=$((SYS_MEM_TOTAL - SYS_MEM_AVAILABLE))

SYS_MEM=$(awk "BEGIN {
  if ($SYS_MEM_TOTAL > 0)
    printf \"%.2f\", ($SYS_MEM_USED / $SYS_MEM_TOTAL) * 100
  else
    printf \"0.00\"
}")

# SystemCPU usage
read -r _ USER1 NICE1 SYSTEM1 IDLE1 IOWAIT1 IRQ1 SOFTIRQ1 STEAL1 _ < /proc/stat
IDLE_ALL1=$((IDLE1 + IOWAIT1))
TOTAL1=$((USER1 + NICE1 + SYSTEM1 + IDLE1 + IOWAIT1 + IRQ1 + SOFTIRQ1 + STEAL1))

sleep 1

read -r _ USER2 NICE2 SYSTEM2 IDLE2 IOWAIT2 IRQ2 SOFTIRQ2 STEAL2 _ < /proc/stat
IDLE_ALL2=$((IDLE2 + IOWAIT2))
TOTAL2=$((USER2 + NICE2 + SYSTEM2 + IDLE2 + IOWAIT2 + IRQ2 + SOFTIRQ2 + STEAL2))

TOTAL_DIFF=$((TOTAL2 - TOTAL1))
IDLE_DIFF=$((IDLE_ALL2 - IDLE_ALL1))

SYSCPU=$(awk "BEGIN {
  if ($TOTAL_DIFF > 0)
    printf \"%.2f\", (100 * ($TOTAL_DIFF - $IDLE_DIFF) / $TOTAL_DIFF)
  else
    printf \"0.00\"
}")

echo "Process CPU Share       : ${PRO_CPU}% of total CPU (${CPU_CORES} cores)"
echo "Process CPU ps %CPU     : ${PRO_CPU_RAW}%"
echo "Process MEM Share       : ${PRO_MEM}% of total MEM"
echo "Process MEM RSS         : ${MEM_RSS} KB"
echo "System CPU Usage        : ${SYSCPU}%"
echo "System MEM Usage        : ${SYS_MEM}%"
echo "System MEM Used         : ${SYS_MEM_USED} KB"
echo "System MEM Total        : ${SYS_MEM_TOTAL} KB"
echo "DISK Used               : ${DISK}%"

# Process threshold warning
awk "BEGIN{exit !($PRO_CPU > $CPU_THRESHOLD)}" && echo "[WARNING] Process CPU share threshold exceeded (${PRO_CPU}% > ${CPU_THRESHOLD}%)"
awk "BEGIN{exit !($PRO_MEM > $MEM_THRESHOLD)}" && echo "[WARNING] Process MEM threshold exceeded (${PRO_MEM}% > ${MEM_THRESHOLD}%)"

# System threshold warning
awk "BEGIN{exit !($SYSCPU > $SYS_CPU_THRESHOLD)}" && echo "[WARNING] SystemCPU threshold exceeded (${SYSCPU}% > ${SYS_CPU_THRESHOLD}%)"
awk "BEGIN{exit !($SYS_MEM > $SYS_MEM_THRESHOLD)}" && echo "[WARNING] System MEM threshold exceeded (${SYS_MEM}% > ${SYS_MEM_THRESHOLD}%)"

# Disk threshold warning
[[ "$DISK" -gt "$DISK_THRESHOLD" ]] && echo "[WARNING] DISK threshold exceeded (${DISK}% > ${DISK_THRESHOLD}%)"

mkdir -p "$(dirname "$LOG_FILE")"
printf '[%s] PID:%s PRO_CPU:%s%% PRO_MEM:%s%% MEM_RSS:%sKB\n' \
  "$(ts)" \
  "$PID" \
  "$PRO_CPU" \
  "$PRO_MEM" \
  "$MEM_RSS" \
  >> "$LOG_FILE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$SCRIPT_DIR/report.sh" ]]; then
  "$SCRIPT_DIR/report.sh"
fi

echo
echo "[INFO] Log appended: ${LOG_FILE}"
