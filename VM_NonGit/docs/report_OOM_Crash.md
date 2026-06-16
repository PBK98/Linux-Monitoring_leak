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
