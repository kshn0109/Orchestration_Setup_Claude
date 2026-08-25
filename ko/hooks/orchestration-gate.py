#!/usr/bin/env python3
"""fable 오케스트레이션 게이트 (PreToolUse 훅) — Windows 네이티브판.

역할
----
메인 에이전트가 한 턴(prompt_id 기준)에 직접 수정할 수 있는 코드 파일 수를
제한한다. 한도를 넘는 수정 시도는 종료 코드 2로 차단하고, stderr 메시지로
서브에이전트 위임을 지시한다. Bash/PowerShell을 통한 코드 파일 쓰기는
항상 차단한다.

통과 조건
---------
* 스위치 파일(~/.claude/.fable-state)이 "on"이 아니면 전부 통과
* 페이로드에 agent_id 또는 agent_type이 있으면(=서브에이전트) 전부 통과
* 코드 확장자가 아닌 파일(문서/설정)은 개수와 무관하게 통과
* 같은 턴에 이미 수정한 파일의 재수정은 개수에 세지 않음

안전장치
--------
스크립트 내부 오류는 무조건 통과(fail-open)로 처리해 게이트 버그가
세션 전체를 마비시키지 않게 한다.

요구: Claude Code v2.1.196 이상 (prompt_id), Windows용 Python 3
등록: settings.json에서 exec form으로 등록 — "command": "python",
      "args": ["C:\\Users\\사용자명\\.claude\\fable\\hooks\\orchestration-gate.py"]
"""

import json
import os
import re
import sys
import time

# Windows 콘솔 기본 인코딩(cp949/cp932)에서 한글 stderr가 깨지지 않도록 UTF-8 고정
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
# sed -i / perl -i 계열 인플레이스 편집 (Bash)
RE_INPLACE = re.compile(r"\b(?:sed|perl)\b[^|;&]*\s-\w*i")
# > , >> , tee 로 코드 확장자 파일에 쓰는 리다이렉트 (Bash/PowerShell 공통)
RE_REDIRECT = re.compile(
    r"(?:>{1,2}|\btee\b(?:\s+-\S+)*)\s*['\"]?\S+\.(?:%s)(?:['\"]|\s|$)" % _EXT_ALT
)
# PowerShell 쓰기 cmdlet
RE_PS_WRITE = re.compile(
    r"\b(?:Set-Content|Add-Content|Out-File|Tee-Object)\b", re.IGNORECASE
)
RE_ANY_CODE_PATH = re.compile(r"\.(?:%s)\b" % _EXT_ALT, re.IGNORECASE)

DELEGATION_HINT = (
    "일반 구현·수정·테스트·리뷰는 executor(Opus 5)로, "
    "심층 추론·설계·근본원인 분석은 deep-reasoner(Opus 5)로, "
    "단순 명령·조회는 runner(Haiku)로 위임하세요."
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
    """현재 턴의 카운터를 읽는다. 턴이 바뀌었으면 새로 시작한다."""
    try:
        with open(counter_path, encoding="utf-8") as f:
            saved = json.load(f)
        if saved.get("prompt_id") == prompt_id:
            return saved
    except (OSError, ValueError):
        pass
    return {"prompt_id": prompt_id, "files": []}


def sweep_stale_counters():
    """오래된 세션의 카운터 파일을 정리한다. 실패해도 무시."""
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
        return  # 코드 파일을 건드리지 않는 명령
    writes = RE_REDIRECT.search(command)
    if tool == "Bash":
        writes = writes or RE_INPLACE.search(command)
    else:  # PowerShell
        writes = writes or RE_PS_WRITE.search(command)
    if writes:
        block(
            "[fable 게이트] 메인 에이전트는 셸(%s)로 코드 파일을 수정할 수 없습니다. "
            "Edit/Write 도구(턴당 %d개 파일)를 쓰거나 위임하세요. %s"
            % (tool, MAX_FILES_PER_TURN, DELEGATION_HINT)
        )


def check_file_edit(data):
    tool_input = data.get("tool_input") or {}
    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if not path or not looks_like_code(path):
        return  # 문서·설정 파일은 자유

    session = re.sub(r"[^\w-]", "", data.get("session_id", "unknown"))
    prompt_id = data.get("prompt_id", "")
    counter_path = os.path.join(COUNTER_DIR, "%s.json" % session)

    counter = load_counter(counter_path, prompt_id)
    if not counter["files"]:
        sweep_stale_counters()

    # Windows 경로 대소문자·구분자 차이로 같은 파일이 두 번 세이지 않게 정규화.
    # os.path.normcase는 실행 플랫폼에 따라 동작이 달라지므로 명시적으로 처리한다.
    def norm_win(p):
        return p.replace("/", "\\").lower()

    if norm_win(path) in (norm_win(p) for p in counter["files"]):
        return  # 같은 파일 재수정은 허용

    if len(counter["files"]) >= MAX_FILES_PER_TURN:
        block(
            "[fable 게이트] 이번 턴에 직접 수정한 코드 파일이 이미 %d개입니다(%s). "
            "지금 수정하려던 %s 은(는) 재시도하지 말고 Agent 도구로 위임하세요. %s"
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

    # 서브에이전트의 도구 호출은 게이트 대상이 아니다. 위임이 곧 실행 경로다.
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
        sys.exit(0)  # fail-open: 게이트 오류는 차단이 아니라 통과
