#!/usr/bin/env python3
"""fable オーケストレーションゲート (PreToolUse フック) — Windows ネイティブ版。

役割
----
メインエージェントが 1 ターン(prompt_id 基準)に直接修正できるコードファイル数を
制限する。上限を超える修正の試みは終了コード 2 でブロックし、stderr メッセージで
サブエージェントへの委任を指示する。Bash/PowerShell 経由のコードファイル書き込みは
常にブロックする。

通過条件
--------
* スイッチファイル(~/.claude/.fable-state)が "on" でなければすべて通過
* ペイロードに agent_id または agent_type があれば(= サブエージェント)すべて通過
* コード拡張子でないファイル(ドキュメント/設定)は個数に関係なく通過
* 同じターンに既に修正したファイルの再修正は個数に数えない

安全装置
--------
スクリプト内部のエラーは必ず通過(fail-open)として扱い、ゲートのバグが
セッション全体を麻痺させないようにする。

要求: Claude Code v2.1.196 以上 (prompt_id)、Windows 用 Python 3
登録: settings.json で exec form として登録 — "command": "python",
      "args": ["C:\\Users\\ユーザー名\\.claude\\fable\\hooks\\orchestration-gate.py"]
"""

import json
import os
import re
import sys
import time

# Windows コンソールの既定エンコーディング(cp932/cp949)で日本語 stderr が壊れないよう UTF-8 に固定
try:
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

MAX_FILES_PER_TURN = 2
SWITCH_FILE = os.path.expanduser("~/.claude/.fable-state")
COUNTER_DIR = os.path.expanduser("~/.claude/fable/state")
STALE_SECONDS = 24 * 60 * 60

CODE_EXTENSIONS = frozenset("""
    py ipynb js jsx ts tsx mjs cjs vue svelte astro
    go rs c h cc cpp hpp cs java kt kts swift scala
    rb php lua dart ex exs zig sql
    sh bash zsh ps1 psm1 bat cmd html css scss sass less
""".split())

_EXT_ALT = "|".join(sorted(CODE_EXTENSIONS))
# sed -i / perl -i 系のインプレース編集 (Bash)
RE_INPLACE = re.compile(r"\b(?:sed|perl)\b[^|;&]*\s-\w*i")
# > , >> , tee でコード拡張子のファイルに書くリダイレクト (Bash/PowerShell 共通)
RE_REDIRECT = re.compile(
    r"(?:>{1,2}|\btee\b(?:\s+-\S+)*)\s*['\"]?\S+\.(?:%s)(?:['\"]|\s|$)" % _EXT_ALT
)
# PowerShell の書き込み cmdlet
RE_PS_WRITE = re.compile(
    r"\b(?:Set-Content|Add-Content|Out-File|Tee-Object)\b", re.IGNORECASE
)
RE_ANY_CODE_PATH = re.compile(r"\.(?:%s)\b" % _EXT_ALT, re.IGNORECASE)

DELEGATION_HINT = (
    "一般的な実装・修正・テスト・レビューは executor(Opus 5)へ、"
    "深い推論・設計・根本原因分析は deep-reasoner(Opus 5)へ、"
    "単純なコマンド・照会は runner(Haiku)へ委任してください。"
)


def switch_is_on():
    try:
        with open(SWITCH_FILE, encoding="utf-8") as f:
            return f.read().strip() == "on"
    except OSError:
        return False


def looks_like_code(path):
    _, dot, ext = path.rpartition(".")
    return bool(dot) and ext.lower() in CODE_EXTENSIONS


def block(message):
    sys.stderr.write(message)
    sys.exit(2)


def load_counter(counter_path, prompt_id):
    """現在のターンのカウンターを読む。ターンが変わっていれば新しく始める。"""
    try:
        with open(counter_path, encoding="utf-8") as f:
            saved = json.load(f)
        if saved.get("prompt_id") == prompt_id:
            return saved
    except (OSError, ValueError):
        pass
    return {"prompt_id": prompt_id, "files": []}


def sweep_stale_counters():
    """古いセッションのカウンターファイルを片付ける。失敗しても無視。"""
    try:
        now = time.time()
        for name in os.listdir(COUNTER_DIR):
            p = os.path.join(COUNTER_DIR, name)
            if now - os.path.getmtime(p) > STALE_SECONDS:
                os.remove(p)
    except OSError:
        pass


def check_shell(tool, command):
    if not RE_ANY_CODE_PATH.search(command):
        return  # コードファイルに触らないコマンド
    writes = RE_REDIRECT.search(command)
    if tool == "Bash":
        writes = writes or RE_INPLACE.search(command)
    else:  # PowerShell
        writes = writes or RE_PS_WRITE.search(command)
    if writes:
        block(
            "[fable ゲート] メインエージェントはシェル(%s)でコードファイルを修正できません。"
            "Edit/Write ツール(1 ターンあたり %d ファイル)を使うか委任してください。%s"
            % (tool, MAX_FILES_PER_TURN, DELEGATION_HINT)
        )


def check_file_edit(data):
    tool_input = data.get("tool_input") or {}
    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if not path or not looks_like_code(path):
        return  # ドキュメント・設定ファイルは自由

    session = re.sub(r"[^\w-]", "", data.get("session_id", "unknown"))
    prompt_id = data.get("prompt_id", "")
    counter_path = os.path.join(COUNTER_DIR, "%s.json" % session)

    counter = load_counter(counter_path, prompt_id)
    if not counter["files"]:
        sweep_stale_counters()

    # Windows のパスの大文字小文字・区切り文字の違いで同じファイルが二重に
    # 数えられないよう正規化する。os.path.normcase は実行プラットフォームで
    # 動作が変わるため、明示的に処理する。
    def norm_win(p):
        return p.replace("/", "\\").lower()

    if norm_win(path) in (norm_win(p) for p in counter["files"]):
        return  # 同じファイルの再修正は許可

    if len(counter["files"]) >= MAX_FILES_PER_TURN:
        block(
            "[fable ゲート] このターンに直接修正したコードファイルは既に %d 個です(%s)。"
            "いま修正しようとした %s は再試行せず、Agent ツールで委任してください。%s"
            % (
                MAX_FILES_PER_TURN,
                ", ".join(counter["files"]),
                path,
                DELEGATION_HINT,
            )
        )

    counter["files"].append(path)
    os.makedirs(COUNTER_DIR, exist_ok=True)
    with open(counter_path, "w", encoding="utf-8") as f:
        json.dump(counter, f)


def main():
    if not switch_is_on():
        return

    data = json.load(sys.stdin)

    # サブエージェントのツール呼び出しはゲートの対象外。委任こそが実行経路だ。
    if data.get("agent_id") or data.get("agent_type"):
        return

    tool = data.get("tool_name", "")
    if tool in ("Bash", "PowerShell"):
        check_shell(tool, (data.get("tool_input") or {}).get("command", ""))
    elif tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        check_file_edit(data)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)  # fail-open: ゲートのエラーはブロックではなく通過
