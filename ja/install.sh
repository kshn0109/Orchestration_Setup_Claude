#!/usr/bin/env bash
# install.sh — fable オーケストレーション層のワンショットインストーラー
#
# 対応: Windows (Git Bash) / macOS。管理者権限は不要。
# 再実行しても安全(設置済みの項目はスキップする)。
#
#   Windows: Git Bash でこのフォルダに移動し  bash install.sh
#   macOS:   ターミナルでこのフォルダに移動し  bash install.sh
#
# 手順の詳細と設計理由は SETUP.md を参照。

set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
BASE="$HOME/.claude/fable"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
SETTINGS="$HOME/.claude/settings.json"

info() { printf '%s\n' "$*"; }
fail() { printf 'エラー: %s\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  Darwin)               OS=mac ;;
  *)                    OS=posix ;;  # Linux などもそのまま POSIX 経路で動く
esac

# --- 前提チェック -----------------------------------------------------------

# Windows の "python" は Microsoft Store のスタブのことがあるので、
# 実際にバージョン文字列を出すものだけを採用する。
# Windows では SETUP.md の記載どおり python を優先し、macOS では python3 を優先する。
PY=
if [ "$OS" = windows ]; then PY_CANDIDATES="python python3"; else PY_CANDIDATES="python3 python"; fi
for c in $PY_CANDIDATES; do
  if command -v "$c" >/dev/null 2>&1 && "$c" --version 2>/dev/null | grep -q '^Python 3'; then
    PY=$c
    break
  fi
done
[ -n "$PY" ] || fail "Python 3 が見つかりません。インストールしてから再実行してください。"

if [ "$OS" = windows ] && ! command -v cygpath >/dev/null 2>&1; then
  fail "cygpath がありません。Windows では Git Bash から実行してください。"
fi

for f in instructions.md blank.md fable env.sh \
         agents/executor.md agents/deep-reasoner.md agents/runner.md \
         hooks/orchestration-gate.py; do
  [ -f "$SRC/$f" ] || fail "配布ファイルが見つかりません: $SRC/$f — このフォルダから実行してください。"
done

if command -v claude >/dev/null 2>&1; then
  info "claude バージョン: $(claude --version 2>/dev/null || echo '?') (必要: v2.1.196 以上、推奨 v2.1.219 以上)"
else
  info "警告: claude コマンドが見つかりません。設置は続行しますが、Claude Code v2.1.196 以上が必要です。"
fi

# --- 1) 本体の配置 ----------------------------------------------------------

mkdir -p "$BASE/agents" "$BASE/hooks" "$HOME/.claude/agents"
cp -f "$SRC/instructions.md" "$SRC/blank.md" "$SRC/fable" "$SRC/env.sh" "$BASE/"
cp -f "$SRC/agents/executor.md" "$SRC/agents/deep-reasoner.md" "$SRC/agents/runner.md" "$BASE/agents/"
cp -f "$SRC/hooks/orchestration-gate.py" "$BASE/hooks/"
info "[ok] 本体を配置 ($BASE)"

cp -f "$BASE/agents/executor.md" "$BASE/agents/deep-reasoner.md" "$BASE/agents/runner.md" "$HOME/.claude/agents/"
info "[ok] エージェントのコピー 3 個 (~/.claude/agents/)"

# --- 2) CLAUDE.md インポート ------------------------------------------------

if [ "$OS" = windows ]; then
  ACTIVE_PATH=$(cygpath -w "$BASE/active.md")
  GATE_PATH=$(cygpath -w "$BASE/hooks/orchestration-gate.py")
else
  ACTIVE_PATH="$BASE/active.md"
  GATE_PATH="$BASE/hooks/orchestration-gate.py"
fi

if grep -q 'fable[\\/]active\.md' "$CLAUDE_MD" 2>/dev/null; then
  info "[skip] CLAUDE.md インポートは設置済み"
else
  printf '\n<!-- fable-loader: トグルは fable on/off。この行は残す -->\n@%s\n' "$ACTIVE_PATH" >> "$CLAUDE_MD"
  info "[ok] CLAUDE.md にインポートを追加"
fi

# --- 3) settings.json へのゲートフック登録 (既存キーを保持してマージ) ------

"$PY" - "$SETTINGS" "$PY" "$GATE_PATH" <<'PYEOF'
import json, os, sys

# Windows コンソール(cp932/cp949)で日本語出力が壊れないよう UTF-8 に固定
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
        sys.stderr.write("settings.json が JSON として壊れています。手動で修正してから再実行してください。\n")
        sys.exit(3)

if "orchestration-gate" in json.dumps(cfg):
    print("[skip] ゲートフックは登録済み")
    sys.exit(0)

entry = {
    "matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash|PowerShell",
    "hooks": [{"type": "command", "command": cmd, "args": [script]}],
}
cfg.setdefault("hooks", {}).setdefault("PreToolUse", []).append(entry)
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("[ok] settings.json にゲートフックを登録")
PYEOF

# --- 4) シェルローダー ------------------------------------------------------

add_loader() {
  if grep -q 'fable/env.sh' "$1" 2>/dev/null; then
    info "[skip] シェルローダーは設置済み ($1)"
  else
    printf '\n# fable シェルローダー\n[ -f "$HOME/.claude/fable/env.sh" ] && . "$HOME/.claude/fable/env.sh"\n' >> "$1"
    info "[ok] シェルローダーを追加 ($1)"
  fi
}

add_loader "$HOME/.bashrc"
if [ "$OS" = mac ]; then
  add_loader "$HOME/.zshrc"   # macOS の既定シェルは zsh
fi

# --- 5) 有効化 + 点検 -------------------------------------------------------

echo
bash "$BASE/fable" on
echo
bash "$BASE/fable" status
echo
info "完了。新しいターミナルを開く(または source ~/.bashrc)と fable コマンドが使えます。"
info "オーケストレーションは次に起動する claude セッションから適用されます。"
