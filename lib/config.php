<?php
// 駐車券記録アプリ 設定
// 上書き方法（優先順）: 環境変数 PARK_DB_PATH / テストでの DB_PATH define / 本番の既定値

if (!defined('DB_PATH'))   { define('DB_PATH', getenv('PARK_DB_PATH') ?: __DIR__ . '/../data/parking.db'); }
if (!defined('ADMIN_PW'))  { define('ADMIN_PW', '1234'); }
if (!defined('APP_TZ'))    { define('APP_TZ', 'Asia/Tokyo'); }
if (!defined('MAX_COUNT')) { define('MAX_COUNT', 999); }

date_default_timezone_set(APP_TZ);
