# ywr 使い方ガイド

[English](usage.md) | 日本語

`ywr`（yabai-workspaces）は、macOS のウィンドウ配置を名前を付けて保存し、同じ
ディスプレイ構成が接続されたときに復元する CLI です。以下、導入から日常運用まで
順を追って説明します。

---

## 1. 前提: yabai の導入

`ywr` は [yabai](https://github.com/koekeishiya/yabai) を呼び出して動作します。
先に yabai をインストール・起動してください。

```sh
brew install koekeishiya/formulae/yabai
yabai --start-service
```

必要な権限・設定:

- **yabai のアクセシビリティ権限** — ウィンドウの移動・リサイズに必要です
  （**位置のみ復元でも必須**）。
- **Space / ディスプレイをまたぐ**フル復元をしたい場合は、追加で次が必要:
  - システム設定 ▸ デスクトップとDock ▸ 「ディスプレイごとに個別の操作スペース」を ON
  - yabai の **scripting-addition** をロード
- これらの追加設定が無い環境では、ywr は自動的に**位置のみ復元**へ縮退します
  （`ywr doctor` が状況を表示）。なお単一ディスプレイでも複数 Space 間の移動は可能で、
  単一ディスプレイでは「ディスプレイをまたぐ移動」だけが対象外になります。

---

## 2. ywr のインストール

リポジトリでリリースビルドし、PATH の通ったディレクトリへ配置します。

```sh
cd yabai-workspaces
swift build -c release
cp .build/release/ywr ~/.local/bin/ywr    # ~/.local/bin が PATH にある前提
```

確認:

```sh
ywr doctor
```

`doctor` は yabai の導入・疎通・必要な macOS 設定をチェックします。すべて ✓ に
なれば準備完了です。✗ が出たらメッセージに従って解消してください。

---

## 3. 基本の流れ: 保存 → 復元

いちばん使う操作はこの 2 つです。

```sh
# 今のウィンドウ配置を "home" という名前で保存
ywr snapshot save home

# （ウィンドウを動かしたあと）"home" の配置に戻す
ywr restore home
```

**まず `--dry-run` で確認**するのがおすすめです。実際には何も動かさず、何が
起きるかだけを表示します。

```sh
ywr restore home --dry-run
```

保存済みの一覧:

```sh
ywr snapshot list
# NAME  PROFILE              WINDOWS  SPACES  CAPTURED
# home  1728x1117+3840x2160  12       3       2026-07-11T...
```

---

## 4. 自動で戻す

構成が変わったとき（外部ディスプレイの抜き差しなど）に自動で復元する方法が
2 つあります。どちらか好みで選べます。

### 4-1. その場で自動選択

現在のディスプレイ構成に最も近いスナップショットを自動で選んで復元します。

```sh
ywr restore --auto
ywr restore --auto --dry-run   # 何が選ばれるか確認だけ
```

一致度が高ければ即復元、あいまいなら候補を提示します。

### 4-2. デーモン（ポーリング）

ディスプレイ変更を一定間隔で監視し、変化したら `restore --auto` を実行します。

```sh
ywr daemon                 # 既定 2 秒間隔
ywr daemon --interval 5    # 5 秒間隔
```

フォアグラウンドで動き続けます。停止は Ctrl-C。

### 4-3. yabai シグナル（イベント駆動、デーモン不要）

yabai 自身にディスプレイイベントを監視させ、変化時に `ywr restore --auto` を
実行させます。常駐プロセスが不要です。

```sh
ywr signal install     # display_added / display_removed / display_moved を登録
ywr signal list        # 登録するシグナルを表示
ywr signal uninstall   # 登録を解除
```

> デーモンとシグナルは同じ「自動復元」を実現する別方式です。両方同時に使う必要は
> ありません。

---

## 5. ディスプレイプロファイル

ディスプレイ構成そのものを記録・確認できます（fingerprint 付き）。

```sh
ywr profile capture home   # 現在の構成を "home" として記録
ywr profile list
```

---

## 6. 復元でできること

`restore` は以下を復元します:

- ウィンドウを保存時の **Display / Space** へ移動
- **相対座標**で位置・サイズを復元（解像度が変わっても破綻しにくい）
- **floating / minimized / fullscreen** 状態
- 保存時に**アクティブだったウィンドウへフォーカス**を戻す
- 起動していないアプリは `open -a` で**起動**して数秒待つ
- 復元できなかったウィンドウは**最後に一覧表示**（失敗を握りつぶさない）

### 位置のみ復元 / 自動フォールバック

Space やディスプレイをまたぐ移動が使えない・不要な環境（「個別の操作スペース」OFF、
scripting-addition 無し、単一ディスプレイでのディスプレイ跨ぎ復元など）でも、
**現在の Space 内でウィンドウの位置・サイズだけを復元**できます。

- **既定は自動フォールバック**：まずフル復元を試み、Space/Display 移動が失敗した
  ウィンドウは自動で位置のみ復元へ縮退します（失敗扱いにはなりません）。復元後に
  「N positions-only」と表示されます。
- **明示指定**：最初から Space/Display 移動をスキップしたい場合は `--positions-only`。

```sh
ywr restore home                  # 自動フォールバック（既定）
ywr restore home --positions-only # 位置・サイズのみ復元（Space/Display 移動なし）
```

### 不足している Space を作る

保存時にラベル付き Space があり、現在それが無い場合、`--create-spaces` を付けると
不足分の Space を作成してからウィンドウを移動します。`--positions-only` とは併用
できません（同時指定するとエラーになります）。

```sh
ywr restore home --create-spaces
ywr restore home --create-spaces --dry-run   # 作成予定の Space も表示
```

---

## 7. メニューバーアプリ

CLI と同じ操作（保存・自動復元）を GUI から行えるメニューバーアプリ
（`ywr-menubar`）もあります。

```sh
swift run ywr-menubar
```

### 配色・フォントの変更

メニューバーアプリの配色とフォントは**コードを触らず外部ファイルで**変更できます。
`~/.config/yabai-workspaces/theme.json` を置いてください（無ければ組み込みの
ダーク既定を使用）。

```json
{
  "colors": {
    "accent": "#4C8DFF", "background": "#1E1E1E", "surface": "#2A2A2A",
    "textPrimary": "#FFFFFF", "textSecondary": "#A0A0A0",
    "success": "#3FB950", "warning": "#D29922", "error": "#F85149"
  },
  "font": { "family": "System", "regularSize": 13, "titleSize": 15, "monospacedDigits": true }
}
```

- `colors` は `#RRGGBB` または `#RRGGBBAA` の16進。
- `font.family` は `"System"` でシステムフォント、他はフォント名を指定。

---

## 8. 保存場所

すべて `$XDG_CONFIG_HOME/yabai-workspaces`（既定は `~/.config/yabai-workspaces`）
配下に JSON で保存されます。

```
~/.config/yabai-workspaces/
  snapshots/<name>.json    # スナップショット
  profiles/<name>.json     # ディスプレイプロファイル
  theme.json               # （任意）メニューバーの配色・フォント
```

---

## 9. コマンド早見表

| コマンド | 説明 |
|---|---|
| `ywr doctor` | yabai と環境をチェック |
| `ywr snapshot save <name>` | 現在の配置を保存 |
| `ywr snapshot list` | 保存済み一覧 |
| `ywr restore <name>` | 復元 |
| `ywr restore <name> --dry-run` | 復元内容をプレビュー |
| `ywr restore --auto` | 現構成に一致する snapshot を自動選択して復元 |
| `ywr restore <name> --create-spaces` | 不足 Space を作成してから復元 |
| `ywr restore <name> --positions-only` | Space/Display 移動なし、位置・サイズのみ復元 |
| `ywr profile capture <name>` | ディスプレイ構成を記録 |
| `ywr profile list` | プロファイル一覧 |
| `ywr daemon [--interval <秒>]` | ポーリングで自動復元 |
| `ywr signal` <install\|uninstall\|list> | yabai シグナルで自動復元 |

---

## 10. うまくいかないとき

- **`command not found: ywr`** → バイナリが PATH に無い。`swift build -c release`
  後に `cp .build/release/ywr ~/.local/bin/ywr`。
- **`doctor` が ✗** → yabai 未導入 or 未起動。`brew install ... yabai` /
  `yabai --start-service`。
- **Space をまたぐ移動が効かない** → scripting-addition が未ロード、または
  「ディスプレイごとに個別の操作スペース」が OFF。この場合でも位置のみ復元は動作し、
  ywr は自動でそちらへ縮退します（`--positions-only` で明示指定も可）。
- **一部ウィンドウが戻らない** → `restore` 実行後の末尾に失敗一覧が出ます。
  アプリ未起動・タイトル不一致などが原因。`--dry-run` で対応付けを確認できます。
