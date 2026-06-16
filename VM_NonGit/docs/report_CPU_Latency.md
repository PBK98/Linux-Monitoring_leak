# [Bug] CPU Latency - CPU 부하 재현 실패 및 환경변수 미반영 의심

## 1. Description (현상 설명)

### 장애 현상

`agent-app-leak`에서 CPU Latency 장애를 재현하기 위해 CPU 관련 환경변수를 조정하였다.

그러나 실제 모니터링 결과 `PRO_CPU`와 `SYSCPU`가 매우 낮게 유지되어, 현재 수집된 로그만으로는 CPU 포화로 인한 Latency가 발생했다고 단정하기 어렵다.

프로세스는 종료되지 않고 포트 15034도 Listen 상태를 유지했으며, CPU 사용률 또한 1% 미만으로 관찰되었다.

### 발생 조건

CPU Latency 장애가 실제로 발생하려면 일반적으로 다음 조건이 확인되어야 한다.

* `agent-app-leak` 실행
* `CPU_MAX_OCCUPY` 값을 높게 설정
* CPU 부하를 유발하는 요청 또는 내부 작업 실행
* 프로세스 CPU 사용률 또는 시스템 CPU 사용률이 임계치에 근접
* Run Queue 또는 Load Average 증가
* 요청 처리 지연 또는 타임아웃 발생

하지만 현재 재현 로그에서는 CPU 사용률 상승이 확인되지 않았다.

따라서 `agent-app-leak` 내부에 CPU 부하 조건이 하드코딩되어 있거나, `CPU_MAX_OCCUPY` 환경변수가 실제 동작에 반영되지 않았을 가능성이 있다.

### 재현 환경

```bash
export MEMORY_LIMIT=512
export CPU_MAX_OCCUPY=90
export MULTI_THREAD_ENABLE=False
export CPU_THRESHOLD=80
export SYS_CPU_THRESHOLD=80
```

주의: 위 환경변수를 설정해도 실행 파일이 해당 값을 실제로 읽지 않거나 내부 하드코딩 값을 우선 사용한다면 CPU 부하는 증가하지 않을 수 있다.

---

## 2. Evidence & Logs (증거 자료)

### 실행 로그
```bash
   ... Log directory is writable: /var/log/agent-app-leak
[6/6] Verifying Mission Environment       [OK]
   ... MEMORY_LIMIT=512MB, CPU_MAX_OCCUPY=80%, MULTI_THREAD_ENABLE=True
------------------------------------------------------------
All Boot Checks Passed!
Agent READY
2026-06-16 19:14:59,295 [INFO] [SafetyGuard] Process priority lowered (nice=10).
2026-06-16 19:14:59,295 [INFO] Agent listening at port 15034

==================================================
 [ Agent Initiate ] Resource Check
==================================================
 [ MEMORY ] Limit: 512MB 		[ OK ]
 [ CPU    ] Limit: 80%  		[ WARNING: Recommend Under 50% ]
 [ THREAD ] Concurrency: True 		[ WARNING ]
--------------------------------------------------
 >>> SYSTEM WARNING: POTENTIAL DEADLOCK IN CONCURRENT MODE.
==================================================

2026-06-16 19:15:01,310 [INFO] [CpuWorker] Started. Maximum CPU Limit: 80%
2026-06-16 19:15:01,311 [INFO] [CpuWorker] Current Load: 5.00%
2026-06-16 19:15:04,441 [INFO] [CpuWorker] Current Load: 12.57%
2026-06-16 19:15:07,573 [INFO] [CpuWorker] Current Load: 20.93%
2026-06-16 19:15:10,703 [INFO] [CpuWorker] Current Load: 30.45%
2026-06-16 19:15:13,828 [INFO] [CpuWorker] Current Load: 32.55%
2026-06-16 19:15:16,960 [INFO] [CpuWorker] Current Load: 40.98%
2026-06-16 19:15:20,083 [INFO] [CpuWorker] Current Load: 47.15%
2026-06-16 19:15:23,212 [INFO] [CpuWorker] Current Load: 55.53%
2026-06-16 19:15:23,318 [CRITICAL] [CpuWorker] CPU Threshold Violated! (55.53%).

>>> [SYSTEM] WATCHDOG: INITIATING EMERGENCY ABORT (SIGTERM) <<<

Terminated
```
### monitor.sh 로그

`monitor.sh`는 프로세스 CPU 사용률, 시스템 CPU 사용률, 메모리 사용량, 디스크 사용량을 주기적으로 수집한다.

CPU Latency 장애 상황에서는 메모리 사용량보다 CPU 관련 지표가 먼저 상승해야 한다.

하지만 실제 수집된 로그에서는 CPU 부하 상승이 확인되지 않았다.

```bash
[2026-06-16 17:34:23] PID:4566 PRO_CPU:0.6% PRO_MEM:0.143% PRO_MEM_RSS:17536KB SYSCPU:0.10% SYS_MEM:5.11% SYS_MEM_USED:629392KB SYS_MEM_TOTAL:12305676KB DISK_USED:2%
[2026-06-16 17:34:41] PID:4566 PRO_CPU:0.8% PRO_MEM:0.143% PRO_MEM_RSS:17536KB SYSCPU:0.10% SYS_MEM:4.89% SYS_MEM_USED:601332KB SYS_MEM_TOTAL:12305676KB DISK_USED:2%
[2026-06-16 17:34:44] PID:4566 PRO_CPU:0.9% PRO_MEM:0.143% PRO_MEM_RSS:17536KB SYSCPU:0.10% SYS_MEM:4.92% SYS_MEM_USED:605016KB SYS_MEM_TOTAL:12305676KB DISK_USED:2%
```

확인 포인트:

* `PRO_CPU`가 0.6%에서 0.9% 수준으로 낮게 유지되었다.
* `SYSCPU`도 0.10% 수준으로 CPU 포화 상태가 아니다.
* `PRO_MEM_RSS`는 17536KB로 고정되어 Memory Leak 또는 OOM 장애 양상도 아니다.
* 현재 로그만으로는 CPU Scheduling Latency를 입증할 수 없다.

### monitor.sh 경고 출력

현재 수집 구간에서는 CPU 임계치 초과 경고가 확인되지 않았다.

CPU Latency 장애가 재현되었다면 다음과 같은 경고가 발생해야 한다.

```bash
[WARNING] ProcessCPU threshold exceeded (90.0% > 80%)
[WARNING] SystemCPU threshold exceeded (80.0% > 80%)
```

### 프로세스 상태 확인

```bash
ps -p 4566 -o pid,stat,pcpu,pmem,rss,comm
```

예상 결과:

```bash
    PID STAT %CPU %MEM   RSS COMMAND
   4793 SN+   0.6  0.1 17384 agent-app-leak
```

프로세스는 살아 있지만 CPU 사용률은 낮게 유지된다.

### Run Queue / Load Average 확인

CPU Latency를 입증하려면 CPU 사용률뿐 아니라 Load Average와 Run Queue도 함께 확인해야 한다.

```bash
uptime
```

CPU Latency가 발생하지 않은 경우 예시:

```bash
17:34:44 up 1:03, 1 user, load average: 0.02, 0.03, 0.00
```

```bash
vmstat 1 5
```

CPU Latency가 발생하지 않은 경우 예시:

```bash
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 0  0      0 9301240  42412 1932212    0    0     0     2  211  392  0  0 100  0  0
 0  0      0 9301028  42412 1932212    0    0     0     0  246  411  1  0  99  0  0
```

`vmstat`의 `r` 값은 실행 가능 상태이지만 CPU를 기다리는 프로세스/스레드 수를 의미한다. CPU 코어 수보다 `r` 값이 지속적으로 높으면 CPU 대기열이 길어지고 CPU Scheduling Latency가 증가한다.

현재처럼 `PRO_CPU`, `SYSCPU`, Load Average, Run Queue가 모두 낮다면 CPU Latency 장애로 판단하기 어렵다.

---

## 3. Root Cause Analysis (원인 분석)

### 현재 판단

현재 수집된 로그에서는 `agent-app-leak`가 CPU를 과도하게 점유하지 않았다.

따라서 이번 단계의 원인은 "CPU Latency 발생"이 아니라 "CPU Latency 재현 조건이 애플리케이션 동작에 반영되지 않음"으로 보는 것이 더 정확하다.

가능성이 높은 원인은 다음과 같다.

* `agent-app-leak` 내부에 CPU 부하 값 또는 장애 조건이 하드코딩되어 있음
* `CPU_MAX_OCCUPY` 환경변수를 실행 파일이 읽지 않음
* 환경변수는 프로세스에 전달되었지만 실제 CPU 부하 로직에 연결되지 않음
* 앱 실행만으로는 CPU 부하가 발생하지 않고 특정 요청 또는 조건이 필요함
* 분석 대상 바이너리와 실제 실행 중인 바이너리가 다름

### CPU Latency란?

CPU Latency는 작업이 CPU에서 실제로 실행되기까지 기다리는 시간 또는 작업이 완료되기까지 걸리는 지연 시간을 의미한다.

CPU 사용률은 "CPU가 얼마나 바쁜가"를 보여주고, CPU Latency는 "작업이 얼마나 오래 기다리는가"를 보여준다.

CPU 사용률이 높으면 다음 흐름이 발생할 수 있다.

```text
요청 수신 -> run queue 대기 -> CPU 할당 -> 작업 처리 -> 응답 반환
```

run queue 대기 시간이 길어질수록 사용자는 서비스가 느려졌다고 느끼게 된다.

### CPU 사용률과 CPU Latency의 차이

| 항목 | 의미 | 장애 판단 포인트 |
| --- | --- | --- |
| CPU 사용률 | CPU가 사용 중인 시간의 비율 | CPU 자원이 포화 상태인지 확인 |
| CPU Latency | 작업이 CPU를 얻기까지 기다리는 시간 | 요청 처리 지연 원인 확인 |
| Load Average | 실행 중이거나 CPU/I/O를 기다리는 작업 수 | CPU 코어 수와 비교 |
| Run Queue | CPU 실행을 기다리는 작업 수 | 코어 수보다 지속적으로 큰지 확인 |

CPU 사용률이 높고 run queue가 길면 CPU 포화로 인한 Latency 가능성이 높다.

반대로 CPU 사용률이 낮은데 Latency가 높다면 I/O 대기, 락 경합, 인터럽트 처리, 컨텍스트 스위칭, 캐시 미스 등을 추가로 의심해야 한다.

이번 로그처럼 CPU 사용률과 run queue가 모두 낮다면 CPU Latency 장애로 판단하기 어렵다.

### 환경변수와 하드코딩 가능성

Linux에서 `export`로 설정한 환경변수는 프로세스 실행 시점에 전달된다.

하지만 환경변수가 전달되었다고 해서 애플리케이션이 반드시 그 값을 사용하는 것은 아니다. 실행 파일 내부 코드가 환경변수를 읽지 않거나, 내부에 고정된 값을 사용하도록 하드코딩되어 있다면 외부 설정 변경은 동작에 영향을 주지 않는다.

환경변수 전달 여부는 다음 명령으로 확인할 수 있다.

```bash
tr '\0' '\n' < /proc/4566/environ | grep -E 'CPU|THREAD|MEMORY|PORT'
```

확인 결과 `CPU_MAX_OCCUPY=90`이 보인다면 환경변수는 프로세스에 전달된 것이다. 그러나 CPU 사용률이 계속 낮다면 애플리케이션 내부에서 해당 값을 사용하지 않거나, 별도 트리거 조건이 있는 것으로 판단해야 한다.

### 관련 OS 동작 원리

Linux 커널은 CFS(Completely Fair Scheduler)를 통해 실행 가능한 프로세스와 스레드에 CPU 시간을 분배한다.

실행 가능한 작업이 CPU 코어 수보다 많아지면 모든 작업이 즉시 실행될 수 없으므로 run queue에서 대기한다. 이 대기 시간이 CPU Scheduling Latency이다.

CPU-bound 작업이 실제로 많아질 경우 다음 문제가 발생한다.

* 요청 처리 스레드가 CPU를 늦게 할당받음
* 컨텍스트 스위칭 증가
* Load Average 상승
* 응답 시간 증가
* 모니터링에서 CPU threshold 경고 발생

### 영향도

CPU Latency가 실제로 발생하면 다음 영향이 발생할 수 있다.

* 서비스 응답 지연
* 타임아웃 증가 가능성
* 사용자 요청 처리량 감소
* CPU 임계치 경고 발생
* 장애가 지속되면 다른 프로세스에도 영향 가능

현재 수집 로그에서는 위 영향도를 입증할 만큼의 CPU 지표 상승이 확인되지 않았다.

---

## 4. Workaround & Verification (조치 및 검증)

### 조치 내용

현재는 CPU 부하가 증가하지 않았으므로, 조치의 우선순위는 CPU 사용량 제한이 아니라 CPU 부하 재현 조건 확인이다.

먼저 `agent-app-leak`가 환경변수를 실제로 전달받았는지 확인한다.

```bash
tr '\0' '\n' < /proc/4566/environ | grep -E 'CPU|THREAD|MEMORY|PORT'
```

이후 CPU 부하가 실제로 발생하는 요청 또는 실행 조건을 확인한다.

CPU 부하가 정상적으로 재현되는 경우에는 `CPU_MAX_OCCUPY` 값을 낮추고, 필요 시 멀티스레드 동작을 제한한다.

#### Before

```bash
export CPU_MAX_OCCUPY=90
export MULTI_THREAD_ENABLE=True
```

#### After

```bash
export CPU_MAX_OCCUPY=50
export MULTI_THREAD_ENABLE=False
```

### Before & After 비교

| 항목 | Before | After |
| --- | --- | --- |
| CPU_MAX_OCCUPY | 90 | 50 |
| MULTI_THREAD_ENABLE | True | False |
| Process CPU | 0.6% ~ 0.9% | CPU 부하 재현 후 재측정 필요 |
| System CPU | 0.10% | CPU 부하 재현 후 재측정 필요 |
| Run Queue | 낮음 | CPU 부하 재현 후 재측정 필요 |
| 응답 상태 | CPU Latency 증거 부족 | 응답 시간 지표 추가 필요 |
| 판단 | CPU Latency 입증 불가 | 하드코딩/트리거 조건 확인 필요 |

### 검증 방법

환경변수 반영 여부와 CPU 부하 트리거 조건을 확인한 뒤 동일한 요청 부하를 주고 모니터링을 다시 수행한다.

```bash
ps -p "$(pgrep -f agent-app-leak | head -n 1)" -o pid,stat,pcpu,pmem,rss,comm
uptime
vmstat 1 5
ss -tulnp | grep 15034
tr '\0' '\n' < /proc/4566/environ | grep -E 'CPU|THREAD|MEMORY|PORT'
curl -w 'time_total=%{time_total}\n' -o /dev/null -s http://127.0.0.1:15034/
```

확인 기준:

* CPU Latency 재현 시 `PRO_CPU` 또는 `SYSCPU`가 임계치에 근접하거나 초과한다.
* `vmstat`의 `r` 값이 CPU 코어 수보다 지속적으로 높아진다.
* `curl`의 `time_total` 값이 증가한다.
* 포트 15034가 계속 Listen 상태를 유지한다.
* 환경변수를 조정한 후 CPU 사용률과 응답 시간이 변화한다.

### 근본 해결 제안

* `agent-app-leak`가 `CPU_MAX_OCCUPY`와 `MULTI_THREAD_ENABLE`을 실제로 읽는지 확인
* 바이너리 내부에 CPU 부하 값이 하드코딩되어 있는지 확인
* CPU 부하를 유발하는 API 또는 실행 조건 확인
* 모니터링에 Load Average, run queue, 응답 시간 지표 추가
* CPU를 많이 사용하는 루프에 sleep, rate limit, backoff 적용
* 요청 처리 스레드 수를 CPU 코어 수에 맞게 제한
* CPU-bound 작업과 I/O-bound 작업 분리
