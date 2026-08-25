# Claude Code Orchestration (fable)

Claude Code의 메인 에이전트를 지휘자(오케스트레이터)로 한정하고, 실행을
난이도별 하위 서브에이전트에 위임하는 셋업. 지침(권고) 위에 PreToolUse 훅
게이트(강제)를 얹어, 메인 에이전트의 직접 코드 수정을 턴당 2개 파일로
제한한다.

Claude Code のメインエージェントを指揮者(オーケストレーター)に限定し、
実行を難易度別のサブエージェントへ委任するセットアップ。指示(推奨)の上に
PreToolUse フックのゲート(強制)を重ね、メインエージェントの直接コード修正を
1 ターン 2 ファイルに制限する。

| 역할 / 役割       | 담당 / 担当   | 모델 / モデル             |
| ----------------- | ------------- | ------------------------- |
| 계획·판단 / 計画·判断 | 메인 세션 / メインセッション | Fable |
| 심층 추론 / 深い推論 | deep-reasoner | Opus 5 (effort: high)     |
| 일반 구현 / 一般実装 | executor      | Opus 5 (effort: medium)   |
| 단순 잡무 / 雑務     | runner        | Haiku (effort: low)       |

## 문서 / ドキュメント

- 한국어: [ko/SETUP.md](ko/SETUP.md) · [도입 효과](ko/WHY-ORCHESTRATION.md)
- 日本語: [ja/SETUP.md](ja/SETUP.md) · [導入効果](ja/WHY-ORCHESTRATION.md)

## 설치 / インストール

요구 사항 / 要件: Claude Code v2.1.196 이상(권장 v2.1.219+) · Python 3 ·
Windows는 Git Bash / macOS는 표준 터미널.

```bash
cd ko    # 日本語版は cd ja
bash install.sh
```

설치 후 새 터미널에서 / インストール後、新しいターミナルで:

```
fable on      # 다음 세션부터 활성화 / 次のセッションから有効
fable off     # 비활성화 / 無効化
fable status  # 상태 점검 / 状態点検
```

완전 제거는 각 SETUP.md의 마지막 절 참조.
完全な削除は各 SETUP.md の最終節を参照。
