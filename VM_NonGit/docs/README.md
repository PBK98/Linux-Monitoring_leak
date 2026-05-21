1. 요구사항 수행 내역서(문서 1개)

==================	수행 내역	==================

◦	설정/명령어 기록 (SSH 포트, 방화벽 규칙, 계정/그룹/ACL, 디렉토리/권한, 환경 변수, cron 등록 등)


==================	필수 증거 자료 체크리스트	==================

◦	SSH 포트 변경(20022) 및 Root 원격 접속 차단 설정 확인 내역
```bash
root@ubuntu:~# grep -E '^Port |^PermitRootLogin' /etc/ssh/sshd_config
```

```bash
Port 20022
PermitRootLogin no
```

◦	방화벽(UFW 또는 firewalld) 활성화 및 20022/tcp, 15034/tcp만 허용 내역

```bash
root@ubuntu:~# ufw status verbose
```

```bash
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
20022/tcp                  ALLOW IN    Anywhere                  
15034/tcp                  ALLOW IN    Anywhere                  
20022/tcp (v6)             ALLOW IN    Anywhere (v6)             
15034/tcp (v6)             ALLOW IN    Anywhere (v6)
```


◦	계정/그룹(agent-admin/dev/test, agent-common/core) 생성 확인 내역
```bash
root@ubuntu:~# id agent-admin
```

```bash
uid=1000(agent-admin) gid=1000(agent-common) groups=1000(agent-common),1001(agent-core)
```

```bash
root@ubuntu:~# id agent-admin && id agent-dev && id agent-test
```

```bash
uid=1000(agent-admin) gid=1000(agent-common) groups=1000(agent-common),1001(agent-core)
uid=1001(agent-dev) gid=1000(agent-common) groups=1000(agent-common),1001(agent-core)
uid=1002(agent-test) gid=1000(agent-common) groups=1000(agent-common)
```

◦	디렉토리 구조 및 권한(ACL 포함) 확인 내역

```bash
root@ubuntu:~# ls -ld /home/agent-admin/agent-app/upload_files

drwxrwx--- 1 agent-test agent-common 0 May 19 19:19 /home/agent-admin/agent-app/upload_files

root@ubuntu:~# ls -ld /home/agent-admin/agent-app/api_keys

drwxrwx--- 1 agent-admin agent-core 24 May 19 19:19 /home/agent-admin/agent-app/api_keys

root@ubuntu:~# ls -ld /var/log/agent-app

drwxrwx--- 1 agent-admin agent-core 94 May 19 20:44 /var/log/agent-app
```
◦	환경변수 확인 내역

```bash
agent-admin@ubuntu:~/agent-app/bin$ cat /etc/profile.d/agent-app.sh
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
export AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key
export AGENT_LOG_DIR=/var/log/agent-app

```

◦	앱 Boot Sequence 5단계 [OK] 및 “Agent READY” 확인 내역

```bash
agent-admin@ubuntu:~/agent-app/app$ ./agent-app 

>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]
 ... Running as service user 'agent-admin' (uid=1000)
[2/5] Verifying Environment Variables     [OK]
 ... All required Envs correct
[3/5] Checking Required Files             [OK]
 ... Verified 'secret.key' with correct key string.
[4/5] Checking Port Availability          [OK]
 ... Port 15034 is available.
[5/5] Verifying Log Permission            [OK]
 ... Log directory is writable: /var/log/agent-app
------------------------------------------------------------
All Boot Checks Passed!
Agent READY

2026-05-19 21:43:43,388 [INFO] [SafetyGuard] Process priority lowered (nice=10).
2026-05-19 21:43:43,389 [INFO] Agent listening at port 15034
2026-05-19 21:43:43,389 [INFO] === Agent Started. Beginning resource cycle. ===
2026-05-19 21:43:43,389 [INFO] --- Step Info: Mode=UP, CPU Lv=1, Mem=0MB ---
2026-05-19 21:43:43,391 [INFO] [Memory] Increasing... (+25 MB) Total: 25 MB
2026-05-19 21:43:43,409 [INFO] [CPU] Level 1 workload completed. Duration: 0.02s
2026-05-19 21:43:44,415 [INFO] --- Step Info: Mode=UP, CPU Lv=2, Mem=25MB ---
2026-05-19 21:43:44,421 [INFO] [Memory] Increasing... (+25 MB) Total: 50 MB
2026-05-19 21:43:44,484 [INFO] [CPU] Level 2 workload completed. Duration: 0.06s
2026-05-19 21:43:45,489 [INFO] --- Step Info: Mode=UP, CPU Lv=3, Mem=50MB ---
2026-05-19 21:43:45,495 [INFO] [Memory] Increasing... (+25 MB) Total: 75 MB
2026-05-19 21:43:45,580 [INFO] [CPU] Level 3 workload completed. Duration: 0.08s
2026-05-19 21:43:46,581 [INFO] --- Step Info: Mode=UP, CPU Lv=4, Mem=75MB ---
2026-05-19 21:43:46,589 [INFO] [Memory] Increasing... (+25 MB) Total: 100 MB
2026-05-19 21:43:46,690 [INFO] [CPU] Level 4 workload completed. Duration: 0.10s
2026-05-19 21:43:47,695 [INFO] --- Step Info: Mode=UP, CPU Lv=5, Mem=100MB ---
2026-05-19 21:43:47,701 [INFO] [Memory] Increasing... (+25 MB) Total: 125 MB
2026-05-19 21:43:47,822 [INFO] [CPU] Level 5 workload completed. Duration: 0.12s
^C2026-05-19 21:43:48,599 [WARNING] Stop signal received. Terminating now...
2026-05-19 21:43:48,599 [INFO] === Agent Shutdown. Releasing resources. ===
```
◦	monitor.sh 실행 결과(프로세스/포트/리소스/경고) 내역

```bash
agent-admin@ubuntu:~/agent-app/bin$ ./monitor.sh 
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent-app'... [OK] (PID: 10403)
Checking port 15034... [OK]

[RESOURCE MONITORING]
CPU Usage : 1.20%
MEM Usage : 0.0%
DISK Used : 1%
MEM RSS : 3968

====== STATISTICS REPORT ======
[CPU]
Average : 0.0%
Maximum : 1.2% at 2026-05-19 21:45:31
Minimum : 0.0% at 2026-05-19 19:21:01
[Memory]
Average : 0.0%
Maximum : 0.0% at 2026-05-19 19:20:01
Minimum : 0.0% at 2026-05-19 19:20:01
[Samples]
Data Points: 145 samples

[INFO] Log appended: /var/log/agent-app/monitor.log
```

◦	/var/log/agent-app/monitor.log 누적 기록 확인(최근 라인) 내역

```bash
agent-admin@ubuntu:~/agent-app/bin$ tail /var/log/agent-app/monitor.log 

[2026-05-19 21:36:01] PID:6439 CPU:0.00% MEM:0.0% DISK_USED:1% MEM_RSS:2116 KB
[2026-05-19 21:37:02] PID:6439 CPU:0.00% MEM:0.0% DISK_USED:1% MEM_RSS:2116 KB
[2026-05-19 21:38:01] PID:6439 CPU:0.00% MEM:0.0% DISK_USED:1% MEM_RSS:2116 KB
[2026-05-19 21:39:01] PID:6439 CPU:0.00% MEM:0.0% DISK_USED:1% MEM_RSS:2116 KB
[2026-05-19 21:40:02] PID:6439 CPU:0.00% MEM:0.0% DISK_USED:1% MEM_RSS:2116 KB
[2026-05-19 21:41:01] PID:6439 CPU:0.00% MEM:0.0% DISK_USED:1% MEM_RSS:2116 KB
[2026-05-19 21:42:01] PID:6439 CPU:0.00% MEM:0.0% DISK_USED:1% MEM_RSS:2116 KB
[2026-05-19 21:43:02] PID:6439 CPU:0.00% MEM:0.0% DISK_USED:1% MEM_RSS:2116 KB
[2026-05-19 21:45:31] PID:10403 CPU:1.20% MEM:0.0% DISK_USED:1% MEM_RSS:3968 KB
[2026-05-19 21:46:01] PID:10403 CPU:0.20% MEM:0.0% DISK_USED:1% MEM_RSS:3968 KB
```

◦	crontab 매분 실행 등록 및 자동 실행 확인(1분 후 로그 증가) 내역

```bash
agent-admin@ubuntu:~/agent-app/bin$ crontab -l

* * * * * . /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1

0 3 * * * . /etc/profile.d/agent-app.sh; /home/agent-admin/agent-app/bin/log_archive.sh >> /var/log/agent-app/archive.log 2>&1
```


2. 자동화 스크립트 소스코드
    
==========  monitor.sh : 시스템 상태 수집 및 로깅 스크립트  ==========

```bash
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

```