[日本語](README.md) | 한국어

# Claude Code Orchestration (fable)

Claude Code의 메인 에이전트를 "지휘자"로 고정하고, 실행을 단가가 낮은
서브에이전트에 위임시키는 셋업. 지침에만 의존하지 않고 PreToolUse 훅의
**강제 게이트**가 메인 에이전트의 직접 코드 수정을 턴당 2개 파일로 제한한다.

| 역할       | 담당        | 기본 모델                      |
| ---------- | ----------- | ------------------------------ |
| 계획·판단  | 메인 세션   | 사용 중인 모델 (`/model`로 선택) |
| 심층 추론  | deep-reasoner | Opus 5 (effort: high)        |
| 일반 구현  | executor    | Opus 5 (effort: medium)        |
| 잡무       | runner      | Haiku (effort: low)            |

## 필요한 것

- Claude Code v2.1.196 이상(권장 v2.1.219 이상)
- Python 3
- Windows는 Git Bash / macOS는 표준 터미널

## 설치

```bash
cd ko        # 日本語版은 cd ja
bash install.sh
```

이걸로 끝. 파일 배치·CLAUDE.md·훅 등록·셸 로더·활성화까지 전부 수행한다.
다시 실행해도 안전하며, **다음에 시작하는 claude 세션부터** 적용된다.

## 사용법

새 터미널에서:

```bash
fable on        # 활성화 (다음 세션부터)
fable off       # 비활성화
fable status    # 설치 상태 점검
fable model     # 역할별 모델 표시
fable model executor=sonnet reasoner=opus   # 모델 변경
```

모델은 `fable | opus | sonnet | haiku` 별칭 또는 `claude-`로 시작하는
전체 ID로 지정한다. 역할은 `executor | reasoner | runner`.

Claude 세션 안에서는 `/fable-model` 스킬로 같은 변경을 할 수 있다
(예: `/fable-model executor=sonnet`, 또는 "실행자를 sonnet으로 바꿔줘").
메인 세션(지휘자)의 모델은 `/model`로 고른다.

## 상세

- 구조·설계 이유·수동 설치·검증: [ko/SETUP.md](ko/SETUP.md)
- 도입 효과 분석: [ko/WHY-ORCHESTRATION.md](ko/WHY-ORCHESTRATION.md)

## 제거

[ko/SETUP.md](ko/SETUP.md)의 "완전 제거" 절 참조.
