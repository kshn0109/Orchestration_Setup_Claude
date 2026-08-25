日本語 | [한국어](README.ko.md)

# Claude Code Orchestration (fable)

Claude Code のメインエージェントを「指揮者」に固定し、実行をコストの低い
サブエージェントへ委任させるセットアップ。指示だけに頼らず、PreToolUse
フックの**強制ゲート**がメインエージェントの直接コード修正を 1 ターン
2 ファイルまでに制限する。

| 役割        | 担当             | 既定モデル                    |
| ----------- | ---------------- | ----------------------------- |
| 計画・判断  | メインセッション | 使用中のモデル (`/model` で選択) |
| 深い推論    | deep-reasoner    | Opus 5 (effort: high)         |
| 一般実装    | executor         | Opus 5 (effort: medium)       |
| 雑務        | runner           | Haiku (effort: low)           |

## 必要なもの

- Claude Code v2.1.196 以上(推奨 v2.1.219 以上)
- Python 3
- Windows は Git Bash / macOS は標準ターミナル

## インストール

```bash
cd ja        # 韓国語版は cd ko
bash install.sh
```

これだけ。ファイル配置・CLAUDE.md・フック登録・シェルローダー・有効化まで
すべて行う。再実行しても安全で、**次に起動する claude セッションから**
適用される。

## 使い方

新しいターミナルで:

```bash
fable on        # 有効化(次のセッションから)
fable off       # 無効化
fable status    # 設置状況の点検
fable model     # 役割ごとのモデルを表示
fable model executor=sonnet reasoner=opus   # モデルを変更
```

モデルは `fable | opus | sonnet | haiku` のエイリアスか、`claude-` で始まる
完全な ID で指定する。役割は `executor | reasoner | runner`。

Claude のセッション内では `/fable-model` スキルで同じ変更ができる
(例: `/fable-model executor=sonnet`、または「実行役を sonnet に変えて」)。
メインセッション(指揮者)のモデルは `/model` で選ぶ。

## 詳細

- 仕組み・設計理由・手動インストール・検証: [ja/SETUP.md](ja/SETUP.md)
- 導入効果の分析: [ja/WHY-ORCHESTRATION.md](ja/WHY-ORCHESTRATION.md)

## アンインストール

[ja/SETUP.md](ja/SETUP.md) の「完全な削除」の節を参照。
