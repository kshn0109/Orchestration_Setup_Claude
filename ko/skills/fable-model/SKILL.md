---
name: fable-model
description: fable 오케스트레이션 서브에이전트(executor/deep-reasoner/runner)의 모델을 확인하거나 변경한다. "실행자 모델을 sonnet으로", "추론자를 opus로 바꿔줘", "역할별 모델 보여줘" 같은 요청에 사용.
---

fable 오케스트레이션의 역할별 모델을 설정하는 스킬이다. 에이전트 정의
파일의 frontmatter `model:` 필드를 fable 스크립트가 고쳐 쓴다.

## 사용법

`/fable-model [역할=모델 ...]`

- 역할: `executor`(일반 구현) | `reasoner`(심층 추론, deep-reasoner) | `runner`(잡무)
- 모델: `fable` | `opus` | `sonnet` | `haiku` | `claude-`로 시작하는 전체 모델 ID

예: `/fable-model executor=sonnet reasoner=opus`

## 실행 절차

1. 인자가 있으면 Bash로 실행한다:

   ```
   bash ~/.claude/fable/fable model <인자들 그대로>
   ```

   인자가 없거나 "보여줘"류 요청이면 현재 설정만 표시한다:

   ```
   bash ~/.claude/fable/fable model
   ```

2. 자연어 요청("실행자를 sonnet으로")이면 `역할=모델` 형식으로 변환해 넘긴다.
   역할 대응: 실행자→executor, 추론자→reasoner, 잡무/러너→runner.

3. 출력 결과를 그대로 보고하고, 변경은 **다음 claude 세션부터** 확실히
   적용된다고 알린다.

## 주의

- 메인 세션(오케스트레이터)의 모델은 이 스킬이 아니라 `/model`로 바꾼다.
- runner에 고단가 모델을 지정하는 요청은 그대로 수행하되, 잡무 담당이라
  비용 효율이 떨어진다고 한 문장으로 언급한다.
- 스크립트가 에러를 내면(알 수 없는 역할/모델) 에러 메시지를 그대로 보여주고
  올바른 형식을 안내한다. 에이전트 파일을 직접 수정하지 않는다.
