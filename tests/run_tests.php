<?php
// 駐車券記録アプリ 単体テスト（PHP CLI）
// 実行: php tests/run_tests.php
// DB_PATH を一時ファイルに差し替えて store.php のロジックを検証する。

$tmpDb = sys_get_temp_dir() . '/park_test_' . getmypid() . '_' . bin2hex(random_bytes(4)) . '.db';
define('DB_PATH', $tmpDb);
require_once __DIR__ . '/../lib/store.php';

$results = [];
function check(string $name, bool $cond, string $detail = ''): void {
    global $results;
    $results[] = ['name' => $name, 'pass' => $cond];
    printf("%s %s%s\n", $cond ? 'PASS' : 'FAIL', $name, $detail !== '' ? " — $detail" : '');
}

$db = db_open();
$tz = new DateTimeZone(APP_TZ);
// T1/T2 は 08-06 の時刻を使い、T3 以降の「今日(08-07)」の合計に混入させない
$base = new DateTimeImmutable('2026-08-06 09:00:00', $tz);

// T11: TZ設定
check('T11 timezone is Asia/Tokyo', date_default_timezone_get() === 'Asia/Tokyo');

// T1: 記録追加（正常）
$rec = add_record($db, 3, $base);
check('T1 add_record(3)', is_array($rec) && $rec['count'] === 3 && isset($rec['id'], $rec['created_at']));

// T12: タイムスタンプ形式
check('T12 created_at format', isset($rec['created_at']) && preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $rec['created_at']) === 1);

// T2: 記録追加（異常系）
$bad = [0, -1, 1000, 1.5, 'abc', '', null];
$t2ok = true;
foreach ($bad as $v) {
    if (add_record($db, $v, $base) !== null) { $t2ok = false; }
}
check('T2 invalid counts rejected', $t2ok);

// T3: 今日の合計
add_record($db, 3, new DateTimeImmutable('2026-08-07 09:00:00', $tz));
add_record($db, 2, new DateTimeImmutable('2026-08-07 09:01:00', $tz));
add_record($db, 1, new DateTimeImmutable('2026-08-07 09:02:00', $tz));
check('T3 today total', get_today($db, new DateTimeImmutable('2026-08-07 10:00:00', $tz))['total'] === 6);

// T4: 一覧の順序（時間昇順・同刻は id 昇順 — DEMO 化仕様 R5）
$r1 = add_record($db, 1, new DateTimeImmutable('2026-08-07 10:00:00', $tz));
$r2 = add_record($db, 2, new DateTimeImmutable('2026-08-07 10:00:00', $tz));
$r3 = add_record($db, 3, new DateTimeImmutable('2026-08-07 11:00:00', $tz));
$ids = array_column(get_today($db, new DateTimeImmutable('2026-08-07 12:00:00', $tz))['records'], 'id');
check('T4 today order asc', array_slice($ids, -3) === [$r1['id'], $r2['id'], $r3['id']], 'ids=' . json_encode($ids));

// T8: 日付境界（23:59:59 は昨日扱い、00:00:00 は今日扱い）
add_record($db, 5, new DateTimeImmutable('2026-08-07 23:59:59', $tz));
$nextMorning = get_today($db, new DateTimeImmutable('2026-08-08 00:00:00', $tz));
$prevNight = get_today($db, new DateTimeImmutable('2026-08-07 23:59:59', $tz));
check('T8 date boundary', $nextMorning['date'] === '2026-08-08' && $nextMorning['total'] === 0 && $prevNight['total'] > 0);

// T5: 月別集計（指定月の全日 + 記録日の合計/件数 + 記録なしの日は0）
add_record($db, 3, new DateTimeImmutable('2026-08-03 12:00:00', $tz));
add_record($db, 2, new DateTimeImmutable('2026-08-03 13:00:00', $tz));
$aug = get_monthly_totals($db, 2026, 8);
$t5ok = is_array($aug)
    && count($aug['days']) === 31
    && $aug['days'][0]['date'] === '2026-08-01' && $aug['days'][0]['total'] === 0 && $aug['days'][0]['count'] === 0
    && $aug['days'][2]['date'] === '2026-08-03' && $aug['days'][2]['total'] === 5 && $aug['days'][2]['count'] === 2;
check('T5 monthly totals', $t5ok);

// T6: 月別集計（別月は含まれない）
add_record($db, 7, new DateTimeImmutable('2026-07-31 23:00:00', $tz));
add_record($db, 8, new DateTimeImmutable('2026-09-01 00:00:00', $tz));
$jul = get_monthly_totals($db, 2026, 7);
$sep = get_monthly_totals($db, 2026, 9);
check('T6 other months excluded', is_array($aug) && $aug['days'][2]['total'] === 5
    && $jul['days'][30]['total'] === 7 && $sep['days'][0]['total'] === 8);

// T7: 月別集計（パラメータ検証）
$t7ok = get_monthly_totals($db, 1999, 8) === null
    && get_monthly_totals($db, 2101, 1) === null
    && get_monthly_totals($db, 2026, 0) === null
    && get_monthly_totals($db, 2026, 13) === null
    && get_monthly_totals($db, 2026, '8') === null
    && is_array(get_monthly_totals($db, 2026, 8));
check('T7 monthly param validation', $t7ok);

// T9: 削除（正常）
$before = get_today($db, new DateTimeImmutable('2026-08-07 12:00:00', $tz))['total'];
$deleted = delete_record($db, $r1['id']);
$after = get_today($db, new DateTimeImmutable('2026-08-07 12:00:00', $tz))['total'];
check('T9 delete record', $deleted === true && $after === $before - 1);

// T10: 削除（存在しないID）
check('T10 delete nonexistent', delete_record($db, 999999) === false && delete_record($db, 'abc') === false);

// T13: 日詳細（指定日の一覧・時間昇順・合計）
$d3 = get_day($db, '2026-08-03');
$times = array_column($d3['records'], 'created_at');
check('T13 day records asc', $d3['total'] === 5 && count($d3['records']) === 2
    && $times[0] === '2026-08-03 12:00:00' && $times[1] === '2026-08-03 13:00:00');

// T14: 日詳細（記録のない日は空・形式不正も空）
$dEmpty = get_day($db, '2026-08-05');
check('T14 day empty', $dEmpty['total'] === 0 && $dEmpty['records'] === []
    && get_day($db, '2026/08/03')['total'] === 0 && get_day($db, 'abc')['total'] === 0);

// T15: 日詳細（日付境界 — 前後の日は含まない）
$d31 = get_day($db, '2026-07-31');
$d1 = get_day($db, '2026-09-01');
$dAug = get_day($db, '2026-08-03');
$allAug = count(array_filter($dAug['records'], fn($r) => str_starts_with($r['created_at'], '2026-08-03')));
check('T15 day boundary', $d31['total'] === 7 && $d1['total'] === 8
    && count($dAug['records']) === 2 && $allAug === 2);

// T16: データ更新検出（version: count と maxId）
$v0 = get_db_version($db);
$rNew = add_record($db, 4, new DateTimeImmutable('2026-08-02 10:00:00', $tz));
$v1 = get_db_version($db);
check('T16 version count/maxId', $v1['count'] === $v0['count'] + 1 && $v1['maxId'] === $rNew['id']);

// T19: 分析（2026-08: 08-02[4]/08-03[3,2]/08-06[3]/08-07[6件=3,2,1,2,3,5] → days=4 total=28 records=10 max=08-07:16 avg=7.0）
$st = get_stats($db, '2026', '08');
$t19ok = is_array($st)
    && $st['summary']['days'] === 4 && $st['summary']['total'] === 28 && $st['summary']['records'] === 10
    && $st['summary']['max_day'] === ['date' => '2026-08-07', 'total' => 16]
    && $st['summary']['avg_per_day'] === 7.0
    && $st['dow'][0] === ['dow' => 0, 'count' => 1, 'sum' => 4]   // 日曜 08-02
    && $st['dow'][1] === ['dow' => 1, 'count' => 2, 'sum' => 5]   // 月曜 08-03
    && $st['dow'][5] === ['dow' => 5, 'count' => 6, 'sum' => 16]  // 金曜 08-07
    && $st['hour'][9] === ['hour' => 9, 'count' => 4, 'sum' => 9] // 09時台: 09:00×2, 09:01, 09:02
    && $st['hour'][10] === ['hour' => 10, 'count' => 2, 'sum' => 6]
    && $st['hour'][23] === ['hour' => 23, 'count' => 1, 'sum' => 5];
check('T19 stats dow/hour/summary', $t19ok);

// T20: 年報（月別合計・全12ヶ月・2026: 7月[7,1] 8月[28,10] 9月[8,1]）
$yr = get_yearly_totals($db, 2026);
$t20ok = is_array($yr)
    && count($yr['months']) === 12
    && $yr['months'][0] === ['month' => 1, 'total' => 0, 'count' => 0]
    && $yr['months'][6] === ['month' => 7, 'total' => 7, 'count' => 1]
    && $yr['months'][7] === ['month' => 8, 'total' => 28, 'count' => 10]
    && $yr['months'][8] === ['month' => 9, 'total' => 8, 'count' => 1]
    && get_yearly_totals($db, 9999) === null;
check('T20 yearly totals', $t20ok);

// T17: 訂正 — 枚数変更（r2: 08-07 10:00 count=2 → 10・created_at 不変・今日の合計に反映）
$u1 = update_record($db, $r2['id'], 10, null);
$t17ok = is_array($u1) && $u1['ok'] === true
    && $u1['record']['count'] === 10 && $u1['record']['created_at'] === '2026-08-07 10:00:00'
    && get_day($db, '2026-08-07')['total'] === 24; // 16 - 2 + 10
check('T17 update count', $t17ok);

// T18: 訂正 — 日時変更（r3: 08-07 11:00 count=3 → 08-04 08:30:00・集計が別日に移る）
$u2 = update_record($db, $r3['id'], null, '2026-08-04 08:30:00');
$d4 = get_day($db, '2026-08-04');
$t18ok = is_array($u2) && $u2['ok'] === true
    && $u2['record']['created_at'] === '2026-08-04 08:30:00'
    && get_day($db, '2026-08-07')['total'] === 21 // 24 - 3
    && $d4['total'] === 3 && count($d4['records']) === 1 && $d4['records'][0]['created_at'] === '2026-08-04 08:30:00';
check('T18 update datetime', $t18ok);

// 訂正のバリデーション（not_found / invalid_count / invalid_datetime）
check('T19b update validation',
    update_record($db, 999999, 1, null) === ['ok' => false, 'error' => 'not_found']
    && update_record($db, $r2['id'], 0, null) === ['ok' => false, 'error' => 'invalid_count']
    && update_record($db, $r2['id'], 1000, null) === ['ok' => false, 'error' => 'invalid_count']
    && update_record($db, $r2['id'], null, '2026-08-07 10:00') === ['ok' => false, 'error' => 'invalid_datetime']);

$passCount = count(array_filter($results, fn($r) => $r['pass']));
echo "\n$passCount/" . count($results) . " passed\n";
exit($passCount === count($results) ? 0 : 1);
