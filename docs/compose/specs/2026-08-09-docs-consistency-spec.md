# ドキュメント整合ラウンド — 仕様

> NOTE: この仕様の検証結果と実測値の最終取りまとめは docs/compose/reports/parking-ticket-app.md（最終レポート）を参照。

- 日時: 2026-08-09（実働）
- 依頼（逐語）: 「ドキュメントを整備し、全部プッシュ＆コミット、リポジトリと齟齬がない状態に完全に一致するようにして」
- ヒアリング: docs/compose/specs/2026-08-09-docs-consistency-hearing.md（Q1〜Q3・Lock Approved）

## 目的

リポジトリ内のドキュメント群（README・最終レポート・ローリング結果ファイル・spec の NOTE マーカー）を、現在のコード・テストスイート・本番状態（コミット 6dc1c7f まで）と完全に一致させる。すべてコミットして push し、`git status` clean + origin/main 同期を確認する。

## 現状の齟齬（調査で特定）

1. README.md: api 一覧に add_record 欠落・受入 17→19・デプロイ実績に最新 2 ラウンド欠落・管理者画面の新機能（追加ボタン/グラフ位置/時間帯範囲）未記載
2. 最終レポート docs/compose/reports/parking-ticket-app.md: コミット履歴・API 一覧・テスト数・検証履歴・Journey Log・Source Materials/仕様一覧が最新未反映
3. ローリング結果ファイル reports/2026-08-07-{unit,smoke,e2e-ui}-results.txt: 実測が旧ラウンド（21/25/63）で現スイート（22/30/74）と不一致
4. spec の NOTE マーカー欠落: 2026-08-09 の 3 ファイル

## 要件

### R1: テストスイートの再実行と結果ファイル更新
- 全スイートを再実行し、ローリング結果ファイルを最新実測で上書き:
  - `php tests/run_tests.php` → reports/2026-08-07-unit-test-results.txt（期待 22/22）
  - `php tests/seed_demo_test.php` → reports/2026-08-07-seed-demo-test.txt（期待 8/8）
  - `bash tests/smoke_test.sh` → reports/2026-08-07-smoke-test-results.txt（期待 30/30）
  - `node tests/e2e_ui.mjs`（php -S + chrome 9222）→ reports/2026-08-07-e2e-ui-results.txt（期待 74/74）
- 各ファイルのタイトル・実測行を今回の実行内容に更新（E2E は「2026-08-09・グラフ位置/時間帯範囲/日詳細追加ラウンド」等）

### R2: README.md 更新
- api.php のアクション一覧に `add_record`（要認証・過去日への記録追加）を追加
- 本番受入テストのケース数を 17 → **19** に更新（T18/T19 説明を含む）
- 本番デプロイ実績に以下を追記: カレンダー7列/ログアウト内蔵/前月翌月ラウンド（コミット 2adbed4・受入 17/17・ブラウザ 16/16）、グラフ位置/時間帯範囲/日詳細追加ラウンド（コミット 44f0709 + リリース証跡 6dc1c7f・受入 19/19・ブラウザ 11/11）
- 管理者画面の使い方・ディレクトリ構成の admin.php 説明に「日詳細の追加（つけ忘れ記録・枚数+時間）」を追記

### R3: 最終レポート（docs/compose/reports/parking-ticket-app.md）更新
- コミット履歴・API 一覧（add_record 追加）・ファイル構成のテスト数（単体 22・スモーク 30・E2E 74・受入 19）を最新に
- 検証履歴に SSH 知識整理ラウンド（92bdeba）とグラフ/追加ラウンド（44f0709/6dc1c7f）を追記
- Journey Log に最新教訓を追記（E22 Bootstrap Modal hide() no-op → shown ガード・waitFor の boolean 強制・本番受入の読み取り専用検証方針）
- Source Materials・仕様一覧に 2026-08-09 の仕様 3 件（calendar-layout / ssh-block-knowledge / admin-report-chart-position）を追加
- H1 直下の NOTE の状態（status: delivered）を維持

### R4: spec の NOTE マーカー追加
- 以下の 3 ファイルに、calendar-layout 系と同形式の NOTE マーカー（最終レポートへの相対リンク）を追加:
  - docs/compose/specs/2026-08-09-admin-report-chart-position-hearing.md
  - docs/compose/specs/2026-08-09-ssh-block-knowledge-hearing.md
  - docs/compose/specs/2026-08-09-ssh-block-knowledge-spec.md

### R5: コミット・プッシュ
- 認証情報の git grep 実施（該当なし確認）→ 全変更をコミット → origin/main へ push → `git status` clean・同期確認

## テスト仕様（tests/docs_consistency_check.sh）

自動テストプログラム（bash・grep ベース・読み取り専用）。全 PASS（exit 0）でリポジトリ整合を検証する:

- **T1**: reports/2026-08-07-unit-test-results.txt が「22/22 passed」を含む
- **T2**: reports/2026-08-07-smoke-test-results.txt が「30 passed, 0 failed」を含む
- **T3**: reports/2026-08-07-e2e-ui-results.txt が「74/74 passed」を含む
- **T4**: reports/2026-08-07-seed-demo-test.txt が「8/8 passed」を含む
- **T5**: README のテスト表に 22チェック / 30チェック / 74チェック / 19ケース が含まれる
- **T6**: README の api 一覧に `add_record` が含まれる
- **T7**: README のデプロイ実績に 44f0709（または 6dc1c7f）と 19/19 が含まれる
- **T8**: 最終レポートに add_record・74/74（または 74チェック）・6dc1c7f（または 44f0709）が含まれる
- **T9**: 2026-08-09 の spec/hearing 6 ファイルすべてに NOTE マーカーが含まれる
- **T10**: 認証情報（SFTP パスワード / 旧本番 ADMIN_PW — 実値はリポジトリ外の外部値ファイル `/tmp/park_creds_check.txt` で管理）がコミット対象ドキュメントに存在しない（外部値ファイルの全値について git grep 0 件 — 既存の leak-check 記録を除く）
- **T11**: `git status --porcelain` が空・`git rev-parse HEAD` == `git rev-parse origin/main`

実行: `bash tests/docs_consistency_check.sh` → 結果を reports/2026-08-09-docs-consistency-check.txt に記録

## 受入基準（A）

- **A1**: README・最終レポート・結果ファイルが現在のテスト実測（22/30/74/8/19）と一致（T1〜T8 PASS）
- **A2**: 2026-08-09 の全 spec/hearing に NOTE マーカーあり（T9 PASS）
- **A3**: コミット対象に認証情報なし（T10 PASS）
- **A4**: 全変更コミット・push 済み・リポジトリ clean・origin/main 同期（T11 PASS）
