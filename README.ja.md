# ywr — yabai workspaces

[English](README.md) | 日本語

macOS のウィンドウ配置（ディスプレイ構成・Spaces・ウィンドウ位置）を名前付きの
スナップショットとして保存し、同じディスプレイ構成が接続されたときに復元します。
`ywr` は [yabai](https://github.com/koekeishiya/yabai) の薄い**コンパニオン CLI**
です。yabai を fork したり同梱したりはせず、`yabai -m` を呼び出すだけです。

## ステータス

実装済み:

- **CLI (`ywr`)**: `doctor`、`snapshot save/list`、`restore`（`--dry-run` と
  `--auto` に対応）、`profile capture/list`、`daemon`（ディスプレイ変更を検知して
  自動復元）。
- **メニューバーアプリ (`ywr-menubar`)**: SwiftUI `MenuBarExtra`。現在のレイアウト
  を保存し、自動復元を実行できます。配色は外部ファイルで指定します。

## ドキュメント

- **[使い方ガイド](docs/usage.ja.md)** — 導入・基本操作・自動復元・テーマ・トラブルシュート（[English](docs/usage.md)）
- **[ロードマップ](ROADMAP.md)** — 統合仮想デスクトップ対応の実装済み範囲と今後の課題

## 必要条件

本ツールは yabai が別途インストール・設定されていることを前提とします。

```sh
brew install koekeishiya/formulae/yabai
yabai --start-service
```

環境の確認は `ywr doctor` を実行してください。

## 使い方

```sh
ywr doctor                 # yabai と環境をチェック
ywr snapshot save home     # 現在のレイアウトを "home" として保存
ywr snapshot list          # 保存済みスナップショット一覧
ywr restore home --dry-run # 復元内容をプレビュー（変更しない）
ywr restore home           # ウィンドウを元の配置へ戻す
ywr restore --auto         # 現在のディスプレイに一致する snapshot を自動選択
ywr restore home --create-spaces  # 不足している labeled Space を作成してから復元
ywr profile capture home   # 現在のディスプレイ構成を記録
ywr daemon --interval 2    # ディスプレイ変更時に自動復元（ポーリング）
ywr signal install         # yabai のシグナルで自動復元（デーモン不要）
```

`ywr daemon`（ポーリング）と `ywr signal install`（yabai シグナルによるイベント
駆動）は自動復元の 2 方式です。お好みの方をどうぞ。復元では各ウィンドウの
floating / minimized / fullscreen 状態も戻し、保存時にアクティブだったウィンドウ
へフォーカスを戻します。

スナップショットとプロファイルは `$XDG_CONFIG_HOME/yabai-workspaces`
（既定は `~/.config/yabai-workspaces`）配下に JSON として保存されます。

### メニューバーアプリのテーマ設定

カラーコードとフォントはコードを触らずに変更できるよう、別の JSON ファイルで
指定します。スナップショットと同じ場所に `theme.json`
（`~/.config/yabai-workspaces/theme.json`）を置いてください。存在しない場合は
組み込みのダーク既定が使われます。スキーマ:

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

## ビルドとテスト

```sh
swift build                # `ywr` バイナリをビルド
swift test                 # XCTest スイートを実行（Xcode が必要）
```

## アーキテクチャ

コードはテスト可能なコアライブラリ（`YWRCore`）と、合成ルート＋引数ディスパッチ
だけの薄い CLI（`ywr`）に分離されています。設計は SOLID 原則に沿っています。

- **単一責任 (SRP)** — 1 つの型は 1 つの仕事: `SnapshotCapturer`（状態を読んで
  スナップショット化）、`RestorePlanner`（スナップショット＋現状 → 計画）、
  `SnapshotRestorer`（計画を実行）、`DisplayMatcher`（ディスプレイをスコア付け）、
  `FileSnapshotStore`（永続化）、`Doctor`（診断）。
- **開放/閉鎖 (OCP)** — ディスパッチャを書き換えずに機能追加できる: CLI の各動詞は
  `Command` に準拠し `CommandRegistry` に登録、環境チェックは `DiagnosticCheck` に
  準拠、スコアリングは `MatchWeights` のデータで駆動。
- **リスコフの置換 (LSP)** — すべての協力オブジェクトはプロトコル経由でのみ利用し、
  テストの in-memory フェイクが実装を透過的に差し替えます。
- **インターフェース分離 (ISP)** — yabai アクセスを `YabaiQuerying`（読み取り）と
  `YabaiControlling`（変更）に分割し、capture/doctor が状態を変更できないように。
- **依存関係逆転 (DIP)** — 副作用はすべて `CommandRunner` 抽象を通り、コア全体は
  実機や yabai なしで単体テストできます。

復元処理は意図的に**計画と実行を分離**しています。プランナーは純粋関数なので
`--dry-run` が実行内容と厳密に一致し、すべてテスト可能です。エグゼキュータは計画を
適用し、各ウィンドウの結果を報告します（失敗を握りつぶしません）。

## ライセンス

本プロジェクトは MIT License です。`LICENSE` を参照してください。

yabai は別プロジェクトであり、MIT License で提供されています。
本プロジェクトは yabai のバイナリやソースコードを含みません。
