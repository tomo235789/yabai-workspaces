実装プラン
yabai 本体をforkせず、まずは yabai companion CLI として作るのがよいです。名前は仮に yabai-workspaces / ywr。
目的
外部ディスプレイ構成、Spaces、表示中ウィンドウ配置をスナップショットとして保存し、同じ構成が接続されたときに復元する。
構成
ywr CLI
  - profile: ディスプレイ構成の検出・保存
  - snapshot: Spaces / windows の保存
  - restore: 復元
  - daemon: display変更検知・自動復元

yabai
  - displays / spaces / windows query
  - window移動・リサイズ
  - Space作成・ラベル付け
  - windowをSpace/Displayへ移動
MVP機能
ywr doctor
yabai がインストール済みか確認
yabai -m query --displays が動くか確認
jq など外部依存がある場合は確認
必要なmacOS設定の注意を表示

ywr profile capture <name>
yabai -m query --displays を保存
display id / uuid / index / frame / spaces / focused 状態を記録
fingerprint を生成
例: ~/.config/yabai-workspaces/profiles/home.json

ywr snapshot save <name>
query --displays
query --spaces
query --windows
表示中または全取得可能ウィンドウを保存
window の app, title, id, pid, space, display, frame, is-floating, is-sticky, is-minimized などを保存
frame は絶対座標に加えて display 内の相対座標も保存

ywr snapshot list
保存済みスナップショット一覧
紐づく display profile
作成日時
window数 / space数を表示

ywr restore <snapshot>
現在の display profile を検出
保存時の display と現在の display をマッチング
Space label を復元
対象アプリが起動していなければ起動、またはスキップ
window を Space / Display に移動
float 化が必要なら yabai -m window --toggle float
相対座標から現在の display frame に変換して move / resize
失敗したwindowを最後に一覧表示

ywr restore --auto
現在のディスプレイ構成に最も近い snapshot を選ぶ
一致度が高ければ復元
曖昧なら候補を表示して選択

データ構造
{
  "version": 1,
  "name": "home",
  "capturedAt": "2026-07-11T10:00:00+09:00",
  "displayProfile": {
    "fingerprint": "builtin+lg-4k-left",
    "displays": []
  },
  "spaces": [],
  "windows": [
    {
      "app": "Visual Studio Code",
      "title": "project",
      "pid": 12345,
      "space": 2,
      "display": 1,
      "frame": { "x": 0, "y": 0, "w": 1200, "h": 900 },
      "relativeFrame": { "x": 0.04, "y": 0.06, "w": 0.5, "h": 0.82 },
      "flags": {
        "floating": true,
        "sticky": false,
        "minimized": false,
        "fullscreen": false
      }
    }
  ]
}
復元アルゴリズム
現在の displays / spaces / windows を取得
保存時 display と現在 display をスコアで対応付け
Space label があれば label で対応、なければ index で対応
app + title + role + size で window を対応付け
見つからない app は open -a で起動
window 出現を数秒リトライ
display / space へ移動
floating 状態を整える
relativeFrame から現在座標を計算
move / resize
focus を保存時に近い状態へ戻す
ディスプレイマッチング
serial / uuid 一致        +50
name 一致                 +15
resolution 一致           +15
frame size 一致            +10
spaces数が近い             +5
相対配置が近い             +10
70点以上なら同一ディスプレイ扱い。満たない場合は候補として表示。
実装言語
最初は Go か Swift CLI がよいです。
おすすめは Go。
JSON処理が楽
single binary配布しやすい
yabai CLIを呼ぶだけなら十分
後でSwiftUIメニューバーアプリから呼びやすい
Swiftにする理由があるとしたら、将来メニューバーアプリ化やmacOS通知、LaunchAgent統合を自然にやりたい場合。
ディレクトリ構成
yabai-workspaces/
  cmd/ywr/
    main.go
  internal/yabai/
    client.go
    types.go
  internal/profile/
    fingerprint.go
    matcher.go
  internal/snapshot/
    capture.go
    restore.go
    store.go
  internal/app/
    launcher.go
  internal/config/
    paths.go
  README.md
  LICENSE
最初に作る順番
ywr doctor
ywr snapshot save <name>
保存JSONの確認
ywr snapshot list
ywr restore <name> の dry-run
window move / resize の実復元
Space label / Space移動
アプリ起動待ち
display profile 自動判定
restore --auto
yabai signal 連携
メニューバーアプリ化
READMEに書くこと
## Requirements

This tool requires yabai to be installed and configured separately.

## License

This project is licensed under the MIT License.

yabai is a separate project licensed under the MIT License.
This project does not include yabai binaries or source code.
避けること
最初から yabai をforkしない
最初からGUIを作らない
最初から全アプリ完全復元を狙わない
Spaceの完全再現を最初のMVP条件にしない
絶対座標だけで保存しない
最初のゴールは、「今のMac環境で save → ぐちゃっと動かす → restore で戻る」 です。そこまで行けば、このアイデアはかなり現実味が出ます。