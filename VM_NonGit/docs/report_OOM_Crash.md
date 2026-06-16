# [Bug] OOM Crash - Memory Leak으로 인한 프로세스 비정상 종료

## 1. Description (현상 설명)

### 장애 현상

`agent-app-leak` 실행 후 시간이 지남에 따라 프로세스의 메모리 사용량이 지속적으로 증가하였다.

메모리 사용량이 설정된 제한 값을 초과한 이후 프로세스가 비정상 종료되었으며, 서비스 포트(15034) 또한 비활성화되었다.

### 발생 조건

* `agent-app-leak` 실행
* `MEMORY_LIMIT`를 낮은 값으로 설정
* 장시간 동작
* 메모리 사용량 지속 증가
* OOM(Out Of Memory) 발생

### 재현 환경

```bash
export MEMORY_LIMIT=256
```

---

## 2. Evidence & Logs (증거 자료)

### agent-app-leak 실행 화면
```bash
[6/6] Verifying Mission Environment       [OK]
   ... MEMORY_LIMIT=256MB, CPU_MAX_OCCUPY=90%, MULTI_THREAD_ENABLE=False
------------------------------------------------------------
All Boot Checks Passed!
Agent READY
2026-06-16 17:49:46,375 [INFO] [SafetyGuard] Process priority lowered (nice=10).
2026-06-16 17:49:46,375 [INFO] Agent listening at port 15034

==================================================
 [ Agent Initiate ] Resource Check
==================================================
 [ MEMORY ] Limit: 256MB 		[ WARNING: Recommend Over 256MB ]
 [ CPU    ] Limit: 90%  		[ WARNING: Recommend Under 50% ]
 [ THREAD ] Concurrency: False 		[ OK ]
--------------------------------------------------
 >>> SYSTEM STATUS: STABLE. STARTING WORKLOAD MONITORING...
==================================================

2026-06-16 17:49:48,405 [INFO] [MemoryWorker] Current Heap: 25MB
2026-06-16 17:49:51,438 [INFO] [MemoryWorker] Current Heap: 50MB
2026-06-16 17:49:54,472 [INFO] [MemoryWorker] Current Heap: 75MB
2026-06-16 17:49:57,508 [INFO] [MemoryWorker] Current Heap: 100MB
2026-06-16 17:50:00,543 [INFO] [MemoryWorker] Current Heap: 125MB
2026-06-16 17:50:03,576 [INFO] [MemoryWorker] Current Heap: 150MB
2026-06-16 17:50:06,608 [INFO] [MemoryWorker] Current Heap: 175MB
2026-06-16 17:50:09,644 [INFO] [MemoryWorker] Current Heap: 200MB
2026-06-16 17:50:12,674 [INFO] [MemoryWorker] Current Heap: 225MB
2026-06-16 17:50:15,700 [INFO] [MemoryWorker] Current Heap: 250MB
2026-06-16 17:50:18,732 [INFO] [MemoryWorker] Current Heap: 275MB
2026-06-16 17:50:18,732 [CRITICAL] [MemoryGuard] Memory limit exceeded (275MB >= 256MB) / (Recommend Over 256MB)
2026-06-16 17:50:18,732 [CRITICAL] [MemoryGuard] Self-terminating process 4864 to prevent system instability.


>>> [SYSTEM] SELF-TERMINATED (Memory Limit Exceeded) <<<

Killed
```

### MEMORY_LIMIT 512MB로 증가 후

```bash
[6/6] Verifying Mission Environment       [OK]
   ... MEMORY_LIMIT=512MB, CPU_MAX_OCCUPY=40%, MULTI_THREAD_ENABLE=False
------------------------------------------------------------
All Boot Checks Passed!
Agent READY
2026-06-16 17:50:43,352 [INFO] [SafetyGuard] Process priority lowered (nice=10).
2026-06-16 17:50:43,352 [INFO] Agent listening at port 15034

==================================================
 [ Agent Initiate ] Resource Check
==================================================
 [ MEMORY ] Limit: 512MB 		[ OK ]
 [ CPU    ] Limit: 40%  		[ OK ]
 [ THREAD ] Concurrency: False 		[ OK ]
--------------------------------------------------
 >>> SYSTEM STATUS: STABLE. STARTING WORKLOAD MONITORING...
==================================================

2026-06-16 17:50:45,367 [INFO] >>> Scenario Selected: [Healthy System Monitoring]

>>> [SYSTEM] ALL CONFIGURATIONS OPTIMAL. RUNNING STABILITY TEST... <<<

2026-06-16 17:50:45,368 [INFO] [Scheduler] Task Scheduler Initialized.
2026-06-16 17:50:45,368 [INFO] [Scheduler] Registered Tasks: ['Thread-A', 'Thread-B', 'Thread-C']
2026-06-16 17:50:45,368 [INFO] [Scheduler] Starting task execution...
2026-06-16 17:50:45,368 [INFO] [Thread-A] Task Started. Calculating... (20%)
2026-06-16 17:50:45,424 [INFO] [Thread-A] Calculating... (40%)
2026-06-16 17:50:45,476 [INFO] [Thread-A] Preempted. Progress saved at (40%)
2026-06-16 17:50:45,529 [INFO] [Thread-B] Task Started. Calculating... (20%)
2026-06-16 17:50:45,585 [INFO] [Thread-B] Calculating... (40%)
2026-06-16 17:50:45,641 [INFO] [Thread-B] Preempted. Progress saved at (40%)
2026-06-16 17:50:45,697 [INFO] [Thread-C] Task Started. Calculating... (20%)
2026-06-16 17:50:45,753 [INFO] [Thread-C] Calculating... (40%)
2026-06-16 17:50:45,809 [INFO] [Thread-C] Preempted. Progress saved at (40%)
2026-06-16 17:50:45,865 [INFO] [Thread-A] Resumed. Calculating... (60%)
2026-06-16 17:50:45,921 [INFO] [Thread-A] Calculating... (80%)
2026-06-16 17:50:45,975 [INFO] [Thread-A] Preempted. Progress saved at (80%)
2026-06-16 17:50:46,032 [INFO] [Thread-B] Resumed. Calculating... (60%)
2026-06-16 17:50:46,088 [INFO] [Thread-B] Calculating... (80%)
2026-06-16 17:50:46,143 [INFO] [Thread-B] Preempted. Progress saved at (80%)
2026-06-16 17:50:46,199 [INFO] [Thread-C] Resumed. Calculating... (60%)
2026-06-16 17:50:46,255 [INFO] [Thread-C] Calculating... (80%)
2026-06-16 17:50:46,311 [INFO] [Thread-C] Preempted. Progress saved at (80%)
2026-06-16 17:50:46,367 [INFO] [Thread-A] Resumed. Calculating... (100%)
2026-06-16 17:50:46,423 [INFO] [Thread-B] Resumed. Calculating... (100%)
2026-06-16 17:50:46,475 [INFO] [Thread-C] Resumed. Calculating... (100%)
2026-06-16 17:50:46,531 [INFO] [Scheduler] All tasks completed.
2026-06-16 17:50:46,547 [INFO] [MemoryWorker] Current Heap: 25MB
2026-06-16 17:50:46,547 [INFO] [CpuWorker] Started. Maximum CPU Limit: 40%
2026-06-16 17:50:46,547 [INFO] [CpuWorker] Current Load: 5.00%
2026-06-16 17:50:49,583 [INFO] [MemoryWorker] Current Heap: 50MB
2026-06-16 17:50:49,674 [INFO] [CpuWorker] Current Load: 6.28%
2026-06-16 17:50:52,616 [INFO] [MemoryWorker] Current Heap: 75MB
2026-06-16 17:50:52,805 [INFO] [CpuWorker] Current Load: 13.48%
2026-06-16 17:50:55,645 [INFO] [MemoryWorker] Current Heap: 100MB
2026-06-16 17:50:55,935 [INFO] [CpuWorker] Current Load: 14.41%
2026-06-16 17:50:58,681 [INFO] [MemoryWorker] Current Heap: 125MB
2026-06-16 17:50:59,067 [INFO] [CpuWorker] Current Load: 15.41%
2026-06-16 17:51:01,714 [INFO] [MemoryWorker] Current Heap: 150MB
2026-06-16 17:51:02,196 [INFO] [CpuWorker] Current Load: 22.68%
2026-06-16 17:51:04,744 [INFO] [MemoryWorker] Current Heap: 175MB
2026-06-16 17:51:05,312 [INFO] [CpuWorker] Current Load: 30.83%
2026-06-16 17:51:07,429 [INFO] [CpuWorker] Peak reached (40.00%). Starting cooldown...
2026-06-16 17:51:07,779 [INFO] [MemoryWorker] Current Heap: 200MB
2026-06-16 17:51:08,437 [INFO] [CpuWorker] Current Load: 40.00%
2026-06-16 17:51:10,808 [INFO] [MemoryWorker] Current Heap: 225MB
2026-06-16 17:51:11,566 [INFO] [CpuWorker] Current Load: 38.16%
2026-06-16 17:51:13,839 [INFO] [MemoryWorker] Current Heap: 250MB
2026-06-16 17:51:14,689 [INFO] [CpuWorker] Current Load: 29.40%
2026-06-16 17:51:16,870 [INFO] [MemoryWorker] Current Heap: 275MB
2026-06-16 17:51:17,816 [INFO] [CpuWorker] Current Load: 23.81%
2026-06-16 17:51:19,903 [INFO] [MemoryWorker] Current Heap: 300MB

...
```


### monitor.sh 로그

```bash
[2026-06-02 18:51:36] PID:5518 PRO_CPU:-% PRO_MEM:1.287% PRO_MEM_RSS:158228KB SYSCPU:0.39% SYS_MEM:7.03% SYS_MEM_USED:863908KB SYS_MEM_TOTAL:12293676KB DISK_USED:2%
[2026-06-02 18:51:39] PID:5518 PRO_CPU:-% PRO_MEM:1.495% PRO_MEM_RSS:183832KB SYSCPU:0.30% SYS_MEM:7.48% SYS_MEM_USED:919552KB SYS_MEM_TOTAL:12293676KB DISK_USED:2%
[2026-06-02 18:51:42] PID:5518 PRO_CPU:-% PRO_MEM:1.704% PRO_MEM_RSS:209436KB SYSCPU:0.20% SYS_MEM:7.34% SYS_MEM_USED:901852KB SYS_MEM_TOTAL:12293676KB DISK_USED:2%
[2026-06-02 18:51:44] PID:5518 PRO_CPU:-% PRO_MEM:1.912% PRO_MEM_RSS:235040KB SYSCPU:0.20% SYS_MEM:7.65% SYS_MEM_USED:940436KB SYS_MEM_TOTAL:12293676KB DISK_USED:2%
[2026-06-02 18:51:48] PID:5518 PRO_CPU:-% PRO_MEM:2.120% PRO_MEM_RSS:260644KB SYSCPU:0.29% SYS_MEM:8.07% SYS_MEM_USED:992464KB SYS_MEM_TOTAL:12293676KB DISK_USED:2%
[2026-06-02 18:51:49] PID:5518 PRO_CPU:-% PRO_MEM:2.328% PRO_MEM_RSS:286248KB SYSCPU:0.20% SYS_MEM:8.43% SYS_MEM_USED:1036356KB SYS_MEM_TOTAL:12293676KB DISK_USED:2%
```

프로세스 RSS(Resident Set Size)가 지속적으로 증가하는 것을 확인하였다.

### 프로세스 상태 확인

```bash
agent-admin@ubuntu-intel:~/agent-app-leak/bin$ ps -p 6164 -o pid,%mem,rss
```

결과:

```bash
    PID %MEM   RSS
   6164  0.6 81612
agent-admin@ubuntu-intel:~/agent-app-leak/bin$ ps -p 6164 -o pid,%mem,rss
    PID %MEM   RSS
   6164  0.8 107216
agent-admin@ubuntu-intel:~/agent-app-leak/bin$ ps -p 6164 -o pid,%mem,rss
    PID %MEM   RSS
   6164  1.0 132820
agent-admin@ubuntu-intel:~/agent-app-leak/bin$ ps -p 6164 -o pid,%mem,rss
    PID %MEM   RSS
   6164  1.2 158424
agent-admin@ubuntu-intel:~/agent-app-leak/bin$ ps -p 6164 -o pid,%mem,rss
    PID %MEM   RSS
   6164  1.4 184028
agent-admin@ubuntu-intel:~/agent-app-leak/bin$ ps -p 6164 -o pid,%mem,rss
    PID %MEM   RSS
   6164  1.7 209632
agent-admin@ubuntu-intel:~/agent-app-leak/bin$ ps -p 6164 -o pid,%mem,rss
    PID %MEM   RSS
   6164  1.9 235236
agent-admin@ubuntu-intel:~/agent-app-leak/bin$ ps -p 6164 -o pid,%mem,rss
    PID %MEM   RSS
   6164  2.1 260840
agent-admin@ubuntu-intel:~/agent-app-leak/bin$ ps -p 6164 -o pid,%mem,rss
    PID %MEM   RSS
   6164  2.3 286444
```

### 장애 발생 이후 프로세스 확인

```bash
pgrep -f agent-app-leak
```

결과:

```text
(no output)
```

프로세스 종료 확인.

### 포트 상태 확인

```bash
ss -tulnp | grep 15034
```

결과:

```text
(no output)
```

서비스 포트 비활성화 확인.

## 3. Root Cause Analysis (원인 분석)

### 원인

`agent-app-leak` 프로세스 내부에서 할당된 메모리가 정상적으로 해제되지 않아 Memory Leak이 발생하였다.

Memory Leak으로 인해 프로세스의 RSS 메모리 사용량이 지속적으로 증가하였으며, 설정된 메모리 제한을 초과하면서 OOM 상태가 발생하였다.

### Linux OOM 동작 원리

Linux 커널은 시스템의 가용 메모리가 부족해질 경우 OOM(Out Of Memory) 상태를 감지한다.

OOM 상태 발생 시 커널은 다음 과정을 수행한다.

1. 메모리 부족 상태 감지
2. OOM Score 계산
3. 종료 대상 프로세스 선정
4. 프로세스 강제 종료

Memory Leak으로 인해 가장 많은 메모리를 사용하는 `agent-app-leak` 프로세스가 종료 대상이 되었다.

### 영향도

* 서비스 중단
* 프로세스 강제 종료
* 포트 15034 비활성화
* 신규 요청 처리 불가

---

## 4. Workaround & Verification (조치 및 검증)

### 조치 내용

메모리 제한 값을 증가시켜 OOM 발생 시점을 지연시켰다.

#### Before

```bash
export MEMORY_LIMIT=256
```

#### After

```bash
export MEMORY_LIMIT=512
```

### Before & After 비교

| 항목           | Before | After  |
| ------------ | ------ | ------ |
| MEMORY_LIMIT | 256MB  | 512MB |
| 서비스 유지 시간    | 짧음     | 증가     |
| OOM 발생       | 발생     | 미발생    |
| 프로세스 종료      | 발생     | 미발생    |
| 포트 15034 상태  | 비활성화   | 정상 유지  |

### 검증 결과

설정 변경 후 동일한 환경에서 테스트를 수행하였다.

프로세스가 정상적으로 유지되었으며 서비스 포트도 지속적으로 Listen 상태를 유지하였다.

```bash
pgrep -f agent-app-leak
```

결과:

```text
7579
7580
```

프로세스 정상 동작 확인.

```bash
ss -tulnp | grep 15034
```

결과:

```text
tcp   LISTEN 0      1                   0.0.0.0:15034      0.0.0.0:*    users:(("agent-app-leak",pid=7580,fd=6))
```

포트 정상 상태 확인.
