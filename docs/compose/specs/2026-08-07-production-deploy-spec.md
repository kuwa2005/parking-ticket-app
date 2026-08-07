# 本番デプロイ仕様（debugprint.com/parking/）— 要件・テスト仕様

- 日付: 2026-08-07
- 依頼: 「本番環境へデプロイして。必要な情報のみ使用して。」（ヒアリングログ Q19〜Q23・Requirements Lock Approved）
- 本番環境: coreserver.jp 共有ホスティング（b45.coreserver.jp・SFTP 22・アカウント pcm）・ドキュメントルート `/virtual/pcm/public_html/debugprint.com`（SFTP 相対: `public_html/debugprint.com`）
- 配置先: **`public_html/debugprint.com/parking/`**（https://debugprint.com/parking/）
- 経緯: 当初 docomo2.com/parking/ に配置したが、ユーザー再指示「https://docomo2.com/parking/ ではなく、https://debugprint.com/parking/ で動かして」（2026-08-07）により **debugprint.com/parking/ に最終確定**。docomo2.com/parking/ は撤回・削除。

## 1. 要件

| # | 要件 |
|---|---|
| R1 | アプリ一式（index.php / api.php / lib/ / data/.htaccess）を debugprint.com の `parking/` サブディレクトリに配置する |
| R2 | debugprint.com の既存サイト（ポートフォリオ: ルート index.html・about/・projects/ 等）は一切変更しない |
| R3 | 本番の ADMIN_PW は新しいランダム値（英数字12桁）に変更する。値は公開リポジトリ・ドキュメントに記載しない |
| R4 | データベースは SQLite のまま・空の DB から開始（data/parking.db はアップロードしない・初回 API 呼び出しで自動作成） |
| R5 | data/.htaccess により `/parking/data/` 配下への直接アクセス（parking.db）を遮断する |
| R6 | 接続情報（SFTP/PW）・管理PW をリポジトリ・レポートに含めない |
| R7 | デプロイ後の機能検証（記録・集計・削除・PW 認証）を実サーバーに対して実施し、結果を reports/ に記録する |
| R8 | アプリは公開 URL で動作する（ポート4500 の制約は共有ホスティングでは適用外・コードにポート依存なし） |

## 2. 機能仕様（本番構成）

- 配置後のファイル構成（`/virtual/pcm/public_html/debugprint.com/parking/`）:
  - `index.php`（UI・Bootstrap 5.3.3 CDN・相対 URL の fetch で api.php を呼ぶ）
  - `api.php`（JSON API: add/today/monthly/delete/login/logout・セッション認証）
  - `lib/config.php`（**本番 ADMIN_PW は新値**・DB_PATH 既定 `__DIR__.'/../data/parking.db'` → `/parking/data/parking.db`）
  - `lib/db.php` / `lib/store.php`
  - `data/.htaccess`（deny-all → `/parking/data/` 直アクセス 403）
- 動作前提: ホスト PHP が PDO SQLite を有効・`data/` が PHP から書き込み可能
- タイムゾーン: Asia/Tokyo 固定（コード内）→ ホスト TZ 非依存
- デプロイ手段: SFTP（lftp）のみ使用。MySQL / PostgreSQL は不使用（アプリが SQLite のため・「必要な情報のみ使用」）

## 3. テスト仕様（受入チェックリスト）

テストプログラム: `tests/production_check.sh <base_url>`（実サーバーに対する HTTP 検証・PASS/FAIL を出力）

| # | 入力（操作） | 期待結果 |
|---|---|---|
| T1 | `GET {base}/` | HTTP 200・HTML に駐車券 UI（`駐車券` 文言）が含まれる |
| T2 | `GET {base}/api.php?action=today`（未認証・初回） | 200・JSON `{"total":0}`・DB が自動生成される |
| T3 | `POST {base}/api.php?action=add`（JSON body `{"count":2}`・未認証・記録はPWなし） | 201・JSON に id（>0） |
| T4 | `GET {base}/api.php?action=today` | 200・`total:2` |
| T5 | `POST {base}/api.php?action=login`（JSON body `{"pw":...}`・cookie jar 使用） | 200・`{"ok":true}` |
| T6 | `DELETE {base}/api.php?action=delete&id=T3のid`（認証済み） | 204・today が `total:0` に戻る（本番を初期状態に復元） |
| T7 | `GET {base}/data/parking.db` | 403 または 404（.htaccess による遮断） |
| T8 | `POST {base}/api.php?action=login`（JSON body `{"pw":"0000"}`・誤PW） | 401・応答 ≥1秒（F1 スロットルの共有ホストでの動作確認） |
| T9 | `GET {base}/` のレスポンスヘッダ | X-Content-Type-Options: nosniff 等 F4 ヘッダが送信される |
| T10 | PHP 環境 | PHP 7.4 以上かつ PDO SQLite 有効（プローブで確認・確認後にプローブ削除） |

判定: 全ケース PASS で受入。1 件でも FAIL なら該当項目を修正して再実行。
