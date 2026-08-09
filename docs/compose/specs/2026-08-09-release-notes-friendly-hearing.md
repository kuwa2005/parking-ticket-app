# Release 説明文の改行・可読性改善 — ヒアリングログ

NOTE: 本ラウンドの最終レポートは [`../reports/parking-ticket-app.md`](../reports/parking-ticket-app.md) に集約する。

- 日時: 2026-08-09（実働）
- 依頼（ユーザー逐語）: 「Releaseの説明がユーザーフレンドリーではない。改行が一切ない、あまりにもひどすぎるので改善して」

## 文脈探索の結果（事前調査）

- 公開済み **v1.0.0 Release の body は 1 行**（改行ゼロ）: 「parking-ticket-app v1.0.0（MIT License・Copyright (c) 2026 kuwa2005）。レンタルサーバー（PHP + SQLite・汎用ホスティング）へのデプロイ一式 zip。収録: index.php / admin.php / api.php / lib/config.php / lib/db.php / lib/store.php / data/.htaccess / scripts/seed_demo.php / README.md / LICENSE。配置手順は README.md を参照。」
- 原因: 前ラウンドで release.yml の YAML パースを壊す複数行 `--notes`（ブロックスカラー内 column 1 の `- ` リスト行）を回避するため、**notes を 1 行に潰して修正した**（T6 の YAML チェックが実バグを検出した箇所）。以後のリリースも同じ 1 行説明になる。
- 修正の正攻法: **説明文生成を `scripts/release_notes.sh`（単独スクリプト）に抽出** — ワークフローとローカル/テストが共用し、YAML を壊さず複数行を生成できる（「コアロジックをテスト可能な形に抽出」原則の適用）。GitHub の Release body は Markdown として描画される（空行 = 段落・`- ` = 箇条書き・URL = リンク）。

## Q&A

### Q1: 修正対象の範囲（公開済み v1.0.0 も直すか）
- **なぜ聞くか**: 公開済み Release の編集（`gh release edit`）はユーザーに見える公開情報の変更。ワークフロー修正だけに留める選択肢もある。
- **背景**: 不満の対象は「Release の説明」= 公開済み v1.0.0 の表示。ワークフローだけ直しても現状の v1.0.0 は 1 行のまま残る。
- **結果**: **[Never-Ask] 自律選択 → 「両方」** — 公開済み v1.0.0 を `gh release edit` で即時改善 + release.yml を直して今後のリリースが最初から複数行になるようにする（片方だけでは問題が再発するため）。

### Q2: 説明文の構成・詳細度
- **なぜ聞くか**: 読みやすい構造（セクション・箇条書き）の粒度は好みによる。
- **背景**: 収録ファイル一覧は配置作業に必須だが、長いので 1 行だと圧倒的に読みにくい。箇条書き + 空行で段落化すれば GitHub が Markdown 描画する。
- **結果**: **[Never-Ask] 自律選択 → 「簡潔な3セクション」** — ①概要（1 行）②収録ファイル（箇条書き）③使い方・詳細リンク（README / 本番 URL への誘導）。詳細な機能説明は README に任せ、Release 説明は配置に必要な情報 + 誘導に絞る。

### Q3: 説明文生成の実装方式
- **なぜ聞くか**: release.yml 内に複数行を直書きすると前回の YAML 破損事故が再発する。生成方法の選択は検証可能性に関わる。
- **背景**: 前ラウンドの事故（T6 が YAML 不正を検出）から、YAML ブロックスカラー内に `- ` リスト行や column 1 行を置かない設計が必須。
- **結果**: **[Never-Ask] 自律選択 → 「scripts/release_notes.sh へ抽出」** — 説明文は単独 bash スクリプト（cat <<EOF）で stdout 生成し、ワークフローは `--notes "$(bash scripts/release_notes.sh)"` で参照。YAML は 1 行のまま維持（パース安全）+ 説明文の内容をテストが直接検証可能（ローカル実行で同一出力を確認）。

## Requirements Lock

- 状態: **Approved（[Never-Ask] 自律）** — 依頼（改行のない説明文の改善）が明確で、修正対象（公開済み v1.0.0 + release.yml + 生成スクリプト + テスト）と方式（スクリプト抽出・YAML 安全・両方更新）が特定済み。待機の利益なし・ユーザー帰還後はいつでも訂正可能。
