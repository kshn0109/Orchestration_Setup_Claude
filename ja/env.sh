# fable シェルローダー — Git Bash の ~/.bashrc から source される。
#
# fable 関数だけを定義する。トグルスクリプトの呼び出しをラップするので PATH への
# 配置は不要になる。
#
# モデルのリマップ(ANTHROPIC_DEFAULT_SONNET_MODEL など)はしない。エイリアスを
# ハイジャックすると、サブエージェント frontmatter の完全なモデル ID 固定と衝突する。
#   メインセッション(オーケストレーター)のモデル: settings.json の "model"。
#   サブエージェントのモデル: ~/.claude/fable/agents/*.md frontmatter の model フィールド。
#     executor, deep-reasoner -> claude-opus-5
#     runner                  -> claude-haiku-4-5-20251001
# 外部プラグインなどで model: sonnet に固定されたエージェントまで上位モデルへ
# 上げたい場合は、SETUP.md のオプション項目(claude ラッパーのスニペット)を参照する。
#
# fable スイッチ(~/.claude/.fable-state)は指示のロードとゲートフックを制御する。

fable() {
  bash "$HOME/.claude/fable/fable" "$@"
}

_fable_switch_on() {
  [ "$(cat "$HOME/.claude/.fable-state" 2>/dev/null | tr -d '\r\n')" = "on" ]
}
