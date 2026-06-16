# 평가 항목 대비 정리 문서

이 문서는 평가 항목에 맞춰 `OOM`, `CPU`, `Deadlock` 장애 리포트에서 반드시 설명해야 할 증거, 판단 기준, 도메인 지식을 정리한 문서이다.

관련 리포트:

* `report_OOM_Crash.md`
* `report_CPU_Latency.md`
* `report_DeadLock.md`

---

## 1. 리포트 제출 체크리스트

### OOM

확인해야 할 증거:

* `monitor.sh` 로그에서 `PRO_MEM_RSS`가 시간 순서대로 선형 증가하는지 확인
* `MEMORY_LIMIT`가 낮을 때 프로세스가 종료되는지 확인
* 프로세스 종료 후 `pgrep -f agent-app-leak` 결과가 없는지 확인
* 프로세스 종료 후 `ss -tulnp | grep 15034` 결과가 없는지 확인
* `MEMORY_LIMIT`를 증가시킨 뒤 프로세스 생존 시간이 늘어났는지 Before & After로 비교

리포트에 들어가야 할 핵심 문장:

```text
프로세스 RSS가 지속적으로 증가했고, 설정된 MEMORY_LIMIT를 초과한 뒤 프로세스가 종료되었다.
MEMORY_LIMIT를 256MB에서 512MB로 증가시킨 후 동일 조건에서 프로세스 생존 시간이 증가하였다.
```

### CPU

확인해야 할 증거:

* `monitor.sh` 로그에서 `PRO_CPU` 또는 `SYSCPU`가 임계치를 초과하는지 확인
* `CPU_MAX_OCCUPY` 조정 전후 프로세스 종료 여부 또는 생존 시간이 달라졌는지 확인
* `uptime`의 Load Average가 CPU 코어 수보다 높은지 확인
* `vmstat 1 5`의 `r` 값이 CPU 코어 수보다 지속적으로 높은지 확인
* 요청 응답 시간이 증가했는지 `curl -w 'time_total=%{time_total}\n'`으로 확인

현재 리포트의 판단:

```text
CPU_MAX_OCCUPY를 조정했지만 PRO_CPU가 0.6~0.9%, SYSCPU가 0.10% 수준으로 낮게 유지되었다.
따라서 현재 로그만으로는 CPU Latency 또는 CPU 과점유 장애를 입증하기 어렵다.
agent-app-leak 내부에 CPU 부하 조건이 하드코딩되어 있거나, CPU_MAX_OCCUPY 환경변수가 실제 동작에 반영되지 않았을 가능성이 있다.
```

### Deadlock

확인해야 할 증거:

* `pgrep -f agent-app-leak`으로 PID가 존재하는지 확인
* `ss -tulnp | grep 15034`로 포트가 열려 있는지 확인
* `monitor.sh` 로그에서 CPU/메모리 변화가 거의 없는지 확인
* 요청 응답이 멈췄거나 타임아웃이 발생하는지 확인
* `ps -eLf | grep agent-app-leak` 또는 `top -H -p <PID>`로 스레드가 존재하지만 대기 상태인지 확인
* `MULTI_THREAD_ENABLE` 조정 전후 데드락 재현 여부를 비교

리포트에 들어가야 할 핵심 문장:

```text
프로세스와 포트는 살아 있었지만 CPU와 메모리 지표 변화가 거의 없고 요청 처리가 멈췄다.
이는 프로세스 크래시가 아니라 스레드 간 자원 대기로 인한 Deadlock 가능성이 높다.
```

### Format / Evidence

3개 리포트는 모두 GitHub Issue 스타일의 흐름을 갖춰야 한다.

필수 구조:

1. Description: 어떤 현상이 발생했는가
2. Evidence & Logs: 어떤 로그와 명령 결과로 확인했는가
3. Root Cause Analysis: 왜 발생했는가
4. Workaround & Verification: 어떻게 조치했고 결과가 어떻게 달라졌는가

필수 증거:

* PID
* 로그 타임스탬프
* 핵심 로그 메시지 또는 monitor 로그
* `ps`, `pgrep`, `ss`, `top`, `vmstat`, `uptime` 등 시스템 명령 결과
* Before & After 비교 표

---

## 2. monitor.sh 지표 수집 방식

### 메모리 증가 패턴 추적

프로세스 RSS 수집:

```bash
MEM_RSS=$(ps -p "$PID" -o rss= | awk '{print $1}')
```

전체 메모리 수집:

```bash
MEM_TOTAL=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
```

프로세스 메모리 사용률 계산:

```bash
PRO_MEM=$(awk "BEGIN {
  if ($MEM_TOTAL > 0)
    printf \"%.3f\", ($MEM_RSS / $MEM_TOTAL) * 100
  else
    printf \"0.000\"
}")
```

의미:

* `rss`: 실제 물리 메모리에 올라와 있는 프로세스 메모리 크기
* `MemTotal`: 시스템 전체 메모리 크기
* `PRO_MEM`: `RSS / 전체 메모리 * 100`

OOM 판단 흐름:

```text
RSS 지속 증가 -> MEMORY_LIMIT 초과 -> 프로세스 종료 -> 포트 비활성화
```

### CPU 사용률 확인

프로세스 CPU 사용률 수집:

```bash
PRO_CPU=$(ps -p "$PID" -o pcpu= | awk '{print $1}')
```

중요한 점:

* Linux `ps`에서는 `cpu`보다 `pcpu` 또는 `%cpu` 컬럼을 사용하는 것이 안전하다.
* `ps -o cpu=`를 사용하면 환경에 따라 `-`가 출력될 수 있다.
* `pcpu`는 해당 프로세스의 CPU 사용률을 보여준다.

시스템 CPU 사용률 계산:

```bash
read -r _ USER1 NICE1 SYSTEM1 IDLE1 IOWAIT1 IRQ1 SOFTIRQ1 STEAL1 _ < /proc/stat
sleep 1
read -r _ USER2 NICE2 SYSTEM2 IDLE2 IOWAIT2 IRQ2 SOFTIRQ2 STEAL2 _ < /proc/stat
```

의미:

* `/proc/stat`의 CPU 누적 시간을 1초 간격으로 두 번 읽는다.
* 전체 시간 증가량에서 idle 증가량을 뺀 값을 CPU 사용 시간으로 본다.
* `(전체 증가량 - idle 증가량) / 전체 증가량 * 100`으로 시스템 CPU 사용률을 계산한다.

CPU 장애 판단 흐름:

```text
PRO_CPU 상승 -> SYSCPU 상승 -> Load Average 증가 -> Run Queue 증가 -> 응답 지연
```

현재 CPU 리포트에서는 이 흐름이 확인되지 않았으므로, CPU 장애를 입증하기보다 환경변수 미반영 또는 하드코딩 가능성을 설명해야 한다.

### 살아 있지만 멈춘 상태 진단

Deadlock은 단순 프로세스 존재 여부만으로 판단하면 놓치기 쉽다.

진단 순서:

```bash
pgrep -f agent-app-leak
ss -tulnp | grep 15034
ps -eLf | grep agent-app-leak
top -H -p <PID>
curl -m 3 http://127.0.0.1:15034/
```

판단 흐름:

```text
PID 존재 -> 포트 Listen -> CPU/메모리 변화 없음 -> 요청 타임아웃 -> 스레드 대기 상태 확인 -> Deadlock 의심
```

핵심은 "프로세스가 살아 있다"와 "서비스가 정상이다"를 구분하는 것이다.

---

## 3. 장애별 도메인 지식

### OOM과 메모리 보호 정책

Memory Leak은 애플리케이션이 사용이 끝난 메모리를 반환하지 않아 RSS가 계속 증가하는 현상이다.

메모리가 부족해지면 Linux 커널은 시스템 보호를 위해 OOM Killer를 동작시킬 수 있다. OOM Killer는 프로세스별 메모리 사용량, oom score 등을 기준으로 종료 대상을 고른다.

프로세스 하나를 종료하는 이유:

* 시스템 전체가 멈추는 것을 방지
* 다른 정상 프로세스를 보호
* 커널과 필수 시스템 서비스가 동작할 메모리 확보

운영 관점에서는 OOM으로 프로세스가 죽은 뒤에야 알면 늦다. RSS 증가율, 메모리 임계치, 재시작 횟수, OOM 로그를 조기에 감지해야 한다.

### CPU 과점유와 시스템 보호

CPU 과점유는 특정 프로세스가 CPU 시간을 과도하게 사용해 다른 작업이 CPU를 얻기 어렵게 만드는 상태이다.

CPU 과점유 프로세스를 제한하거나 종료해야 하는 이유:

* 다른 서비스 요청 처리 지연 방지
* SSH, cron, monitoring 같은 운영 작업 보호
* 전체 시스템 응답성 유지
* 장애 전파 방지

CPU 사용률과 CPU Latency는 다르다.

| 항목 | 의미 |
| --- | --- |
| CPU 사용률 | CPU가 얼마나 바쁜지 |
| CPU Latency | 작업이 CPU를 얻기까지 얼마나 기다리는지 |
| Load Average | 실행 중이거나 대기 중인 작업 수 |
| Run Queue | CPU 실행을 기다리는 작업 수 |

CPU Latency를 입증하려면 `PRO_CPU` 하나만 보면 부족하다. `SYSCPU`, Load Average, `vmstat r`, 요청 응답 시간을 함께 봐야 한다.

### Deadlock 원리

Deadlock은 둘 이상의 스레드 또는 프로세스가 서로 가진 자원을 기다리며 무한정 대기하는 상태이다.

발생 조건 4가지:

| 조건 | 설명 |
| --- | --- |
| Mutual Exclusion | 자원을 한 번에 하나의 스레드만 사용 |
| Hold and Wait | 자원을 가진 상태에서 다른 자원을 기다림 |
| No Preemption | 다른 스레드의 자원을 강제로 빼앗을 수 없음 |
| Circular Wait | 서로가 가진 자원을 순환적으로 기다림 |

순환 대기 예시:

```text
Thread A: Lock A 보유 -> Lock B 대기
Thread B: Lock B 보유 -> Lock A 대기
```

로그에서 순환 의존 관계를 추적하는 방법:

1. 스레드별 로그 타임스탬프를 본다.
2. 각 스레드가 어떤 자원을 먼저 획득했는지 찾는다.
3. 이후 어떤 자원을 기다리다가 로그가 멈췄는지 본다.
4. `A -> B`, `B -> A` 형태의 대기 관계가 있는지 정리한다.

Deadlock은 CPU를 많이 쓰지 않을 수 있다. 그래서 CPU가 낮고 메모리도 안정적인데 서비스가 멈췄다면 Deadlock 또는 I/O wait, 외부 의존성 대기를 의심해야 한다.

---

## 4. 심화 질문 대비

### 운영 서버라면 monitor.sh를 어떻게 개선할 것인가?

OOM 사전 탐지를 위해 다음 지표를 추가한다.

* RSS 증가율
* 최근 N분간 메모리 기울기
* `MEMORY_LIMIT` 대비 사용률
* 프로세스 재시작 횟수
* `/var/log/syslog` 또는 `dmesg`의 OOM Killer 로그
* 요청 성공률과 응답 시간

예시 개선 방향:

```text
단순 현재값만 저장하지 않고, 이전 샘플과 비교해 RSS 증가 속도를 계산한다.
RSS가 일정 시간 동안 계속 증가하고 임계치에 근접하면 OOM 발생 전에 경고한다.
```

### 실제 서비스에서 가장 치명적인 장애는 무엇인가?

가장 치명적인 장애는 상황에 따라 다르지만, 운영 관점에서는 Deadlock이 특히 위험하다.

이유:

* 프로세스가 살아 있어 단순 Health Check가 정상으로 보일 수 있다.
* CPU와 메모리 지표가 안정적으로 보여 장애 탐지가 늦을 수 있다.
* 실제 사용자는 요청 타임아웃을 겪는다.
* 자동 복구 조건을 잘못 잡으면 장애가 장시간 지속된다.

OOM은 프로세스가 죽고 포트가 닫히기 때문에 비교적 명확하게 탐지된다. CPU Spike도 CPU 지표로 감지하기 쉽다. 반면 Deadlock은 "살아 있지만 멈춘 상태"라서 애플리케이션 레벨 Health Check가 없으면 놓치기 쉽다.

### OOM과 Deadlock이 동시에 발생하면 무엇부터 볼 것인가?

우선순위:

1. 서비스 영향 확인: 포트와 요청 응답 여부 확인
2. 프로세스 생존 확인: `pgrep`, `ps`
3. OOM 여부 확인: RSS 증가, 프로세스 종료, OOM 로그 확인
4. Deadlock 여부 확인: PID는 있는데 요청이 멈췄는지, 스레드 상태 확인

판단 기준:

* PID가 사라졌고 포트도 닫혔다면 OOM 또는 Crash를 먼저 의심한다.
* PID와 포트가 살아 있는데 요청이 멈췄다면 Deadlock을 먼저 의심한다.
* RSS가 계속 증가하다가 프로세스가 종료되었다면 OOM 가능성이 높다.
* CPU/메모리 변화가 없고 스레드가 sleeping 상태라면 Deadlock 가능성이 높다.

### 소스 코드를 수정할 수 있다면 어떻게 개선할 것인가?

OOM 개선:

* 불필요한 객체 참조 제거
* 파일/소켓/버퍼 close 보장
* 캐시 크기 제한
* 대용량 데이터 스트리밍 처리
* 메모리 프로파일링 도구 적용

CPU 개선:

* 무한 루프 또는 busy loop 제거
* rate limit, sleep, backoff 적용
* CPU-bound 작업을 worker queue로 분리
* 스레드 수를 CPU 코어 수에 맞게 제한
* 환경변수 `CPU_MAX_OCCUPY`가 실제 코드에서 반영되도록 수정

Deadlock 개선:

* 모든 코드 경로에서 락 획득 순서 통일
* 여러 락을 동시에 잡는 구간 최소화
* lock timeout 또는 try-lock 적용
* 실패 시 보유 락 해제 후 재시도
* 공유 상태를 queue 또는 actor 모델로 직렬화

### 다시 처음부터 수행한다면 어떻게 접근할 것인가?

개선된 접근 순서:

1. 장애별 성공/실패 판정 기준을 먼저 정의한다.
2. `monitor.sh`가 필요한 지표를 모두 남기는지 확인한다.
3. 환경변수가 프로세스에 실제 전달되는지 `/proc/<PID>/environ`으로 확인한다.
4. 앱이 환경변수를 실제 동작에 반영하는지 Before & After로 검증한다.
5. OOM, CPU, Deadlock을 각각 독립적으로 재현한다.
6. 로그, PID, 포트, 응답 시간, 스레드 상태를 같은 타임라인으로 정리한다.
7. 리포트에는 성공한 증거뿐 아니라 실패한 재현 시도와 그 해석도 정직하게 남긴다.

---

## 5. 제출 전 최종 점검

### 리포트 3건

* OOM 리포트에 RSS 증가 로그가 있는가?
* OOM 리포트에 `MEMORY_LIMIT` Before & After가 있는가?
* CPU 리포트에 실제 CPU 로그와 재현 실패 판단이 있는가?
* CPU 리포트에 `CPU_MAX_OCCUPY` 하드코딩/미반영 가능성이 설명되어 있는가?
* Deadlock 리포트에 PID 존재, 포트 Listen, CPU/메모리 정체 증거가 있는가?
* Deadlock 리포트에 `MULTI_THREAD_ENABLE` Before & After가 있는가?

### 증거 품질

* 로그에 타임스탬프가 있는가?
* PID가 포함되어 있는가?
* 핵심 수치가 포함되어 있는가?
* 명령어와 결과가 함께 있는가?
* 추정과 사실을 구분해서 썼는가?

### 설명 품질

* OOM Killer가 시스템 보호를 위해 프로세스를 종료한다는 점을 설명할 수 있는가?
* CPU 사용률과 CPU Latency의 차이를 설명할 수 있는가?
* Deadlock의 4조건과 순환 대기를 설명할 수 있는가?
* 살아 있지만 멈춘 상태를 어떤 순서로 진단했는지 설명할 수 있는가?
* 환경변수 조정은 임시 조치이고 코드 레벨 수정이 근본 해결이라는 점을 설명할 수 있는가?
