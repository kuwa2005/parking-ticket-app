# MIT ライセンス付与 + GitHub Releases 登録（v1.0.0・Actions 利用） — 要件・機能仕様・テスト仕様

NOTE: 本仕様の検証結果と実測値の最終取りまとめは [`../reports/parking-ticket-app.md`](../reports/parking-ticket-app.md)（最終レポート）を参照。

- 日付: 2026-08-09
- 依頼（逐語）: 「このアプリをMITライセンスにして」「レンタルサーバーへのデプロイ一式をReleasesに登録して。」「リリース物作成はGitHubのActionsを利用すること」「バージョンは v1.0.0 とする」
- ヒアリングログ: [`./2026-08-09-mit-license-and-release-hearing.md`](./2026-08-09-mit-license-and-release-hearing.md)（Q1〜Q4 + Requirements Lock Approved）

## 要件

- **R1**: リポジトリルートに `LICENSE` を追加（**MIT License**・`Copyright (c) 2026 kuwa2005`・標準 MIT 本文）。
- **R2**: `README.md` に**ライセンス節**（MIT・LICENSE ファイルへのリンク・著作権表記）を追加し、**ディレクトリ構成**に `LICENSE` と `.github/workflows/release.yml` を追記。
- **R3**: `.github/workflows/release.yml` を新設 — **`v*` タグ push で自動実行**・`permissions: contents: write`・`scripts/build_release.sh` でデプロイ一式 zip を生成し、**`gh release create`（GH_TOKEN = github.token・サードパーティ Action 不使用）** で Release 作成 + アセット添付。アセット名は `parking-ticket-app-<タグ>.zip`（例: `parking-ticket-app-v1.0.0.zip`）。
- **R4**: `scripts/build_release.sh` を新設 — **python3 標準ライブラリ（zipfile）で決定論的に zip 生成**（外部依存ゼロ・ランナー/ローカル共通）・VERSION は第 1 引数（省略時 `GITHUB_REF_NAME` から `v` 除去・なければ `local`）・出力先 `dist/parking-ticket-app-<VERSION>.zip`・**収録 = デプロイ一式 8 ファイル + README.md + LICENSE**（DB バイナリ・tests・docs・Docker 一式は除外）・zip 内は `parking-ticket-app-<VERSION>/` フォルダ配下に配置（展開後にそのまま配置可能）。
- **R5**: ドキュメント整合 — 最終レポート（docs/compose/reports/parking-ticket-app.md）に本ラウンドのコミット・ファイル（LICENSE・.github/workflows/release.yml・scripts/build_release.sh）・spec 一覧・検証実測を追記し、コミット + push まで完了。
- **R6**: タグ `v1.0.0` を push して Actions を実行し、**Release v1.0.0 にアセット `parking-ticket-app-v1.0.0.zip` が登録されることを実測確認**。

## 非目標

- コード本体（index.php/admin.php/api.php/lib 等）への変更は行わない。
- ライセンスの変更（MIT 以外）や著作権者の譲渡。
- Docker 一式・tests・docs のリリースアセットへの同梱。
- npm/リリースツール（softprops/action-gh-release 等）のサードパーティ Action 利用。

## テスト仕様

`tests/license_and_release_check.sh`（読み取り専用・全 PASS で exit 0・結果は reports/2026-08-09-mit-license-and-release-check.txt に記録）:

- **T1**: `LICENSE` が存在し、先頭に `MIT License` の記載がある
- **T2**: `LICENSE` に `Copyright (c) 2026 kuwa2005` が含まれる
- **T3**: `README.md` にライセンス節（`MIT` 記載）がある
- **T4**: `scripts/build_release.sh` を実行して `dist/parking-ticket-app-local.zip` が生成される（exit 0）
- **T5**: 生成 zip の収録ファイルが**期待の 10 件**（index.php / admin.php / api.php / lib/config.php / lib/db.php / lib/store.php / data/.htaccess / scripts/seed_demo.php / README.md / LICENSE）と一致し、`.db` が含まれない（python3 zipfile で列挙・決定論的）
- **T6**: `.github/workflows/release.yml` が存在し、`v*` タグトリガー・`gh release create`・`contents: write` を含む（YAML としてパース可能）
- **T7**: 認証情報（外部値ファイル `/tmp/park_creds_check.txt` の全値）がコミット対象ドキュメントに存在しない（既存の leak-check 記録を除く）
- **T8**: git が clean かつ HEAD と origin/main が一致（本チェック自身の結果レポートを除く）

## 受入基準

- **A1**: `LICENSE`（MIT・2026 kuwa2005）と README ライセンス節がリポジトリに存在し、テスト T1〜T3 が PASS。
- **A2**: ビルドスクリプトが期待どおりの zip（10 ファイル・.db なし）を生成し、テスト T4〜T5 が PASS。
- **A3**: タグ `v1.0.0` push 後の GitHub Actions 実行（workflow run）が成功し、Release v1.0.0 に `parking-ticket-app-v1.0.0.zip` が添付されている（`gh release view v1.0.0` で実測確認）。
- **A4**: 全変更がコミット + push され、working tree clean・origin/main 同期。
