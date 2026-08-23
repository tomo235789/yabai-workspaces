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

**無料版と Pro。** 無料版はスナップショットを **3件まで**保持できます（既存名の
上書きは常に可能）。**Pro** ライセンスで上限が解除されます（今後の Pro 機能も解錠）。
ライセンスは**オフライン検証**で、`~/.config/yabai-workspaces/license.json` に置くだけ。
ネットワーク通信は一切しません。

---

## 4. ディスプレイプロファイル

ディスプレイ構成そのものを記録・確認できます（fingerprint 付き）。

```sh
ywr profile capture home   # 現在の構成を "home" として記録
ywr profile list
```

---

## 5. 復元でできること

`restore` は以下を復元します:

- ウィンドウを保存時の **Display / Space** へ移動
- **相対座標**で位置・サイズを復元（解像度が変わっても破綻しにくい）
- **floating / minimized / fullscreen** 状態
- 保存時に**アクティブだったウィンドウへフォーカス**を戻す
- 起動していないアプリは `open -a` で**起動**して数秒待つ
- 復元できなかったウィンドウは**最後に一覧表示**（失敗を握りつぶさない）

### 位置のみ復元 / 自動フォールバック

「ディスプレイごとに個別の操作スペース」がOFFの場合、スナップショットに
`unifiedDesktop` として記録されます。復元時は各仮想デスクトップを順に表示して
ウィンドウを収集し、元のデスクトップへ戻ってから復元します。この収集中は画面が
切り替わることがあります。scripting-additionが無い場合など、Space移動自体が
利用できない環境では、**現在のSpace内で位置・サイズだけを復元**します。

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

### ネイティブバックエンド（yabai なしで動かす）

yabai は「ディスプレイごとに個別の操作スペース」が **OFF** だと起動しません。その
ような構成でも、ywr は **yabai を使わない native バックエンド**（macOS の
Accessibility / CoreGraphics）で**ウィンドウの位置・サイズ**を保存・復元できます。

- **自動切替**：`ywr doctor` が yabai 未応答を検出すると、`snapshot save` / `restore`
  は自動的に native バックエンドを使います（`active backend` 行で状態表示）。
- **明示指定**：`--native` を付けると常に native を使います。

```sh
ywr snapshot save home --native   # yabai を使わず現在の配置を保存
ywr restore home --native         # 位置・サイズを復元（ディスプレイ跨ぎも対応）
```

native バックエンドでできること・制約:

- ✅ ウィンドウの**位置・サイズ**を復元（**別ディスプレイへの移動**も含む）
- ✅ 保存時に**最前面**だったウィンドウを前面に戻す
- ✅ 通常の GUI アプリのみ対象（システム/ヘルパーは自動除外）、Electron/Chromium も対応
- ❌ **Space（仮想デスクトップ）への割り当ては不可**（公開 API の制約による geometry-only）
- ❌ `--create-spaces` は yabai 専用（native では使えません）
- ⚠️ **Accessibility 権限**が必須。加えて**画面収録**権限を付与すると、アプリ再起動を
  またぐ際の同名ウィンドウの識別精度が上がります。

**全デスクトップに復元（実験的）。** 公開 API ではウィンドウを別 Space へ*移動*できま
せんが、そのデスクトップがアクティブなら位置は直せます。そこで `--walk-spaces` は各
デスクトップを順に切り替え、そこにあるウィンドウを配置していき、一度に複数デスクトップ
のレイアウトを再現します（終了後は元のデスクトップに戻ります）:

```sh
ywr restore home --native --walk-spaces
```

- 画面が**各デスクトップを順に切り替わり**、数秒かかります。
- ウィンドウは**デスクトップ間を移動しません** — 今いるデスクトップ上で位置だけ直します。
- **「Mission Control ▸ 操作スペースを左右に移動」のショートカット**（macOS 既定で有効）
  と Accessibility 権限が必要です。
- 想定は**spanning 構成**（「ディスプレイごとに個別の操作スペース」OFF）で、1つの Space
  セットが全ディスプレイにまたがるケースです。個別スペースが ON だと Ctrl+矢印は焦点の
  あるディスプレイの Space しか動かさないため、その構成では **yabai バックエンド**を使って
  ください。
- メニューバーアプリでは各スナップショット横の **▦ ボタン**がこれ。native モードでは名前を
  普通にクリックすると**現在の**デスクトップだけ復元し、yabai バックエンドでは名前クリックで
  各ウィンドウを保存時の Space/ディスプレイへ直接復元します。

---

## 6. メニューバーアプリ

CLI と同じ操作（保存・復元）を GUI から行えるメニューバーアプリ
（`ywr-menubar`）もあります。

```sh
swift run ywr-menubar
```

**メニューバーにアイコンが出ない場合**は、`.app` バンドルとして起動してください。
macOS はバンドル化された常駐（LSUIElement）アプリのメニューバー項目を確実に表示します。

`build/YabaiWorkspaces.app` を生成して開きます（メニューバーに ▤ アイコンが出ます）:

```sh
bash scripts/make-menubar-app.sh && open build/YabaiWorkspaces.app
```

初回起動時にアプリが **アクセシビリティ**（ウィンドウ移動に必須）と **画面収録**
（任意・タイトル取得でマッチ精度向上）の権限を要求し、システム設定 ▸ プライバシーと
セキュリティ に自動登録されます。そこで「yabai workspaces」の **アクセシビリティ**を
ON にしてください。

**再ビルドで許可を失わないようにする。** 既定では ad-hoc 署名のため、再ビルドのたびに
別アプリ扱いになり、アクセシビリティの再追加が必要です。**一度だけ**安定した自己署名
証明書を作れば、以後は再ビルドしても許可が維持されます（署名の designated requirement が
変化するバイナリのハッシュではなく証明書に紐づくため）:

```sh
bash scripts/create-signing-cert.sh   # 一度だけ。sudo もプロンプトも不要
bash scripts/make-menubar-app.sh      # 以後はこの証明書で署名される
```

安定署名での初回ビルド後だけ、署名が変わったのでアクセシビリティをもう一度付与して
ください。その後は再ビルドしても許可が残ります。

### ログイン時に自動起動する

アプリを `~/Applications` にインストールし、ログイン時に開くユーザ LaunchAgent を
登録します（Automation 権限のプロンプトは出ません）:

```sh
bash scripts/autostart-install.sh     # インストール＋今すぐ起動＋ログイン時起動
bash scripts/autostart-uninstall.sh   # 自動起動を無効化
```

`~/Applications` のコピーは署名が保たれるため、アクセシビリティ許可はそのまま引き継が
れます（再付与不要）。後でリビルドして反映したい場合は `scripts/autostart-install.sh`
を再実行してください。

### 署名済みビルドの配布（他の Mac へ渡す）

自己署名バンドルは自分の Mac でしか動きません。Gatekeeper の警告なしに他人へ配るには、
Apple の **Developer ID 証明書**＋**notarization** が必要です。Apple Developer Program
に登録し notarytool 認証情報を保存したうえで、署名→公証→staple を実行します:

```sh
export YWR_DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
export YWR_NOTARY_PROFILE="ywr-notary"   # xcrun notarytool store-credentials で作成
bash scripts/release.sh                  # → 公証済み build/YabaiWorkspaces.zip
```

補足: **Mac App Store は不可**（非公開/アクセシビリティ API を使うため）。直接ダウンロード
または Homebrew Cask で配布してください。

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

## 7. 保存場所

すべて `$XDG_CONFIG_HOME/yabai-workspaces`（既定は `~/.config/yabai-workspaces`）
配下に JSON で保存されます。

```
~/.config/yabai-workspaces/
  snapshots/<name>.json    # スナップショット
  profiles/<name>.json     # ディスプレイプロファイル
  theme.json               # （任意）メニューバーの配色・フォント
```

---

## 8. コマンド早見表

| コマンド | 説明 |
|---|---|
| `ywr doctor` | yabai と環境をチェック |
| `ywr snapshot save <name>` | 現在の配置を保存 |
| `ywr snapshot list` | 保存済み一覧 |
| `ywr snapshot delete <name>` | 保存済みスナップショットを削除 |
| `ywr restore <name>` | 復元 |
| `ywr restore <name> --dry-run` | 復元内容をプレビュー |
| `ywr restore <name> --create-spaces` | 不足 Space を作成してから復元 |
| `ywr restore <name> --positions-only` | Space/Display 移動なし、位置・サイズのみ復元 |
| `ywr restore <name> --native --walk-spaces` | 全デスクトップに復元（Space を巡回） |
| `ywr snapshot save <name> --native` / `ywr restore <name> --native` | yabai を使わず位置・サイズを保存/復元 |
| `ywr profile capture <name>` | ディスプレイ構成を記録 |
| `ywr profile list` | プロファイル一覧 |

---

## 9. うまくいかないとき

- **`command not found: ywr`** → バイナリが PATH に無い。`swift build -c release`
  後に `cp .build/release/ywr ~/.local/bin/ywr`。
- **`doctor` が ✗** → yabai 未導入 or 未起動。`brew install ... yabai` /
  `yabai --start-service`。
- **Space をまたぐ移動が効かない** → scripting-additionが未ロードの可能性があります。
  個別の操作スペースがOFFの構成自体には対応していますが、Space移動に失敗した
  ウィンドウは位置のみ復元へ縮退します（`--positions-only`で明示指定も可）。
- **一部ウィンドウが戻らない** → `restore` 実行後の末尾に失敗一覧が出ます。
  アプリ未起動・タイトル不一致などが原因。`--dry-run` で対応付けを確認できます。
