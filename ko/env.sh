# fable 셸 로더 — Git Bash의 ~/.bashrc에서 source 된다.
#
# fable 함수만 정의한다. 토글 스크립트 호출을 감싸므로 PATH 배치가 필요 없다.
#
# 모델 리매핑(ANTHROPIC_DEFAULT_SONNET_MODEL 등)은 하지 않는다. 별칭을
# 하이재킹하면 서브에이전트 frontmatter의 전체 모델 ID 고정과 상충한다.
#   메인 세션(오케스트레이터) 모델: settings.json의 "model".
#   서브에이전트 모델: ~/.claude/fable/agents/*.md frontmatter의 model 필드.
#     executor, deep-reasoner -> claude-opus-5
#     runner                  -> claude-haiku-4-5-20251001
# 외부 플러그인 등에서 model: sonnet으로 고정된 에이전트까지 상위 모델로
# 올리고 싶다면 SETUP.md의 선택 항목(claude 래퍼 스니펫)을 참고한다.
#
# fable 스위치(~/.claude/.fable-state)는 지침 로드와 게이트 훅을 제어한다.

fable() {
  bash "$HOME/.claude/fable/fable" "$@"
}

_fable_switch_on() {
  [ "$(cat "$HOME/.claude/.fable-state" 2>/dev/null | tr -d '\r\n')" = "on" ]
}
