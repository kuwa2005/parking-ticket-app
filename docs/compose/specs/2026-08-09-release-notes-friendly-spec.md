# Release 説明文の改行・可読性改善 — 要件・機能仕様・テスト仕様

NOTE: 本仕様の検証結果と実測値の最終取りまとめは [`../reports/parking-ticket-app.md`](../reports/parking-ticket-app.md)（最終レポート）を参照。

- 日付: 2026-08-09
- 依頼（逐語）: 「Releaseの説明がユーザーフレンドリーではない。改行が一切ない、あまりにもひどすぎるので改善して」
- ヒアリングログ: [`./2026-08-09-release-notes-friendly-hearing.md`](./2026-08-09-release-notes-friendly-hearing.md)（Q1〜Q3 + Requirements Lock Approved）

## 要件

- **R1**: `scripts/release_notes.sh` を新設 — リリース説明文を **stdout に複数行で生成**（VERSION は第 1 引数 / 未指定時 `GITHUB_REF_NAME` / なければ `local`）。構成 = ①概要（1 行: アプリ名・バージョン・MIT License・著作権）②空行③説明（デプロイ一式 zip の説明）④空行⑤**収録ファイル（`- ` 箇条書き・10 ファイル）**⑥空行⑦使い方・リンク（README・本番 URL）。
- **R2**: `.github/workflows/release.yml` の `--notes` を **`"$(bash scripts/release_notes.sh)"`** に変更（YAML は 1 行のまま維持 — ブロックスカラー内の複数行直書きによる YAML 破損を回避）。
- **R3**: 公開済み **v1.0.0 Release の説明を `gh release edit v1.0.0 --notes "$(bash scripts/release_notes.sh v1.0.0)"` で更新**（複数行・セクション構成に）。
- **R4**: テスト追加 — `tests/license_and_release_check.sh` に **T9（release_notes.sh の出力検証）/ T10（release.yml が release_notes.sh を使用・YAML パース）** を追加し、結果を reports/2026-08-09-release-notes-friendly-check.txt に記録。
- **R5**: ドキュメント整合 — 最終レポート（docs/compose/reports/parking-ticket-app.md）・ヒアリング/spec 一覧を更新し、コミット + push まで完了。

## 非目標

- 説明文以外の Release 設定（タグ名・アセット・タイトル）の変更。
- コード本体（index.php/admin.php/api.php/lib 等）への変更。
- ライセンス・バージョンの変更。

## テスト仕様

`tests/license_and_release_check.sh` に追加（既存 T1〜T7 + 新規 T9〜T11 = 全 10 チェック・旧 T8 の git clean チェックは T11 へ移設・全 PASS で exit 0・結果は reports/2026-08-09-release-notes-friendly-check.txt に記録）:

- **T9**: `bash scripts/release_notes.sh v1.0.0` の出力が複数行（**≥7 行**）で、**空行が 2 つ以上**、**`- 収録:` で始まる箇条書き行**（10 ファイル名を含む）、**README リンク**（github.com/kuwa2005/parking-ticket-app）を含む
- **T10**: `.github/workflows/release.yml` が **`scripts/release_notes.sh`** を参照し（`bash scripts/release_notes.sh`）、YAML としてパース可能（既存 T6 の YAML チェックと重複しない追加確認）
- **T11**: git が clean かつ HEAD と origin/main が一致（本チェック自身の結果レポートを除く）

## 受入基準

- **A1**: `scripts/release_notes.sh` が複数行の説明文を生成し、テスト T9・T10 が PASS。
- **A2**: 公開済み v1.0.0 の説明が複数行（概要・収録・使い方のセクション構成）に更新されたことを `gh release view v1.0.0` の body で実測確認（改行あり・`- 収録:` あり）。
- **A3**: 全変更がコミット + push され、working tree clean・origin/main 同期。
