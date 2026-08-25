---
name: fable-model
description: fable オーケストレーションのサブエージェント(executor/deep-reasoner/runner)のモデルを確認・変更する。「実行役を sonnet に」「推論役を opus に変えて」「役割ごとのモデルを見せて」といった依頼で使う。
---

fable オーケストレーションの役割ごとのモデルを設定するスキル。エージェント
定義ファイルの frontmatter `model:` フィールドを fable スクリプトが書き換える。

## 使い方

`/fable-model [役割=モデル ...]`

- 役割: `executor`(一般実装) | `reasoner`(深い推論、deep-reasoner) | `runner`(雑務)
- モデル: `fable` | `opus` | `sonnet` | `haiku` | `claude-` で始まる完全なモデル ID

例: `/fable-model executor=sonnet reasoner=opus`

## 実行手順

1. 引数があれば Bash で実行する:

   ```
   bash ~/.claude/fable/fable model <引数をそのまま>
   ```

   引数がない、または「見せて」系の依頼なら現在の設定だけを表示する:

   ```
   bash ~/.claude/fable/fable model
   ```

2. 自然言語の依頼(「実行役を sonnet に」)は `役割=モデル` 形式に変換して渡す。
   役割の対応: 実行役→executor、推論役→reasoner、雑務/ランナー→runner。

3. 出力をそのまま報告し、変更は**次に起動する claude セッションから**確実に
   適用されると伝える。

## 注意

- メインセッション(オーケストレーター)のモデルはこのスキルではなく `/model` で変える。
- runner に高単価モデルを指定する依頼はそのまま実行するが、雑務担当なので
  コスト効率が下がると一文だけ言及する。
- スクリプトがエラーを出したら(不明な役割/モデル)、エラーメッセージをそのまま
  見せて正しい形式を案内する。エージェントファイルを直接修正しない。
