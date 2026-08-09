# SSH 遮断対応ノウハウの整理 — 要件・機能仕様・テスト仕様

- 日付: 2026-08-09
- 状態: **Requirements Lock Approved**（[Never-Ask] 自律承認・ヒアリングログ参照）
- 依頼（ユーザー逐語）: 「SSH IPブロック解除前に施行した作業はスキルやノウハウとしては不要なので削除し、SSHアクセスでブロックされたら https://docomo2.com/ipaddress/b45/ にアクセスして2～3分待つということだけ記憶して」
- 対象: プロジェクトメモリ（`~/.local/share/oimo/memory/projects/569a0d3f-*/MEMORY.md`・`MEMORY-e2e-test-tooling.md`）+ 証跡ドキュメント（本リポジトリ）

## 背景

coreserver（b45）の SSH/SFTP 遮断（2026-08-09 09:12〜09:55・`kex_exchange_identification: Connection reset by peer`）を「fail2ban 系スロットリング」と誤診し、以下のノウハウを施行していた:
- プローブ間隔規律（遮断中は接続完全停止・10〜20 分間隔で 1 回のみ）
- 監視ループ（cron loop）の再武装手順
- 「プローブ連発はブロックタイマーを延長する」仮説

ユーザー指示により真因が確定: **coreserver は接続元 IP の事前登録制**であり、登録 URL（https://docomo2.com/ipaddress/b45/）にアクセスすると 2〜3 分後に SSH 接続可能になる（表示される警告画面は偽物で無害）。→ 誤診ベースのノウハウは不要のため削除し、正しい知識のみ残す。

関連する同一調査中の誤診も除去対象（Q1 自律決定）:
- 「HTTP 取得サイズ vs ローカルソース」の比較による配置判定（実際は PHP 実行後出力のためソースより小さく見える — 誤診）
- 「本番 index.php/admin.php はユーザー直接改修の DEMO 版（PHP ヘッダ除去）」判定（SFTP get + cmp でローカルと byte 一致を確認し覆った — 誤診）

## 要件（R）

- **R1**: SSH 遮断対応の誤診ベースノウハウ（fail2ban 説・プローブ間隔規律・監視ループ再武装・サイズ比較配置判定・DEMO 版誤診）をプロジェクトメモリから除去する。
- **R2**: 正しい知識のみを残す — 「SSH アクセスでブロックされたら https://docomo2.com/ipaddress/b45/ にアクセスして 2〜3 分待つ（偽警告画面は無害）」。
- **R3**: 証跡ドキュメント（ヒアリングログ・本仕様・テスト仕様）を docs/compose/specs/ に、テスト実行結果を reports/ に作成し、コミットする。公開リポジトリのため認証情報（SFTP パスワード・本番 ADMIN_PW・サーバーアカウント）は記載しない。

## 機能仕様（対象ファイルと編集内容）

対象メモリファイル（プロジェクトメモリディレクトリ配下）:
1. **MEMORY.md**
   - `## Discovered durable knowledge` の「coreserver SFTP の ls が flaky」エントリ → 「lftp の ls は GNU オプション非対応（`ls -la` 不可）」に置換（遮断起因の flaky 記述を除去）
   - 「本番配置検証は curl 取得 + サイズ比較で決定的」エントリ → 「curl マーカー grep + SFTP 実ファイル byte 比較」に訂正（サイズ比較は PHP 実行後出力のため誤診と明記）
   - 「デプロイは単一パイプライン + マーカー/サイズ検証ゲート」エントリ → サイズゲート部分を削除（PHP 実行後出力のため）
   - 「本番 index.php/admin.php はユーザー直接改修の DEMO 版」エントリ → 「本番の実ファイルはリポジトリ版と byte 一致（区間39 の判定は誤診）」に訂正
   - 「MEMORY-e2e-test-tooling.md 参照」行の要約「SSH スロットリング誤診（訂正）」→「SSH 接続は IP 登録制（docomo2.com/ipaddress/b45/）」に更新
   - 既存の正しいエントリ「coreserver の SSH アクセスは『IP アドレス登録制』」は**維持**（R2 の中核）
2. **MEMORY-e2e-test-tooling.md**
   - 「coreserver の SSH/SFTP（22 ポート）もスロットリングされる（プローブ規律）」エントリ → 「接続元 IP 登録制（登録 URL → 2〜3 分待つ）」に置換

## テスト仕様（S）— 自動テスト `tests/ssh_knowledge_check.sh`

検証対象: メモリファイル（MEMORY.md・MEMORY-e2e-test-tooling.md）+ 証跡ドキュメント（本リポジトリ docs/compose/specs/*ssh-block-knowledge-cleanup*）。

| ID | 入力 | 期待結果 |
|----|------|----------|
| S1 | MEMORY.md に正しい知識が存在するか | `docomo2.com/ipaddress/b45` を含む行があり、かつ同エントリ内に「2〜3 分」を含む（R2 充足） |
| S2 | MEMORY-e2e-test-tooling.md に正しい知識が存在するか | `docomo2.com/ipaddress/b45` を含む（R2 の複数ファイル整合） |
| S3 | 誤診ベースのノウハウが除去されているか（MEMORY.md + MEMORY-e2e-test-tooling.md） | 禁止語句のうち**禁止パターン**が 0 件: ①「プローブ連発」かつ「ブロック」を同一エントリに含む ②「20 分間隔」/「20 分以上間隔」 ③「接続完全停止」 ④「ユーザー直接改修の DEMO 版」 ⑤「サイズ比較」かつ「決定的」 ⑥「スロットリングされる」（ただし「誤診」「廃止」「登録制」を含む訂正記述は許容 — 正規表現で除外） |
| S4 | 証跡ドキュメントが存在し、認証情報を含まないか | docs/compose/specs/2026-08-09-ssh-block-knowledge-cleanup-hearing.md と同 -spec.md が存在し、**認証情報の実値はリポジトリに埋め込まない設計**（テストは外部値ファイル `/tmp/park_creds_check.txt` に実値があれば grep・無ければ値チェックをスキップして PASS。値はリポジトリ外でのみ管理） |

実行: `bash tests/ssh_knowledge_check.sh` → 全ケース PASS で exit 0・各ケースの PASS/FAIL を出力。結果を reports/2026-08-09-ssh-block-knowledge-cleanup-check.txt に記録。

## 受入チェックリスト（A）

- A1: メモリに正しい知識（登録 URL + 2〜3 分待ち）のみが残っている（S1・S2 PASS）
- A2: 誤診ベースのノウハウが除去されている（S3 PASS）
- A3: 証跡ドキュメント 3 点 + 実行結果 1 点が存在し、認証情報を含まない（S4 PASS）
- A4: 証跡一式をコミット・push 済み（reports 追記後）

## 非目標

- アプリコード（index.php/admin.php/api.php/lib）の変更は行わない（本ラウンドはメモリ整理のみ）
- セッション checkpoint ファイルの直接編集は行わない（writer 管理領域・会話履歴と本ドキュメントから次回 checkpoint に反映される）
- 誤診があった当時の調査レポート（reports/2026-08-09-r3-production-check.txt 等）の歴史記述は改変しない（訂正後の結論が同一ファイルに既に記載済み）
