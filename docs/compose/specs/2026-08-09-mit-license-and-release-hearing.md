# MIT ライセンス付与 + GitHub Releases 登録（v1.0.0・Actions 利用） — ヒアリングログ

NOTE: 本ラウンドの最終レポートは [`../reports/parking-ticket-app.md`](../reports/parking-ticket-app.md) に集約する。

- 日時: 2026-08-09（実働）
- 依頼（ユーザー逐語）: 「このアプリをMITライセンスにして」「レンタルサーバーへのデプロイ一式をReleasesに登録して。」「リリース物作成はGitHubのActionsを利用すること」「バージョンは v1.0.0 とする」

## 文脈探索の結果（事前調査）

- リポジトリ状態: HEAD = 4c35d6a（ドキュメント整合ラウンド完了）・working tree clean・origin/main 同期済み。
- **LICENSE ファイルは未存在**・README / 最終レポートともライセンス記載なし。
- **デプロイ一式の定義**: 過去ラウンドで確立したデプロイバンドル 8 ファイル = `index.php`・`admin.php`・`api.php`・`lib/config.php`・`lib/db.php`・`lib/store.php`・`data/.htaccess`・`scripts/seed_demo.php`（本番 https://debugprint.com/parking/ に lftp mirror で配置された内容・DB バイナリは除外）。
- `.github/` は未存在（CI 未設定・今回新設）。
- ローカル環境に `zip`/`unzip` コマンドなし → ビルドは **python3 標準ライブラリ（zipfile）** で実装（GitHub Actions の ubuntu-latest ランナーにも python3 常駐・依存ゼロ・ローカルで決定論的に検証可能）。

## Q&A

### Q1: MIT ライセンスの著作権者表記（Copyright (c) 2026 ◯◯）に記載する名前
- **なぜ聞くか**: 著作権者はライセンスの法的な主体であり、勝手に決められない（実名か別名かはユーザーしか知らない）。
- **背景**: リポジトリは Public（kuwa2005/parking-ticket-app）。プロジェクト開始は 2026-08-07（年は 2026 で確定）。実名を公開リポジトリに出したくない場合もある。
- **結果**: **[Never-Ask] 自律選択 → 「kuwa2005（GitHub ユーザー名）」** — 公開リポジトリの所有者名と一致し、実名を出さずに済む安全な表記。`Copyright (c) 2026 kuwa2005`。

### Q2: v1.0.0 のリリースアセット（zip）に含めるファイル構成
- **なぜ聞くか**: 「デプロイ一式」の範囲は過去ラウンドのバンドル 8 ファイルで確定済みだが、README/LICENSE を含めるか・全ファイルを含めるかは選択肢がある。
- **背景**: レンタルサーバーへの配置を目的とするなら PHP ファイル群のみで足りるが、リリース物として自己完結・ライセンス表記（配布時の MIT 表示義務）を満たすには README + LICENSE を含めるのが適切。
- **結果**: **[Never-Ask] 自律選択 → 「デプロイ一式（8 ファイル）+ README.md + LICENSE」** — DB（data/*.db）・tests・docs・Docker 一式は除外。配置に必要なもの + ライセンス準拠の最小構成。

### Q3: GitHub Actions によるリリース作成のトリガー
- **なぜ聞くか**: リリース作成の契機（タグ push / 手動 / 両方）は運用方針に関わる。
- **背景**: 「バージョンは v1.0.0 とする」ことからタグ `v1.0.0` を切ることが確定。タグ push 駆動が標準的で、リリースの再現性（同じタグ = 同じビルド）が保証される。
- **結果**: **[Never-Ask] 自律選択 → 「v1.0.0 タグ push で自動」** — `v*` タグ push でビルド → `gh release create` で Release 作成 + アセット添付（`permissions: contents: write`・GH_TOKEN = github.token・サードパーティ Action 不使用）。

### Q4: 本ラウンドのドキュメント整合（ヒアリングログ・spec・最終レポート・チェックテスト・コミット/push）を実施するか
- **なぜ聞くか**: ライセンス付与と Actions 追加は README・最終レポート・ディレクトリ構成の記述に影響するため、前ラウンド（ドキュメント整合 4c35d6a）の規律に従うか確認。
- **背景**: ユーザーは直前に「リポジトリと齟齬がない状態に完全に一致するようにして」と明示しており、ドキュメント追従が期待される。
- **結果**: **[Never-Ask] 自律選択 → 「実施する（既存規律どおり）」** — README・最終レポート・spec/hearing・チェックテストを本ラウンドで更新・作成し、コミット + push まで完了させる。

## Requirements Lock

- 状態: **Approved（[Never-Ask] 自律）** — 依頼が明確（MIT・v1.0.0・Actions・Releases 登録）で、修正対象（LICENSE 追加・README/workflow 新設・docs 追従）が特定済み。待機の利益なし・ユーザー帰還後はいつでも訂正可能。
