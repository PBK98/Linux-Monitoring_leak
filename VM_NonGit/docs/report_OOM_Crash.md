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

### monitor.sh 로그

```text
[2026-06-02 14:10:03] PID:4770 PRO_CPU:2.13% PRO_MEM:15.22% PRO_MEM_RSS:1872540KB SYSCPU:3.22% SYS_MEM:21.43%

[2026-06-02 14:15:03] PID:4770 PRO_CPU:2.15% PRO_MEM:28.45% PRO_MEM_RSS:3498712KB SYSCPU:3.35% SYS_MEM:34.67%

[2026-06-02 14:20:03] PID:4770 PRO_CPU:2.19% PRO_MEM:42.88% PRO_MEM_RSS:5278300KB SYSCPU:3.41% SYS_MEM:48.92%
```

프로세스 RSS(Resident Set Size)가 지속적으로 증가하는 것을 확인하였다.

### 프로세스 상태 확인

```bash
ps -p 4770 -o pid,%mem,rss
```

결과:

```text
PID   %MEM      RSS
4770  42.88  5278300
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

### 시스템 로그 확인

```bash
dmesg | grep -i oom
```

또는

```bash
journalctl -k | grep -i oom
```

OOM Killer 동작 로그 확인 가능.

---

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
export MEMORY_LIMIT=2048
```

### Before & After 비교

| 항목           | Before | After  |
| ------------ | ------ | ------ |
| MEMORY_LIMIT | 256MB  | 2048MB |
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
5231
```

프로세스 정상 동작 확인.

```bash
ss -tulnp | grep 15034
```

결과:

```text
LISTEN 0 128 0.0.0.0:15034
```

포트 정상 상태 확인.

### 추가 개선 방안

* Memory Leak 원인 코드 수정
* 메모리 사용량 임계치 경고 기능 추가
* OOM Killer 로그 자동 수집 기능 구현
* 일정 임계치 초과 시 프로세스 자동 재시작 기능 추가
* 모니터링 시스템을 통한 사전 알림 기능 적용
