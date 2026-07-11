# Product Requirements Document: ywr (yabai-workspaces)

**Author**: inagaki.tomonari@gmail.com
**Date**: 2026-07-11
**Status**: Draft
**Stakeholders**: 開発者本人（1名 / 個人プロジェクト）。将来OSS公開時はコントリビューター・利用者。

---

## 1. Executive Summary

`ywr` は yabai を前提とした macOS 向けコンパニオン CLI で、外部ディスプレイ構成・Spaces・表示中ウィンドウ配置を**スナップショットとして保存し、同じディスプレイ構成が接続されたときに復元する**ツールです。まずは自分の Mac 環境で「save → ぐちゃっと動かす → restore で戻る」を成立させ、動作が固まった段階で MIT ライセンスの OSS として公開します。yabai 本体は fork せず、`yabai -m` を呼ぶだけの薄いラッパーとして独立配布します。

---

## 2. Background & Context

macOS のマルチディスプレイ環境では、ケーブルの抜き差しやディスプレイ構成の変化のたびにウィンドウ配置と Spaces が崩れ、手作業での再配置コストが日常的に発生する。yabai はタイリング WM としてウィンドウ操作 API（`query`, `window --move/--resize`, Space 移動）を提供するが、**「今のレイアウトを名前を付けて保存し、後で復元する」という永続化・プロファイル機能は持たない**。

この gap を埋めるのが `ywr` の狙い。yabai を fork するのではなく、`yabai -m query` で状態を吸い出して JSON に永続化し、`yabai -m window` で復元する外部 CLI として実装する。これにより yabai のアップデートに追従しやすく、ライセンス的にもクリーン（yabai バイナリ/ソースを同梱しない）に保てる。

**実装言語の判断**: プラン初稿では JSON 処理と single binary 配布の容易さから Go を推奨していたが、**Swift を採用**する。将来のメニューバーアプリ化・macOS 通知・LaunchAgent 統合を自然に行いたいという方向性を優先したため。CLI としては `yabai -m` をサブプロセス呼び出しし、`Codable` で JSON を扱う。

**プラン原文にある「避けること」を制約として継承**: yabai を fork しない / 最初から GUI を作らない / 全アプリ完全復元を狙わない / Space の完全再現を MVP 条件にしない / 絶対座標だけで保存しない。

---

## 3. Objectives & Success Metrics

### Goals（成功の定義）
1. **自分の主要ディスプレイ構成（例: builtin + 外部4K）で、`ywr snapshot save` → 手動でウィンドウを崩す → `ywr restore` で元配置に戻せる。**
2. スナップショットはディスプレイ構成の fingerprint と紐づき、`restore --auto` で現在の構成に最も近いものを自動選択できる。
3. 復元は相対座標ベースで行い、ディスプレイ解像度・位置が変わっても破綻しない。
4. 復元失敗（アプリ未起動・ウィンドウ未検出）を握りつぶさず、末尾に一覧表示してユーザーが手当てできる。
5. （フェーズ2）OSS 公開に耐える README・LICENSE・`ywr doctor` による前提チェックを備える。

### Non-Goals（明確にスコープ外）
1. **GUI / メニューバーアプリ** — MVP は CLI のみ。GUI は将来フェーズ（Swift 採用の理由ではあるが v1 では作らない）。
2. **yabai の fork・改造・同梱** — あくまで外部から `yabai -m` を呼ぶ。
3. **Space の完全再現**（Space の枚数・順序を厳密に復元すること） — MVP は label ベースの対応と既存 Space への移動まで。
4. **全アプリの完全自動復元** — 起動できないアプリ・ドキュメント状態の復元は対象外。未対応はスキップして報告。
5. **絶対座標のみでの保存** — 必ず相対座標を併記する。
6. **macOS SIP 無効化や yabai scripting-addition のセットアップ代行** — `doctor` で注意喚起はするが自動化しない。

### Success Metrics
| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| 主要構成での restore 成功（対象ウィンドウ中、正しい Display/Space/概略位置に戻った割合） | 0%（未実装） | ≥ 90% | 手動テスト: 10ウィンドウ規模のレイアウトで save→崩す→restore を5回試行し平均 |
| restore 実行時間（10ウィンドウ規模） | N/A | ≤ 10秒 | CLI 実行の wall-clock |
| ディスプレイ自動判定の正答率（`restore --auto`） | N/A | 正しい snapshot を選択 100%（保存済み2構成間） | home / office 2構成を切り替えて判定 |
| 復元失敗が silent に握りつぶされる件数 | N/A | 0（全失敗を末尾レポート） | 意図的にアプリ未起動状態で restore し、レポート有無を確認 |
| `ywr doctor` が前提未充足を正しく検出 | N/A | 100% | yabai 未インストール等を擬似再現して確認 |

---

## 4. Target Users & Segments

**プライマリ（フェーズ1）**: 開発者本人。yabai を既に導入済みで、複数ディスプレイを日常的に抜き差しする macOS パワーユーザー。現在の workaround は「毎回手動でウィンドウを並べ直す」。

**セカンダリ（フェーズ2 / OSS 公開後）**: 同じく yabai を使い、ディスプレイ構成の切り替え（自宅↔オフィス、ドッキング）が頻繁な開発者。CLI とドットファイル運用に抵抗がなく、tiling WM を好む層。市場規模は小さいがニッチで熱量が高い（yabai の GitHub star 数からも一定の潜在ユーザーが見込める）。

---

## 5. User Stories & Requirements

### P0 — Must Have（MVP: 「save → 崩す → restore で戻る」まで）

| # | User Story | Acceptance Criteria |
|---|-----------|-------------------|
| P0-1 | 開発者として、環境の前提が整っているか確認したい | `ywr doctor` が yabai インストール有無・`yabai -m query --displays` の疎通・必要な macOS 設定の注意を表示し、未充足時は非0 exit する |
| P0-2 | 開発者として、現在のレイアウトを名前付きで保存したい | `ywr snapshot save <name>` が displays/spaces/windows を query し、各 window の app/title/id/pid/space/display/frame/flags と **絶対 frame + display 内相対 frame** を JSON 保存する（`~/.config/yabai-workspaces/snapshots/<name>.json`） |
| P0-3 | 開発者として、保存済みスナップショットを一覧したい | `ywr snapshot list` が snapshot 名・紐づく display profile(fingerprint)・作成日時・window数/space数を表形式表示 |
| P0-4 | 開発者として、復元前に何が起きるか確認したい | `ywr restore <name> --dry-run` が「どの window をどの Display/Space に、どの座標へ移動するか」を実行せず一覧表示する |
| P0-5 | 開発者として、保存したレイアウトに戻したい | `ywr restore <name>` が現在の displays を保存時とマッチングし、window を Display/Space へ移動、相対座標から現在解像度の座標を算出して move/resize する |
| P0-6 | 開発者として、復元で失敗した項目を把握したい | 復元できなかった window（アプリ未起動・未検出・移動失敗）を末尾にまとめて一覧表示する（silent failure なし） |

### P1 — Should Have

| # | User Story | Acceptance Criteria |
|---|-----------|-------------------|
| P1-1 | 開発者として、ディスプレイ構成をプロファイルとして扱いたい | `ywr profile capture <name>` が displays の id/uuid/index/frame/spaces/focused を記録し fingerprint を生成・保存する |
| P1-2 | 開発者として、Space の意味を保ったまま復元したい | 復元時、Space label があれば label で対応、なければ index で対応。必要なら Space label を復元する |
| P1-3 | 開発者として、対象アプリが落ちていても復元したい | 未起動アプリを `open -a` で起動し、window 出現を数秒リトライ。起動不能ならスキップして報告 |
| P1-4 | 開発者として、floating 状態も含め正しく復元したい | 保存した floating フラグに合わせて `yabai -m window --toggle float` を適用してから move/resize |
| P1-5 | 開発者として、構成を挿すだけで自動復元したい | `ywr restore --auto` が現在構成に最も近い snapshot をスコアで選定。高一致なら復元、曖昧なら候補を提示して選択させる |

### P2 — Nice to Have / Future

| # | User Story | Acceptance Criteria |
|---|-----------|-------------------|
| P2-1 | 開発者として、ディスプレイ変更を検知して自動復元したい | `ywr daemon` が display 変更（yabai signal 連携）を検知し `restore --auto` を発火 |
| P2-2 | 開発者として、GUI から操作したい | SwiftUI メニューバーアプリから save/restore を呼べる（v1 スコープ外） |
| P2-3 | 利用者として、OSS として導入したい | README（Requirements/License）・LICENSE(MIT)・yabai を同梱しない旨の明記を整備し公開 |

---

## 6. Solution Overview

**アーキテクチャ**: `ywr` CLI（Swift）が `yabai -m` をサブプロセス呼び出しして JSON を取得/操作。永続化は `~/.config/yabai-workspaces/` 配下の JSON。

**モジュール構成（プランのディレクトリ構成を Swift 向けに読み替え）**:
- `YabaiClient` — `yabai -m query --displays/--spaces/--windows`、`window --move/--resize/--space/--display/--toggle` のラッパー（`internal/yabai/client.go` 相当）
- `Snapshot`（capture / restore / store）— スナップショットの取得・復元・保存/読込
- `Profile`（fingerprint / matcher）— ディスプレイ fingerprint 生成とマッチングスコアリング
- `AppLauncher` — `open -a` によるアプリ起動と window 出現リトライ
- `Config`（paths）— 設定/保存パス解決

**データ構造**（プラン準拠、`version`/`name`/`capturedAt`/`displayProfile{fingerprint,displays}`/`spaces`/`windows[]`）。各 window は絶対 `frame` と `relativeFrame`（display 内 0.0–1.0）、`flags{floating,sticky,minimized,fullscreen}` を保持。

**復元アルゴリズム**:
1. 現在の displays/spaces/windows を取得
2. 保存時 display と現在 display をスコアで対応付け
3. Space は label 優先・なければ index で対応
4. window は app + title + role + size で対応付け
5. 未起動 app は `open -a` で起動し数秒リトライ
6. Display/Space へ移動 → floating 状態を整える → `relativeFrame` から現在座標を算出 → move/resize
7. focus を保存時に近い状態へ戻す
8. 失敗した window を末尾にレポート

**ディスプレイマッチング（スコアリング）**: serial/uuid 一致 +50 / name 一致 +15 / resolution 一致 +15 / frame size 一致 +10 / spaces数が近い +5 / 相対配置が近い +10。**70点以上で同一ディスプレイ扱い**、満たなければ候補提示。

**実装順序**（プラン準拠）: doctor → snapshot save → 保存JSON確認 → snapshot list → restore --dry-run → 実 move/resize → Space label/移動 → アプリ起動待ち → display profile 自動判定 → restore --auto → yabai signal 連携 → メニューバーアプリ化。

---

## 7. Open Questions

| Question | Owner | Deadline |
|----------|-------|----------|
| Swift CLI の single binary 配布方法（SwiftPM でのビルド/リリース、Homebrew tap の要否） | 本人 | フェーズ2（OSS公開）前 |
| window 対応付けの精度: 同一 app で複数 window（同じ title）の識別をどう安定させるか（id は再起動で変わる前提） | 本人 | restore 実装時（P0-5） |
| `open -a` 後の window 出現リトライのタイムアウト/回数のデフォルト値 | 本人 | P1-3 実装時 |
| minimized / fullscreen window の復元をどこまでやるか（flags は保存するが復元手順が未定義） | 本人 | restore 実装時 |
| Space が保存時より少ない場合、新規 Space を作成するか既存にマージするか | 本人 | P1-2 実装時 |
| daemon の常駐方式（LaunchAgent か yabai signal か）— Swift 採用の動機と直結 | 本人 | P2-1 着手前 |

---

## 8. Timeline & Phasing

**Phase 1 — MVP / 個人利用（P0）**
`doctor` → `snapshot save`（保存JSON確認）→ `snapshot list` → `restore --dry-run` → 実 move/resize による復元 → 失敗レポート。
ゴール: **自分の主要構成で save → 崩す → restore で戻る**（Section 3 Goal 1）。ここで「アイデアが現実味を持つ」ライン。

**Phase 2 — 実用強化（P1）**
`profile capture` / fingerprint、Space label 対応、アプリ起動待ち、floating 復元、`restore --auto`。複数構成（自宅↔オフィス）の切り替え運用に耐える状態へ。

**Phase 3 — OSS 公開**
README（Requirements / License）・LICENSE(MIT)・yabai 非同梱明記を整備。`doctor` とエラーハンドリングを他人が使える品質に。配布手段（Homebrew tap 等）を決定。

**Phase 4 — 自動化 / GUI（P2）**
`daemon`（display 変更検知 → `restore --auto`）、yabai signal 連携、SwiftUI メニューバーアプリ化・macOS 通知・LaunchAgent 統合。

**依存関係**: 全フェーズが yabai のインストール・scripting-addition 有効化を前提（`doctor` で検証）。Phase 2 以降は Phase 1 の snapshot データ構造に依存。
