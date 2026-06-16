# [Bug] CPU Latency - CPU 점유율 상승으로 인한 요청 처리 지연

## 1. Description (현상 설명)

### 장애 현상

`agent-app-leak` 실행 후 CPU 부하가 증가하면서 서비스 요청의 응답 시간이 길어지는 현상이 발생하였다.

프로세스는 종료되지 않고 포트 15034도 Listen 상태를 유지하지만, CPU를 얻기 위해 대기하는 시간이 길어져 요청 처리 속도가 눈에 띄게 느려졌다.

### 발생 조건

* `agent-app-leak` 실행
* `CPU_MAX_OCCUPY` 값을 높게 설정
* `MULTI_THREAD_ENABLE=True` 상태에서 여러 스레드가 동시에 CPU 사용
* 프로세스 CPU 사용률 또는 시스템 CPU 사용률이 임계치에 근접
* 요청 처리 지연 및 모니터링 경고 발생

### 재현 환경

```bash
export CPU_MAX_OCCUPY=90
export MULTI_THREAD_ENABLE=True
export CPU_THRESHOLD=80
export SYS_CPU_THRESHOLD=80
```

---

## 2. Evidence & Logs (증거 자료)

### monitor.sh 로그

`monitor.sh`는 프로세스 CPU 사용률, 시스템 CPU 사용률, 메모리 사용량, 디스크 사용량을 주기적으로 수집한다.

CPU Latency 장애 상황에서는 메모리 사용량보다 CPU 관련 지표가 먼저 상승한다.

```bash
[2026-06-02 19:10:12] PID:8121 PRO_CPU:72.4% PRO_MEM:0.684% PRO_MEM_RSS:84120KB SYSCPU:61.38% SYS_MEM:7.21% SYS_MEM_USED:886512KB SYS_MEM_TOTAL:12293676KB DISK_USED:2%
[2026-06-02 19:10:15] PID:8121 PRO_CPU:86.9% PRO_MEM:0.687% PRO_MEM_RSS:84488KB SYSCPU:78.42% SYS_MEM:7.22% SYS_MEM_USED:887704KB SYS_MEM_TOTAL:12293676KB DISK_USED:2%
[2026-06-02 19:10:18] PID:8121 PRO_CPU:94.1% PRO_MEM:0.690% PRO_MEM_RSS:84860KB SYSCPU:84.77% SYS_MEM:7.25% SYS_MEM_USED:891216KB SYS_MEM_TOTAL:12293676KB DISK_USED:2%
[2026-06-02 19:10:21] PID:8121 PRO_CPU:96.3% PRO_MEM:0.691% PRO_MEM_RSS:84944KB SYSCPU:88.06% SYS_MEM:7.24% SYS_MEM_USED:890436KB SYS_MEM_TOTAL:12293676KB DISK_USED:2%
```

확인 포인트:

* `PRO_CPU`가 `CPU_THRESHOLD=80`을 초과하였다.
* `SYSCPU`도 `SYS_CPU_THRESHOLD=80`에 근접하거나 초과하였다.
* `PRO_MEM_RSS`는 급격히 증가하지 않아 Memory Leak 또는 OOM 장애와는 양상이 다르다.

### monitor.sh 경고 출력

```bash
[WARNING] ProcessCPU threshold exceeded (94.1% > 80%)
[WARNING] SystemCPU threshold exceeded (84.77% > 80%)
```

### 프로세스 상태 확인

```bash
ps -p 8121 -o pid,stat,pcpu,pmem,rss,comm
```

결과:

```bash
    PID STAT %CPU %MEM   RSS COMMAND
   8121 Sl   96.3  0.6 84944 agent-app-leak
```

프로세스는 살아 있지만 CPU 사용률이 높게 유지된다.

### Run Queue / Load Average 확인

```bash
uptime
```

결과:

```bash
19:10:22 up 2:14, 1 user, load average: 3.82, 3.41, 2.76
```

```bash
vmstat 1 5
```

결과:

```bash
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 4  0      0 9301240  42412 1932212    0    0     0     2  811 1592 82  7 11  0  0
 5  0      0 9301028  42412 1932212    0    0     0     0  846 1711 86  6  8  0  0
```

`r` 값은 실행 가능 상태이지만 CPU를 기다리는 프로세스/스레드 수를 의미한다. CPU 코어 수보다 `r` 값이 지속적으로 높으면 CPU 대기열이 길어지고 CPU Scheduling Latency가 증가한다.

---

## 3. Root Cause Analysis (원인 분석)

### 원인

`agent-app-leak`가 CPU를 과도하게 점유하면서 CPU를 사용하려는 스레드들이 run queue에서 대기하였다.

이로 인해 프로세스가 죽지는 않았지만 요청이 즉시 실행되지 못하고 CPU 스케줄러의 선택을 기다리게 되었으며, 결과적으로 응답 시간이 증가하였다.

### CPU Latency란?

CPU Latency는 작업이 CPU에서 실제로 실행되기까지 기다리는 시간 또는 작업이 완료되기까지 걸리는 지연 시간을 의미한다.

CPU 사용률은 "CPU가 얼마나 바쁜가"를 보여주고, CPU Latency는 "작업이 얼마나 오래 기다리는가"를 보여준다.

예를 들어 CPU 사용률이 높으면 다음 흐름이 발생한다.

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

### 관련 OS 동작 원리

Linux 커널은 CFS(Completely Fair Scheduler)를 통해 실행 가능한 프로세스와 스레드에 CPU 시간을 분배한다.

실행 가능한 작업이 CPU 코어 수보다 많아지면 모든 작업이 즉시 실행될 수 없으므로 run queue에서 대기한다. 이 대기 시간이 CPU Scheduling Latency이다.

CPU-bound 작업이 많아질수록 다음 문제가 발생한다.

* 요청 처리 스레드가 CPU를 늦게 할당받음
* 컨텍스트 스위칭 증가
* Load Average 상승
* 응답 시간 증가
* 모니터링에서 CPU threshold 경고 발생

### 영향도

* 서비스 응답 지연
* 타임아웃 증가 가능성
* 사용자 요청 처리량 감소
* CPU 임계치 경고 발생
* 장애가 지속되면 다른 프로세스에도 영향 가능

---

## 4. Workaround & Verification (조치 및 검증)

### 조치 내용

CPU 부하를 낮추기 위해 `CPU_MAX_OCCUPY` 값을 낮추고, 필요 시 멀티스레드 동작을 제한하였다.

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
| Process CPU | 90% 이상 | 50% 전후 |
| System CPU | 80% 이상 | 임계치 이하 |
| Run Queue | 코어 수보다 높음 | 안정화 |
| 응답 상태 | 지연 발생 | 정상 처리 |

### 검증 방법

설정 변경 후 동일한 요청 부하를 주고 모니터링을 다시 수행한다.

```bash
ps -p "$(pgrep -f agent-app-leak | head -n 1)" -o pid,stat,pcpu,pmem,rss,comm
uptime
vmstat 1 5
ss -tulnp | grep 15034
```

확인 기준:

* `PRO_CPU`가 `CPU_THRESHOLD` 이하로 유지된다.
* `SYSCPU`가 `SYS_CPU_THRESHOLD` 이하로 유지된다.
* `vmstat`의 `r` 값이 CPU 코어 수 이하 또는 일시적 상승 수준으로 안정화된다.
* 포트 15034가 계속 Listen 상태를 유지한다.
* 요청 응답 시간이 정상 범위로 회복된다.

### 근본 해결 제안

* CPU를 많이 사용하는 루프에 sleep, rate limit, backoff 적용
* 요청 처리 스레드 수를 CPU 코어 수에 맞게 제한
* CPU-bound 작업과 I/O-bound 작업 분리
* 비동기 처리 또는 작업 큐 도입
* `top`, `pidstat`, `perf`, `strace` 등을 이용해 CPU hot path 분석
* 모니터링에 Load Average, run queue, 응답 시간 지표 추가
