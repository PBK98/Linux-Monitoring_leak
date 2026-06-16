# [Bug] DeadLock - 스레드 간 자원 대기로 인한 요청 처리 중단

## 1. Description (현상 설명)

### 장애 현상

`agent-app-leak` 실행 중 특정 조건에서 프로세스는 종료되지 않았지만 서비스 요청 처리가 멈추는 현상이 발생하였다.

포트 15034는 Listen 상태로 남아 있고 `pgrep`으로도 프로세스가 확인되지만, 내부 작업 스레드가 서로의 자원을 기다리면서 요청 처리가 진행되지 않는다.

### 발생 조건

* `agent-app-leak` 실행
* `MULTI_THREAD_ENABLE=True` 설정
* 여러 스레드가 동시에 공유 자원에 접근
* 한 스레드는 A 자원을 점유한 상태에서 B 자원을 대기
* 다른 스레드는 B 자원을 점유한 상태에서 A 자원을 대기
* 두 스레드 모두 락을 해제하지 못해 요청 처리 중단

### 재현 환경

```bash
export MULTI_THREAD_ENABLE=True
export CPU_MAX_OCCUPY=50
```

---

## 2. Evidence & Logs (증거 자료)

### monitor.sh 로그

DeadLock 장애에서는 프로세스가 종료되지 않기 때문에 `monitor.sh`의 Health Check는 정상으로 보일 수 있다.

```bash
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent-app-leak'... [OK] (PID: 8436)
Checking port 15034... [OK]
```

하지만 요청 처리는 멈춰 있고, CPU와 메모리 지표는 OOM 또는 CPU 포화 장애처럼 급격히 증가하지 않을 수 있다.

```bash
[2026-06-02 20:03:11] PID:8436 PRO_CPU:0.3% PRO_MEM:0.702% PRO_MEM_RSS:86288KB SYSCPU:0.41% SYS_MEM:7.18% SYS_MEM_USED:882324KB SYS_MEM_TOTAL:12293676KB DISK_USED:2%
[2026-06-02 20:03:14] PID:8436 PRO_CPU:0.2% PRO_MEM:0.702% PRO_MEM_RSS:86300KB SYSCPU:0.36% SYS_MEM:7.18% SYS_MEM_USED:882420KB SYS_MEM_TOTAL:12293676KB DISK_USED:2%
[2026-06-02 20:03:17] PID:8436 PRO_CPU:0.2% PRO_MEM:0.702% PRO_MEM_RSS:86300KB SYSCPU:0.31% SYS_MEM:7.19% SYS_MEM_USED:883108KB SYS_MEM_TOTAL:12293676KB DISK_USED:2%
```

확인 포인트:

* 프로세스는 살아 있다.
* 포트도 열려 있다.
* CPU 사용률이 높지 않다.
* RSS 메모리도 급격히 증가하지 않는다.
* 그런데 요청 응답이 없거나 타임아웃이 발생한다.

### 프로세스 상태 확인

```bash
pgrep -f agent-app-leak
```

결과:

```text
8436
```

```bash
ss -tulnp | grep 15034
```

결과:

```bash
tcp   LISTEN 0      1                   0.0.0.0:15034      0.0.0.0:*    users:(("agent-app-leak",pid=8436,fd=6))
```

프로세스와 포트는 정상으로 보이지만 서비스 응답은 멈춰 있다.

### 스레드 상태 확인

```bash
ps -eLf | grep agent-app-leak
```

예상 결과:

```bash
agent-admin 8436 8436  0  5 20:03 ? 00:00:00 ./agent-app-leak
agent-admin 8436 8441  0  5 20:03 ? 00:00:00 ./agent-app-leak
agent-admin 8436 8442  0  5 20:03 ? 00:00:00 ./agent-app-leak
```

스레드는 존재하지만 요청 처리 로그가 더 이상 증가하지 않는다면 내부 락 대기 가능성이 높다.

### 추가 분석 명령

```bash
top -H -p 8436
```

스레드별 CPU 사용률을 확인한다. DeadLock 상황에서는 스레드가 바쁘게 CPU를 사용하는 것이 아니라 대기 상태에 머무를 수 있다.

```bash
strace -f -p 8436
```

`futex` 대기가 반복적으로 보이면 사용자 공간 락 또는 mutex 대기를 의심할 수 있다.

```text
futex(0x..., FUTEX_WAIT_PRIVATE, ...)
```

`futex`는 pthread mutex, Python Lock 등 사용자 공간 동기화 객체가 커널에 대기를 요청할 때 자주 관찰된다.

---

## 3. Root Cause Analysis (원인 분석)

### 원인

멀티스레드 환경에서 공유 자원 접근 순서가 일관되지 않아 스레드 간 순환 대기가 발생하였다.

예시는 다음과 같다.

```text
Thread-1: Lock A 획득 -> Lock B 대기
Thread-2: Lock B 획득 -> Lock A 대기
```

두 스레드 모두 이미 점유한 락을 해제하지 않은 상태에서 상대방이 가진 락을 기다리기 때문에 작업이 더 이상 진행되지 않는다.

### DeadLock이란?

DeadLock은 둘 이상의 프로세스 또는 스레드가 서로 가진 자원을 기다리며 무한정 대기하는 상태이다.

서비스 관점에서는 프로세스가 죽지 않았는데도 요청이 처리되지 않는 "무응답 장애"로 나타난다.

### DeadLock 발생 4가지 필요 조건

| 조건 | 의미 | 이번 장애와의 관계 |
| --- | --- | --- |
| Mutual Exclusion | 하나의 자원을 한 번에 하나의 스레드만 사용 | Lock A, Lock B가 독점적으로 사용됨 |
| Hold and Wait | 자원을 점유한 상태에서 다른 자원을 기다림 | Lock A를 잡고 Lock B를 기다림 |
| No Preemption | 다른 스레드의 자원을 강제로 빼앗을 수 없음 | 락은 보유 스레드가 풀어야 함 |
| Circular Wait | 서로가 가진 자원을 순환적으로 기다림 | Thread-1과 Thread-2가 서로의 락을 기다림 |

위 네 조건이 동시에 만족되면 DeadLock이 발생할 수 있다.

### 관련 OS 동작 원리

Linux에서 스레드는 커널 스케줄링 단위로 관리된다.

스레드가 mutex 같은 동기화 객체를 얻지 못하면 실행을 계속하지 못하고 대기 상태에 들어간다. 사용자 공간 락은 내부적으로 `futex` 시스템콜을 사용할 수 있으며, 이때 스레드는 CPU를 거의 사용하지 않으면서 특정 조건이 깨워지기를 기다린다.

이 때문에 DeadLock은 CPU 포화 장애와 다르게 보인다.

* CPU 사용률이 낮을 수 있다.
* 메모리 사용량도 안정적으로 보일 수 있다.
* 프로세스와 포트 Health Check는 정상으로 보일 수 있다.
* 실제 요청 처리만 멈춘다.

따라서 단순히 `프로세스 존재 여부`와 `포트 Listen 여부`만 확인하는 Health Check로는 DeadLock을 정확히 탐지하기 어렵다.

### 영향도

* 요청 처리 중단
* 클라이언트 타임아웃 발생
* Health Check 오탐 가능성
* 프로세스 재시작 전까지 장애 지속
* 장애 원인 파악이 CPU/OOM 장애보다 어려움

---

## 4. Workaround & Verification (조치 및 검증)

### 조치 내용

즉시 조치로는 프로세스를 재시작하여 점유된 락 상태를 초기화한다.

```bash
pkill -f agent-app-leak
cd "$AGENT_HOME/app"
nohup ./agent-app-leak >> "$AGENT_LOG_DIR/agent_app.log" 2>&1 < /dev/null &
```

재발 가능성을 낮추기 위해 멀티스레드 동작을 비활성화하거나 공유 자원 접근 경합을 줄인다.

#### Before

```bash
export MULTI_THREAD_ENABLE=True
```

#### After

```bash
export MULTI_THREAD_ENABLE=False
```

### Before & After 비교

| 항목 | Before | After |
| --- | --- | --- |
| MULTI_THREAD_ENABLE | True | False |
| 프로세스 상태 | 살아 있음 | 살아 있음 |
| 포트 15034 상태 | Listen | Listen |
| 요청 처리 | 멈춤 또는 타임아웃 | 정상 응답 |
| CPU 사용률 | 낮거나 변화 적음 | 안정적 |
| 장애 재현 가능성 | 높음 | 낮음 |

### 검증 방법

재시작 및 설정 변경 후 다음을 확인한다.

```bash
pgrep -f agent-app-leak
ss -tulnp | grep 15034
ps -eLf | grep agent-app-leak
```

애플리케이션 요청이 정상 응답하는지 확인한다.

```bash
curl -m 3 http://127.0.0.1:15034/
```

확인 기준:

* 프로세스가 정상 실행된다.
* 포트 15034가 Listen 상태를 유지한다.
* 요청이 타임아웃 없이 응답한다.
* `monitor.sh` 로그가 계속 기록된다.
* 동일 부하에서 요청 처리 멈춤 현상이 재현되지 않는다.

### 근본 해결 제안

* 모든 코드 경로에서 락 획득 순서를 동일하게 유지
* 하나의 작업에서 여러 락을 동시에 잡는 구간 최소화
* 락 획득에 timeout 적용
* `try-lock` 실패 시 보유 중인 락을 해제하고 재시도
* 공유 자원을 단일 작업 큐 또는 actor 모델로 직렬화
* 요청 처리 Health Check를 추가해 단순 포트 체크가 아닌 실제 응답 여부 확인
* 운영 모니터링에 요청 성공률, 응답 시간, 타임아웃 수 추가
