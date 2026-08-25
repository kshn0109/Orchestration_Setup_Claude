# Claude Code 오케스트레이션 셋업 — Git Bash판 (지휘·실행 분리와 강제 게이트)

> 작성: 2026-07-31 · 대상: Windows (Git Bash) / macOS + Claude Code v2.1.219 이상 (최소 v2.1.196)
> macOS는 원샷 설치(`install.sh`)로 대응한다. 아래 수동 절차와 경로 예시는
> Windows + Git Bash 기준으로 쓰여 있다.

## 무엇을 만드는가

최상위 모델(Fable)은 비싸다. 계획과 판단에는 그 값을 하지만, 보일러플레이트
작성이나 테스트 실행 같은 일에 쓰면 토큰이 낭비된다. 이 셋업은 세션의 메인
에이전트를 지휘자로 두고 실행을 하위 모델에 내려보내는 구조를 4개 계층으로
쌓는다.

| 계층   | 수단                                                                                                      | 성격     |
| ------ | --------------------------------------------------------------------------------------------------------- | -------- |
| 지침   | CLAUDE.md가 임포트하는 오케스트레이션 지침                                                                | 권고     |
| 역할   | executor(opus, effort medium) / deep-reasoner(opus, effort high) / runner(haiku, effort low) 서브에이전트 | 권고     |
| 리매핑 | sonnet 별칭을 상위 모델로 바꾸는 환경변수 (선택, 이 판 기본 미설치)                                       | 권고     |
| 게이트 | 직접 코드 수정을 턴당 2개 파일로 제한하는 PreToolUse 훅                                                   | **강제** |

핵심은 마지막 계층이다. 지침은 어겨도 아무 일도 일어나지 않지만, 게이트는
도구 호출 자체를 종료 코드 2로 차단하고 위임 지시를 모델에게 돌려준다.

설계 원칙은 본체와 로딩 코드의 분리다. 실제 내용은 전부 `~/.claude/fable/`
한 폴더에 두고, Claude Code가 읽는 설정 파일에는 그 폴더를 가리키는 짧은
로딩 코드만 넣는다. 켜고 끌 때는 설정 파일을 건드리지 않고 상태 파일과
`active.md` 사본만 바꾼다.

### 왜 심링크가 아니라 복사인가

Windows에서 심링크 생성은 SeCreateSymbolicLinkPrivilege 권한이 필요해서
관리자 PowerShell이나 개발자 모드 없이는 만들 수 없다. 더 문제인 것은
Git Bash의 `ln -s`가 권한이 없을 때 에러를 내는 대신 **조용히 복사본을
만들어버리는** MSYS 기본 동작이다. 심링크 기반 토글을 그대로 쓰면 설치가
되는 것처럼 보이다가, `fable on/off`를 해도 active.md가 실제로는 안 바뀌는
상태에 빠질 수 있다. 그래서 이 판은 처음부터 전부 복사로 처리한다:

- 에이전트 배치: `cp`로 `~/.claude/agents/`에 사본을 둔다.
- `active.md` 토글: `fable on/off`가 instructions.md 또는 blank.md를
  덮어쓴다.

트레이드오프는 하나다. 본체 폴더(`~/.claude/fable/agents/`)의 에이전트
원본을 수정하면 `~/.claude/agents/`로 재복사해야 반영된다.

### 이 판의 다른 조정 사항

- **게이트가 PowerShell 도구도 감시.** 터미널이 Git Bash여도 Claude Code
  자체는 Windows 앱이라 PowerShell 도구를 쓸 수 있다. `Set-Content`,
  `Out-File`, `Add-Content`, `Tee-Object`, 리다이렉트를 통한 코드 파일
  쓰기도 차단한다.
- **게이트의 경로 정규화.** `C:\proj\a.ts`와 `C:/Proj/A.TS`를 같은 파일로
  인식해 재수정이 이중으로 세이지 않는다. 차단 메시지의 한글이 cp949/cp932
  콘솔에서 깨지지 않도록 stderr를 UTF-8로 고정했다.
- **훅 등록은 exec form.** 훅의 `command`에 `args`를 함께 주면 셸을 거치지
  않고 실행 파일을 직접 스폰한다(공식 hooks 레퍼런스의 exec form).
  `"command": "python"` + `"args": [스크립트 경로]`로 등록하면 python.exe가
  스크립트를 직접 실행하므로 셸 종류나 셔뱅과 무관하게 동작한다.

## 공식 문서로 검증한 사실

이 셋업이 기대는 동작은 전부 공식 문서에서 확인했다.

1. **PreToolUse 훅은 종료 코드 2로 도구 호출을 차단**하고 stderr가 모델에게
   전달된다. 그 외 0이 아닌 종료 코드는 차단하지 않으므로 반드시 2를 써야
   한다. (hooks 레퍼런스)
2. **훅 페이로드의 `prompt_id`**: 사용자 프롬프트마다 새 UUID가 부여된다.
   v2.1.196 이상 필요. 이 값이 바뀌면 새 턴으로 보고 카운터를 리셋한다.
3. **서브에이전트 구분**: 훅이 서브에이전트 안에서 발화하면 페이로드에
   `agent_id`와 `agent_type`이 추가된다. 메인 스레드 호출에는 없다. 이것으로
   게이트가 위임 경로를 막지 않게 한다.
4. **서브에이전트 frontmatter**: `model`(별칭 sonnet/opus/haiku/fable 또는
   전체 모델명), `effort`(low/medium/high/xhigh/max), `tools` 필드가 공식
   지원된다.
5. **별칭 리매핑**: `ANTHROPIC_DEFAULT_SONNET_MODEL` 환경변수가 sonnet 별칭의
   해석 대상을 바꾼다. OPUS/HAIKU/FABLE용 변수도 각각 존재한다.
6. **모델 별칭의 현재 상태**: v2.1.219부터 `opus` 별칭은 Opus 5로 해석된다
   (그 이전 버전은 Opus 4.8). 별칭은 각 등급의 권장 버전으로 자동 갱신되는
   장점이 있지만, 바꿔 말하면 클라이언트 버전이 오르면 같은 정의가 소리 없이
   다른 모델을 가리킬 수 있다는 뜻이다. 그래서 이 셋업은 frontmatter에 전체
   모델 ID를 고정한다(`claude-opus-5`, `claude-haiku-4-5-20251001`). 결정론적이고,
   Agent 도구의 `model` 파라미터가 받는 별칭이 frontmatter를 덮어써 의도와
   다른 티어로 떨어지는 사고도 막는다.
7. **셸 폼 훅은 Windows에서 Git Bash로 실행**되지만(설치돼 있을 때), 이
   셋업은 그 경로 대신 exec form을 써서 의존성을 없앤다.

## 파일 구성

```
~/.claude/fable/                 (= C:\Users\사용자명\.claude\fable)
├── instructions.md          # 오케스트레이션 지침 (on일 때 active.md로 복사)
├── blank.md                 # 빈 파일 (off일 때 active.md로 복사)
├── active.md                # 현재 상태의 사본 (fable 스크립트가 관리)
├── fable                    # 토글 스크립트 (bash)
├── env.sh                   # 셸 로더 (fable 함수 정의, 모델 리매핑 없음)
├── agents/
│   ├── executor.md          # claude-opus-5 + effort: medium, 일반 실행 전담
│   ├── deep-reasoner.md     # claude-opus-5 + effort: high, 심층 추론 전담
│   └── runner.md            # claude-haiku-4-5 + effort: low, 잡무 전담 (읽기 도구만)
├── hooks/
│   └── orchestration-gate.py  # PreToolUse 강제 게이트
└── state/                   # 턴별 카운터 (자동 생성)
```

로딩 코드는 세 곳 + 에이전트 사본:

| 위치                      | 내용                       |
| ------------------------- | -------------------------- |
| `~/.claude/CLAUDE.md` 끝  | `@` 임포트 한 줄           |
| `~/.claude/agents/`       | 에이전트 파일 **사본** 3개 |
| `~/.bashrc` 끝            | `source .../env.sh` 한 줄  |
| `~/.claude/settings.json` | PreToolUse 훅 등록 블록    |

## 원샷 설치

이 폴더의 `install.sh`가 아래 전 과정(배치·CLAUDE.md·훅 등록·셸 로더·활성화)을
한 번에 실행한다. 다시 실행해도 안전하다(설치된 항목은 건너뜀).

```bash
bash install.sh    # Windows는 Git Bash에서, macOS는 터미널에서
```

macOS에서는 CLAUDE.md 임포트에 POSIX 경로, 훅의 command에 python3을 쓰고,
셸 로더를 ~/.zshrc에도 추가한다. 아래는 수동으로 설치하는 경우의 절차다.

## 설치 (수동)

전 과정 Git Bash 기준(macOS는 위의 원샷 설치를 권장). 관리자 권한 불필요. 먼저 버전을 확인한다.
v2.1.196 미만이면 게이트의 턴 감지가 동작하지 않는다.

```bash
claude --version
python --version    # Windows용 Python 3 필요 (게이트 실행용)
```

Windows의 `python`은 Microsoft Store 설치 안내만 띄우는 스텁일 수 있으니,
`python --version`이 실제 버전 문자열을 출력하는지 확인한다.

**1) 본체 배치.** 이 문서와 함께 제공된 파일들이 있는 폴더에서 실행한다.

```bash
BASE=~/.claude/fable
mkdir -p "$BASE/agents" "$BASE/hooks" ~/.claude/agents
cp instructions.md blank.md fable env.sh "$BASE/"
cp agents/executor.md agents/deep-reasoner.md agents/runner.md "$BASE/agents/"
cp hooks/orchestration-gate.py "$BASE/hooks/"
```

Git Bash에서 `chmod +x`는 필요 없다. `fable`은 env.sh의 함수가 `bash`로
직접 실행하고, 게이트는 python이 직접 실행한다.

**2) CLAUDE.md 임포트.** `~/.claude/CLAUDE.md` 맨 끝에 아래를 추가한다.
Claude Code는 CLAUDE.md 안의 `@경로` 문법으로 다른 파일을 함께 로드한다.
주의: Claude Code는 Windows 앱이므로 Git Bash식 경로(`/c/Users/...`)가
아니라 **Windows 경로 표기**로 쓴다. 사용자명은 본인 것으로.

```
<!-- fable-loader: 토글은 fable on/off. 이 줄은 유지 -->
@C:\Users\사용자명\.claude\fable\active.md
```

Git Bash에서 명령으로 한 번에 추가하려면(경로 자동 변환):

```bash
WINBASE=$(cygpath -w ~/.claude/fable/active.md)
printf '\n<!-- fable-loader: 토글은 fable on/off. 이 줄은 유지 -->\n@%s\n' "$WINBASE" >> ~/.claude/CLAUDE.md
```

**3) 에이전트 사본 배치.** 심링크 대신 복사한다.

```bash
cp "$BASE/agents/executor.md" "$BASE/agents/deep-reasoner.md" "$BASE/agents/runner.md" ~/.claude/agents/
```

본체 폴더의 에이전트 정의를 나중에 수정하면 이 복사를 다시 실행해야 반영된다.

**4) 게이트 훅 등록.** `~/.claude/settings.json`의 `hooks` 키에 추가한다
(파일이 없으면 이 내용 그대로 새로 만든다). JSON 안에서는 역슬래시를 두 번
쓴다. 사용자명은 본인 것으로. settings.json이 이미 있으면 기존 키(`model`,
`permissions` 등)를 지우지 말고 `hooks` 키만 병합한다.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash|PowerShell",
        "hooks": [
          {
            "type": "command",
            "command": "python",
            "args": [
              "C:\\Users\\사용자명\\.claude\\fable\\hooks\\orchestration-gate.py"
            ]
          }
        ]
      }
    ]
  }
}
```

`args`를 쓰는 exec form이므로 셸을 거치지 않고 python.exe가 직접 스크립트를
실행한다. 등록은 한 번만 한다. 이후 켜고 끄는 것은 스크립트가 스위치 파일을
읽어서 스스로 처리한다(off면 즉시 exit 0).

**5) 셸 로더.** `~/.bashrc` 끝에 한 줄을 추가한다. 이것이 `fable` 명령을
정의한다. env.sh는 기본적으로 그것만 한다 — 모델 리매핑은 하지 않는다.
모델은 settings.json의 `model`(메인 세션)과 각 에이전트 frontmatter의
`model` ID(서브에이전트)로 이미 결정론적으로 고정되어 있다.

```bash
printf '\n# fable 셸 로더\n[ -f "$HOME/.claude/fable/env.sh" ] && . "$HOME/.claude/fable/env.sh"\n' >> ~/.bashrc
source ~/.bashrc
```

**(선택) sonnet 리매핑.** 외부 플러그인 등에서 frontmatter에
`model: sonnet`으로 고정된 에이전트까지 상위 모델로 올리고 싶을 때만
env.sh 끝에 아래를 덧붙인다. 스위치가 on일 때만 효력이 생긴다.

```bash
FABLE_SONNET_REMAP="${FABLE_SONNET_REMAP:-claude-opus-5}"

claude() {
  if _fable_switch_on; then
    ANTHROPIC_DEFAULT_SONNET_MODEL="$FABLE_SONNET_REMAP" command claude "$@"
  else
    command claude "$@"
  fi
}
```

이 래퍼는 별칭 해석을 하이재킹하므로, 자기 에이전트의 모델을 ID로 고정하는
이 셋업의 원칙과는 방향이 다르다. 필요한 경우에만 쓴다.

주의: 모든 서브에이전트를 한 모델로 강제하는 `CLAUDE_CODE_SUBAGENT_MODEL`은
쓰지 않는다. 이 변수는 frontmatter보다 우선순위가 높아서 runner의 haiku
지정까지 덮어써 역할 분리가 깨진다.

**6) 켜기.**

```bash
fable on
fable status
```

status의 점검 항목이 전부 `[OK]`면 설치 완료다.

## 검증

게이트는 만들어두는 것보다 실제로 막히는지 증명하는 게 중요하다. 빈 작업
폴더에서 헤드리스로 확인한다.

```bash
# 메인 에이전트: 3번째 코드 파일에서 차단되어야 함
claude -p "t1.ts, t2.ts, t3.ts를 순서대로 생성해라. 차단되면 BLOCKED라고 출력하고 멈춰라."
ls *.ts    # t1.ts t2.ts 만 존재해야 정상

# 서브에이전트: 제한 없이 전부 생성되어야 함
claude -p "서브에이전트 하나를 띄워 u1.ts, u2.ts, u3.ts를 생성하게 해라."
ls u*.ts   # u1.ts u2.ts u3.ts 모두 존재해야 정상
```

두 결과가 함께 확인되어야 완성이다. 앞쪽만 성공하면 위임 경로가 막힌 것이고,
뒤쪽만 성공하면 게이트가 안 걸린 것이다.

게이트 스크립트 자체의 단위 동작(스위치 off 통과, 한도 차단, 같은 파일
재수정 허용 — 경로 대소문자·구분자 정규화 포함, 턴 리셋, 서브에이전트 통과,
문서 파일 통과, Bash sed -i·리다이렉트 차단, PowerShell
Set-Content/Out-File 차단, 읽기 전용 명령 통과, 비코드 리다이렉트 통과,
깨진 입력 fail-open)은 이 문서와 함께 배포된 스크립트 기준으로 13개 케이스
사전 검증되었다.

## 일상 사용

| 명령           | 동작                                              |
| -------------- | ------------------------------------------------- |
| `fable on`     | 지침 로드 + 게이트 활성. **다음 세션부터**        |
| `fable off`    | 전부 비활성. 로딩 코드는 그대로, 사본·상태만 전환 |
| `fable status` | 상태와 로딩 코드 + python 존재까지 점검           |
| `fable model`  | 역할별 모델 확인/변경 (아래 참조)                 |

CLAUDE.md와 훅 설정은 세션 시작 시점에 로드되므로, 토글은 이미 떠 있는
세션에는 적용되지 않는다. 게이트 스크립트만 도구 호출 시점마다 스위치를 읽는다.

지휘자 모델 자체는 이 셋업이 건드리지 않는다. 세션 안에서 `/model`로 최상위
모델을 기본값으로 저장해두면 그 위에 이 계층이 얹힌다.

### 역할별 모델 변경

서브에이전트의 모델은 각 에이전트 파일의 frontmatter `model:` 필드가 정하며,
`fable model`이 본체와 `~/.claude/agents/` 사본을 함께 고쳐 쓴다.

```bash
fable model                                  # 현재 설정 표시
fable model executor=sonnet reasoner=opus    # 역할=모델 형식으로 변경
fable model runner=claude-haiku-4-5-20251001 # 전체 모델 ID도 허용
```

- 역할: `executor` | `reasoner`(deep-reasoner) | `runner`
- 모델 별칭: `fable` | `opus` | `sonnet` | `haiku` — 스크립트가 전체 ID로
  변환해 고정하므로 별칭 재해석의 영향을 받지 않는다.
- 변경은 **다음 세션부터** 적용된다.

Claude 세션 안에서는 설치된 `/fable-model` 스킬로 같은 작업을 할 수 있다
(`/fable-model executor=sonnet` 또는 "실행자를 sonnet으로 바꿔줘").

## 게이트의 규칙과 한계

규칙: 메인 에이전트는 한 턴에 코드 파일 2개까지 직접 수정 가능, 3개째 차단.
같은 파일 재수정과 문서·설정 파일(md, json, yaml 등)은 세지 않는다.
Bash/PowerShell을 통한 코드 파일 쓰기(sed/perl -i, Set-Content, Out-File,
Add-Content, Tee-Object, 리다이렉트)는 개수 무관 항상 차단. 서브에이전트는
전부 통과.

알아둘 한계:

- **폭주 방지 장치이지 완벽한 차단막이 아니다.** 셸 우회 감지는 대표 경로만
  막는다. 그래서 지침에도 같은 규칙을 적어 권고와 강제를 겹으로 둔다.
- **오류 시 fail-open.** 게이트 버그가 모든 도구 호출을 막아 세션을
  마비시키는 것보다 그 턴의 제한을 놓치는 쪽을 택했다.
- **정당한 작업이 막히면**: 차단 메시지를 받은 모델이 위임하면 그대로
  진행된다. 사람이 직접 풀어야 하면 `fable off` 후 작업하고 다시 켠다.
- **셸 래퍼를 거치지 않는 경로**(IDE 확장, PowerShell에서 직접 실행)에서도
  지침·에이전트·게이트는 정상 동작한다. 선택 항목인 sonnet 리매핑만 이
  경로에서 적용되지 않는다.
- **다른 플러그인 훅과 충돌하지 않는다.** 등록된 PreToolUse 훅은 전부
  실행되고 하나라도 차단하면 막히는 구조라 나란히 동작한다.
- **에이전트 원본 수정 시 재복사 필요.** 복사 방식의 유일한 유지비다.
  `cp ~/.claude/fable/agents/*.md ~/.claude/agents/` 한 줄이면 된다.

## 완전 제거

로딩 코드(CLAUDE.md 임포트 한 줄, `.bashrc`의 source 한 줄, settings.json
hooks 블록)와 에이전트 사본 3개를 지우고 `~/.claude/fable/` 폴더,
`~/.claude/skills/fable-model/` 폴더, `~/.claude/.fable-state` 파일을
삭제하면 흔적 없이 사라진다.

## 참고: SDK에서 같은 원리 — advisor 전략

Claude Code 밖에서 API/SDK로 에이전트를 직접 짤 때는 방향을 뒤집은 공식
기능이 있다. 싼 실행자 모델이 작업을 주도하고, 어려운 판단에 부딪혔을 때만
advisor 툴로 상위 모델에 상담하는 구조다(`advisor` 툴 타입, `max_uses`로
상담 횟수 제한). 판단은 비싼 모델, 실행은 싼 모델이라는 원리는 동일하고,
Claude Code 안에서 멀티스텝 작업을 통째로 맡길 때는 이 문서의 지휘-위임이,
SDK로 대부분 싸게 돌리며 가끔 최상위 판단만 빌릴 때는 advisor가 맞다.
자세한 것은 Anthropic 공식 문서의 advisor 항목을 참고.
