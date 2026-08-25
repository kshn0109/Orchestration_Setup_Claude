# Claude Code オーケストレーション セットアップ — Git Bash 版 (指揮・実行の分離と強制ゲート)

> 作成: 2026-07-31 · 対象: Windows + Git Bash + Claude Code v2.1.219 以上 (最低 v2.1.196)

## 何を作るのか

最上位モデル(Fable)は高い。計画と判断にはその価値があるが、ボイラープレートの
作成やテスト実行のような仕事に使うとトークンの無駄になる。このセットアップは
セッションのメインエージェントを指揮者に置き、実行を下位モデルへ降ろす構造を
4 つの層として積む。

| 層       | 手段                                                                                                          | 性格     |
| -------- | ------------------------------------------------------------------------------------------------------------- | -------- |
| 指示     | CLAUDE.md がインポートするオーケストレーション指示                                                            | 推奨     |
| 役割     | executor(opus, effort medium) / deep-reasoner(opus, effort high) / runner(haiku, effort low) サブエージェント | 推奨     |
| リマップ | sonnet エイリアスを上位モデルに変える環境変数 (オプション、この版では既定で未設置)                            | 推奨     |
| ゲート   | 直接のコード修正を 1 ターン 2 ファイルに制限する PreToolUse フック                                            | **強制** |

核心は最後の層だ。指示は破っても何も起きないが、ゲートはツール呼び出し自体を
終了コード 2 でブロックし、委任の指示をモデルに返す。

設計原則は本体とローディングコードの分離だ。実際の内容はすべて `~/.claude/fable/`
一つのフォルダに置き、Claude Code が読む設定ファイルにはそのフォルダを指す短い
ローディングコードだけを入れる。オン・オフの切り替えでは設定ファイルに触らず、
状態ファイルと `active.md` のコピーだけを差し替える。

### なぜシンボリックリンクではなくコピーなのか

Windows でのシンボリックリンク作成は SeCreateSymbolicLinkPrivilege 権限が必要で、
管理者 PowerShell や開発者モードなしには作れない。さらに問題なのは、
Git Bash の `ln -s` が権限のないときエラーを出す代わりに **黙ってコピーを
作ってしまう** MSYS の既定動作だ。シンボリックリンク前提のトグルをそのまま使うと、
インストールできたように見えて、`fable on/off` をしても active.md が実際には
切り替わらない状態に陥ることがある。そこでこの版は最初からすべてコピーで処理する:

- エージェントの配置: `cp` で `~/.claude/agents/` にコピーを置く。
- `active.md` のトグル: `fable on/off` が instructions.md または blank.md で
  上書きする。

トレードオフは一つだけ。本体フォルダ(`~/.claude/fable/agents/`)のエージェント
原本を修正したら、`~/.claude/agents/` へ再コピーしないと反映されない。

### この版のその他の調整点

- **ゲートが PowerShell ツールも監視。** ターミナルが Git Bash でも Claude Code
  自体は Windows アプリなので PowerShell ツールを使える。`Set-Content`、
  `Out-File`、`Add-Content`、`Tee-Object`、リダイレクトによるコードファイルの
  書き込みもブロックする。
- **ゲートのパス正規化。** `C:\proj\a.ts` と `C:/Proj/A.TS` を同じファイルとして
  認識し、再修正が二重に数えられない。ブロックメッセージの日本語が cp932/cp949 の
  コンソールで壊れないよう stderr を UTF-8 に固定した。
- **フックの登録は exec form。** フックの `command` に `args` を併せて渡すと、
  シェルを経由せず実行ファイルを直接スポーンする(公式 hooks リファレンスの
  exec form)。`"command": "python"` + `"args": [スクリプトのパス]` で登録すれば
  python.exe がスクリプトを直接実行するので、シェルの種類やシバンに依存しない。

## 公式ドキュメントで検証した事実

このセットアップが前提にしている動作は、すべて公式ドキュメントで確認した。

1. **PreToolUse フックは終了コード 2 でツール呼び出しをブロック**し、stderr が
   モデルに渡される。それ以外の 0 でない終了コードはブロックしないので、必ず 2 を
   使うこと。(hooks リファレンス)
2. **フックペイロードの `prompt_id`**: ユーザープロンプトごとに新しい UUID が
   与えられる。v2.1.196 以上が必要。この値が変わったら新しいターンと見なして
   カウンターをリセットする。
3. **サブエージェントの判別**: フックがサブエージェント内で発火すると、ペイロードに
   `agent_id` と `agent_type` が追加される。メインスレッドの呼び出しにはない。これで
   ゲートが委任経路を塞がないようにする。
4. **サブエージェントの frontmatter**: `model`(エイリアス sonnet/opus/haiku/fable
   または完全なモデル名)、`effort`(low/medium/high/xhigh/max)、`tools` フィールドが
   公式にサポートされている。
5. **エイリアスのリマップ**: `ANTHROPIC_DEFAULT_SONNET_MODEL` 環境変数が sonnet
   エイリアスの解決先を変える。OPUS/HAIKU/FABLE 用の変数もそれぞれ存在する。
6. **モデルエイリアスの現状**: v2.1.219 から `opus` エイリアスは Opus 5 として
   解決される(それ以前のバージョンは Opus 4.8)。エイリアスは各グレードの推奨
   バージョンへ自動更新される利点があるが、言い換えればクライアントのバージョンが
   上がると同じ定義が黙って別のモデルを指しうるということだ。そこでこのセットアップは
   frontmatter に完全なモデル ID を固定する(`claude-opus-5`、
   `claude-haiku-4-5-20251001`)。決定論的であり、Agent ツールの `model` パラメータが
   受け取るエイリアスが frontmatter を上書きして意図と違うティアに落ちる事故も防げる。
7. **シェルフォームのフックは Windows では Git Bash で実行される**が(インストール
   されている場合)、このセットアップはその経路の代わりに exec form を使って依存を
   なくす。

## ファイル構成

```
~/.claude/fable/                 (= C:\Users\ユーザー名\.claude\fable)
├── instructions.md          # オーケストレーション指示 (on のとき active.md にコピー)
├── blank.md                 # 空ファイル (off のとき active.md にコピー)
├── active.md                # 現在の状態のコピー (fable スクリプトが管理)
├── fable                    # トグルスクリプト (bash)
├── env.sh                   # シェルローダー (fable 関数の定義、モデルリマップなし)
├── agents/
│   ├── executor.md          # claude-opus-5 + effort: medium、一般実行専任
│   ├── deep-reasoner.md     # claude-opus-5 + effort: high、深い推論専任
│   └── runner.md            # claude-haiku-4-5 + effort: low、雑務専任 (読み取りツールのみ)
├── hooks/
│   └── orchestration-gate.py  # PreToolUse 強制ゲート
└── state/                   # ターン単位のカウンター (自動生成)
```

ローディングコードは 3 か所 + エージェントのコピー:

| 場所                         | 内容                                   |
| ---------------------------- | -------------------------------------- |
| `~/.claude/CLAUDE.md` の末尾 | `@` インポート 1 行                    |
| `~/.claude/agents/`          | エージェントファイルの **コピー** 3 個 |
| `~/.bashrc` の末尾           | `source .../env.sh` 1 行               |
| `~/.claude/settings.json`    | PreToolUse フックの登録ブロック        |

## ワンショットインストール

このフォルダの `install.sh` が以下の全工程(配置・CLAUDE.md・フック登録・
シェルローダー・有効化)を一度に実行する。再実行しても安全(設置済みの項目は
スキップ)。

```bash
bash install.sh    # Windows は Git Bash から、macOS はターミナルから
```

macOS では CLAUDE.md のインポートに POSIX パス、フックの command に python3 を
使い、シェルローダーを ~/.zshrc にも追加する。以下は手動で設置する場合の手順。

## インストール

全工程 Git Bash 基準。管理者権限は不要。まずバージョンを確認する。
v2.1.196 未満だとゲートのターン検出が動作しない。

```bash
claude --version
python --version    # Windows 用 Python 3 が必要 (ゲートの実行用)
```

Windows の `python` は Microsoft Store のインストール案内だけを出すスタブである
ことがあるので、`python --version` が実際のバージョン文字列を出力するか確認する。

**1) 本体の配置.** この文書と一緒に提供されたファイルがあるフォルダで実行する。

```bash
BASE=~/.claude/fable
mkdir -p "$BASE/agents" "$BASE/hooks" ~/.claude/agents
cp instructions.md blank.md fable env.sh "$BASE/"
cp agents/executor.md agents/deep-reasoner.md agents/runner.md "$BASE/agents/"
cp hooks/orchestration-gate.py "$BASE/hooks/"
```

Git Bash では `chmod +x` は不要だ。`fable` は env.sh の関数が `bash` で直接実行し、
ゲートは python が直接実行する。

**2) CLAUDE.md のインポート.** `~/.claude/CLAUDE.md` の末尾に以下を追加する。
Claude Code は CLAUDE.md 内の `@パス` 構文で別のファイルを併せてロードする。
注意: Claude Code は Windows アプリなので、Git Bash 形式のパス(`/c/Users/...`)では
なく **Windows のパス表記** で書く。ユーザー名は自分のものに。

```
<!-- fable-loader: トグルは fable on/off。この行は残す -->
@C:\Users\ユーザー名\.claude\fable\active.md
```

Git Bash でコマンドから一度に追加するには(パスを自動変換):

```bash
WINBASE=$(cygpath -w ~/.claude/fable/active.md)
printf '\n<!-- fable-loader: トグルは fable on/off。この行は残す -->\n@%s\n' "$WINBASE" >> ~/.claude/CLAUDE.md
```

**3) エージェントのコピー配置.** シンボリックリンクの代わりにコピーする。

```bash
cp "$BASE/agents/executor.md" "$BASE/agents/deep-reasoner.md" "$BASE/agents/runner.md" ~/.claude/agents/
```

本体フォルダのエージェント定義を後で修正したら、このコピーを再実行しないと
反映されない。

**4) ゲートフックの登録.** `~/.claude/settings.json` の `hooks` キーに追加する
(ファイルがなければこの内容のまま新規作成する)。JSON 内ではバックスラッシュを
2 つ書く。ユーザー名は自分のものに。settings.json が既にある場合は、既存のキー
(`model`、`permissions` など)を消さず `hooks` キーだけをマージする。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash|PowerShell",
        "hooks": [
          {
            "type": "command",
            "command": "python",
            "args": [
              "C:\\Users\\ユーザー名\\.claude\\fable\\hooks\\orchestration-gate.py"
            ]
          }
        ]
      }
    ]
  }
}
```

`args` を使う exec form なので、シェルを経由せず python.exe がスクリプトを直接
実行する。登録は一度だけ行う。以後のオン・オフはスクリプトがスイッチファイルを
読んで自分で処理する(off なら即 exit 0)。

**5) シェルローダー.** `~/.bashrc` の末尾に 1 行を追加する。これが `fable` コマンドを
定義する。env.sh は既定でそれだけをする — モデルのリマップはしない。
モデルは settings.json の `model`(メインセッション)と各エージェント frontmatter の
`model` ID(サブエージェント)で既に決定論的に固定されている。

```bash
printf '\n# fable シェルローダー\n[ -f "$HOME/.claude/fable/env.sh" ] && . "$HOME/.claude/fable/env.sh"\n' >> ~/.bashrc
source ~/.bashrc
```

**(オプション) sonnet のリマップ.** 外部プラグインなどで frontmatter に
`model: sonnet` と固定されたエージェントまで上位モデルに上げたいときだけ、
env.sh の末尾に以下を付け足す。スイッチが on のときだけ効力が生じる。

```bash
FABLE_SONNET_REMAP="${FABLE_SONNET_REMAP:-claude-opus-5}"

claude() {
  if _fable_switch_on; then
    ANTHROPIC_DEFAULT_SONNET_MODEL="$FABLE_SONNET_REMAP" command claude "$@"
  else
    command claude "$@"
  fi
}
```

このラッパーはエイリアスの解決をハイジャックするので、自分のエージェントのモデルを
ID で固定するこのセットアップの原則とは方向が違う。必要な場合にだけ使う。

注意: すべてのサブエージェントを一つのモデルに強制する
`CLAUDE_CODE_SUBAGENT_MODEL` は使わない。この変数は frontmatter より優先度が高く、
runner の haiku 指定まで上書きして役割分離が壊れる。

**6) 有効化.**

```bash
fable on
fable status
```

status の点検項目がすべて `[OK]` ならインストール完了だ。

## 検証

ゲートは作っておくことより、実際にブロックされるかを証明するほうが重要だ。空の作業
フォルダでヘッドレスに確認する。

```bash
# メインエージェント: 3 番目のコードファイルでブロックされるはず
claude -p "t1.ts, t2.ts, t3.ts を順番に作成しろ。ブロックされたら BLOCKED と出力して止まれ。"
ls *.ts    # t1.ts t2.ts だけが存在すれば正常

# サブエージェント: 制限なくすべて作成されるはず
claude -p "サブエージェントを一つ立てて u1.ts, u2.ts, u3.ts を作成させろ。"
ls u*.ts   # u1.ts u2.ts u3.ts がすべて存在すれば正常
```

この二つの結果が揃って確認されて初めて完成だ。前者だけ成功したなら委任経路が
塞がれており、後者だけ成功したならゲートが効いていない。

ゲートスクリプト自体の単体動作(スイッチ off で通過、上限でブロック、同じファイルの
再修正を許可 — パスの大文字小文字・区切り文字の正規化を含む、ターンのリセット、
サブエージェント通過、ドキュメントファイル通過、Bash の sed -i・リダイレクトを
ブロック、PowerShell の Set-Content/Out-File をブロック、読み取り専用コマンド通過、
非コードのリダイレクト通過、壊れた入力の fail-open)は、この文書と一緒に配布された
スクリプトを対象に 13 ケースで事前検証されている。

## 日常の使い方

| コマンド       | 動作                                                                 |
| -------------- | -------------------------------------------------------------------- |
| `fable on`     | 指示のロード + ゲート有効。**次のセッションから**                    |
| `fable off`    | すべて無効。ローディングコードはそのまま、コピーと状態だけを切り替え |
| `fable status` | 状態とローディングコード + python の存在まで点検                     |

CLAUDE.md とフックの設定はセッション開始時点でロードされるので、トグルは既に
起動しているセッションには適用されない。ゲートスクリプトだけがツール呼び出しごとに
スイッチを読む。

指揮者モデル自体はこのセットアップでは触らない。セッション内で `/model` から最上位
モデルを既定値として保存しておけば、その上にこの層が乗る。

## ゲートのルールと限界

ルール: メインエージェントは 1 ターンにコードファイル 2 個まで直接修正でき、
3 個目でブロック。同じファイルの再修正と、ドキュメント・設定ファイル
(md, json, yaml など)は数えない。Bash/PowerShell 経由のコードファイル書き込み
(sed/perl -i, Set-Content, Out-File, Add-Content, Tee-Object, リダイレクト)は
個数に関係なく常にブロック。サブエージェントはすべて通過。

知っておくべき限界:

- **暴走防止装置であって完全な遮断壁ではない。** シェル回避の検出は代表的な経路
  だけを塞ぐ。だから指示にも同じルールを書き、推奨と強制を二重にしている。
- **エラー時は fail-open。** ゲートのバグがすべてのツール呼び出しを塞いでセッションを
  麻痺させるより、そのターンの制限を取りこぼすほうを選んだ。
- **正当な作業がブロックされたら**: ブロックメッセージを受けたモデルが委任すれば
  そのまま進む。人が直接進めたい場合は `fable off` してから作業し、また有効化する。
- **シェルラッパーを経由しない経路**(IDE 拡張、PowerShell からの直接実行)でも
  指示・エージェント・ゲートは正常に動作する。オプション項目である sonnet の
  リマップだけがこの経路では適用されない。
- **他のプラグインのフックと衝突しない。** 登録された PreToolUse フックはすべて
  実行され、一つでもブロックすれば止まる構造なので並んで動作する。
- **エージェント原本の修正時は再コピーが必要。** コピー方式の唯一の維持コストだ。
  `cp ~/.claude/fable/agents/*.md ~/.claude/agents/` の 1 行で済む。

## 完全な削除

ローディングコード(CLAUDE.md のインポート 1 行、`.bashrc` の source 1 行、
settings.json の hooks ブロック)とエージェントのコピー 3 個を消し、
`~/.claude/fable/` フォルダと `~/.claude/.fable-state` ファイルを削除すれば
跡形なく消える。

## 参考: SDK での同じ原理 — advisor 戦略

Claude Code の外で API/SDK からエージェントを自分で書くときは、方向を逆にした公式
機能がある。安い実行者モデルが作業を主導し、難しい判断に突き当たったときだけ
advisor ツールで上位モデルに相談する構造だ(`advisor` ツールタイプ、`max_uses` で
相談回数を制限)。判断は高いモデル、実行は安いモデルという原理は同じで、
Claude Code 内でマルチステップの作業をまるごと任せるならこの文書の指揮 - 委任が、
SDK で大半を安く回して時々だけ最上位の判断を借りるなら advisor が合っている。
詳しくは Anthropic 公式ドキュメントの advisor 項目を参照。
