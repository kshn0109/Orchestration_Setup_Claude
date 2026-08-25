#!/usr/bin/env bash
# install.sh — fable 오케스트레이션 계층 원샷 설치 스크립트
#
# 지원: Windows (Git Bash) / macOS. 관리자 권한 불필요.
# 다시 실행해도 안전하다(이미 설치된 항목은 건너뜀).
#
#   Windows: Git Bash에서 이 폴더로 이동 후  bash install.sh
#   macOS:   터미널에서 이 폴더로 이동 후    bash install.sh
#
# 절차의 상세와 설계 이유는 SETUP.md 참조.

set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
BASE="$HOME/.claude/fable"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
SETTINGS="$HOME/.claude/settings.json"

info() { printf '%s\n' "$*"; }
fail() { printf '오류: %s\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  Darwin)               OS=mac ;;
  *)                    OS=posix ;;  # Linux 등도 POSIX 경로로 그대로 동작
esac

# --- 사전 점검 --------------------------------------------------------------

# Windows의 "python"은 Microsoft Store 스텁일 수 있으므로,
# 실제 버전 문자열을 출력하는 것만 채택한다.
# Windows에서는 SETUP.md 기재대로 python을, macOS에서는 python3을 우선한다.
PY=
if [ "$OS" = windows ]; then PY_CANDIDATES="python python3"; else PY_CANDIDATES="python3 python"; fi
for c in $PY_CANDIDATES; do
  if command -v "$c" >/dev/null 2>&1 && "$c" --version 2>/dev/null | grep -q '^Python 3'; then
    PY=$c
    break
  fi
done
[ -n "$PY" ] || fail "Python 3을 찾을 수 없습니다. 설치 후 다시 실행하세요."

if [ "$OS" = windows ] && ! command -v cygpath >/dev/null 2>&1; then
  fail "cygpath가 없습니다. Windows에서는 Git Bash에서 실행하세요."
fi

for f in instructions.md blank.md fable env.sh \
         agents/executor.md agents/deep-reasoner.md agents/runner.md \
         hooks/orchestration-gate.py; do
  [ -f "$SRC/$f" ] || fail "배포 파일이 없습니다: $SRC/$f — 이 폴더에서 실행하세요."
done

if command -v claude >/dev/null 2>&1; then
  info "claude 버전: $(claude --version 2>/dev/null || echo '?') (필요: v2.1.196 이상, 권장 v2.1.219 이상)"
else
  info "경고: claude 명령을 찾을 수 없습니다. 설치는 계속하지만 Claude Code v2.1.196 이상이 필요합니다."
fi

# --- 1) 본체 배치 -------------------------------------------------------------

mkdir -p "$BASE/agents" "$BASE/hooks" "$HOME/.claude/agents"
cp -f "$SRC/instructions.md" "$SRC/blank.md" "$SRC/fable" "$SRC/env.sh" "$BASE/"
cp -f "$SRC/agents/executor.md" "$SRC/agents/deep-reasoner.md" "$SRC/agents/runner.md" "$BASE/agents/"
cp -f "$SRC/hooks/orchestration-gate.py" "$BASE/hooks/"
info "[ok] 본체 배치 ($BASE)"

cp -f "$BASE/agents/executor.md" "$BASE/agents/deep-reasoner.md" "$BASE/agents/runner.md" "$HOME/.claude/agents/"
info "[ok] 에이전트 사본 3개 (~/.claude/agents/)"

# --- 2) CLAUDE.md 임포트 ------------------------------------------------------

if [ "$OS" = windows ]; then
  ACTIVE_PATH=$(cygpath -w "$BASE/active.md")
  GATE_PATH=$(cygpath -w "$BASE/hooks/orchestration-gate.py")
else
  ACTIVE_PATH="$BASE/active.md"
  GATE_PATH="$BASE/hooks/orchestration-gate.py"
fi

if grep -q 'fable[\\/]active\.md' "$CLAUDE_MD" 2>/dev/null; then
  info "[skip] CLAUDE.md 임포트는 이미 설치됨"
else
  printf '\n<!-- fable-loader: 토글은 fable on/off. 이 줄은 유지 -->\n@%s\n' "$ACTIVE_PATH" >> "$CLAUDE_MD"
  info "[ok] CLAUDE.md에 임포트 추가"
fi

# --- 3) settings.json 게이트 훅 등록 (기존 키를 보존하며 병합) ---------------

"$PY" - "$SETTINGS" "$PY" "$GATE_PATH" <<'PYEOF'
import json, os, sys

# Windows 콘솔(cp932/cp949)에서 한국어 출력이 깨지지 않도록 UTF-8 고정
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

path, cmd, script = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f:
            cfg = json.load(f)
    except ValueError:
        sys.stderr.write("settings.json이 JSON으로 깨져 있습니다. 수동으로 고친 뒤 다시 실행하세요.\n")
        sys.exit(3)

if "orchestration-gate" in json.dumps(cfg):
    print("[skip] 게이트 훅은 이미 등록됨")
    sys.exit(0)

entry = {
    "matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash|PowerShell",
    "hooks": [{"type": "command", "command": cmd, "args": [script]}],
}
cfg.setdefault("hooks", {}).setdefault("PreToolUse", []).append(entry)
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("[ok] settings.json에 게이트 훅 등록")
PYEOF

# --- 4) 셸 로더 ---------------------------------------------------------------

add_loader() {
  if grep -q 'fable/env.sh' "$1" 2>/dev/null; then
    info "[skip] 셸 로더는 이미 설치됨 ($1)"
  else
    printf '\n# fable 셸 로더\n[ -f "$HOME/.claude/fable/env.sh" ] && . "$HOME/.claude/fable/env.sh"\n' >> "$1"
    info "[ok] 셸 로더 추가 ($1)"
  fi
}

add_loader "$HOME/.bashrc"
if [ "$OS" = mac ]; then
  add_loader "$HOME/.zshrc"   # macOS 기본 셸은 zsh
fi

# --- 5) 활성화 + 점검 ----------------------------------------------------------

echo
bash "$BASE/fable" on
echo
bash "$BASE/fable" status
echo
info "완료. 새 터미널을 열면(또는 source ~/.bashrc) fable 명령을 쓸 수 있습니다."
info "오케스트레이션은 다음에 시작하는 claude 세션부터 적용됩니다."
