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

// T4: 一覧の順序（新しい順・同刻は id 降順）
$r1 = add_record($db, 1, new DateTimeImmutable('2026-08-07 10:00:00', $tz));
$r2 = add_record($db, 2, new DateTimeImmutable('2026-08-07 10:00:00', $tz));
$r3 = add_record($db, 3, new DateTimeImmutable('2026-08-07 11:00:00', $tz));
$ids = array_column(get_today($db, new DateTimeImmutable('2026-08-07 12:00:00', $tz))['records'], 'id');
check('T4 today order desc', array_slice($ids, 0, 3) === [$r3['id'], $r2['id'], $r1['id']], 'ids=' . json_encode($ids));

// T8: 日付境界（23:59:59 は昨日扱い、00:00:00 は今日扱い）
add_record($db, 5, new DateTimeImmutable('2026-08-07 23:59:59', $tz));
$nextMorning = get_today($db, new DateTimeImmutable('2026-08-08 00:00:00', $tz));
$prevNight = get_today($db, new DateTimeImmutable('2026-08-07 23:59:59', $tz));
check('T8 date boundary', $nextMorning['date'] === '2026-08-08' && $nextMorning['total'] === 0 && $prevNight['total'] > 0);

// T5: 月別集計（指定月の全日 + 記録日の合計 + 記録なしの日は0）
add_record($db, 3, new DateTimeImmutable('2026-08-03 12:00:00', $tz));
add_record($db, 2, new DateTimeImmutable('2026-08-03 13:00:00', $tz));
$aug = get_monthly_totals($db, 2026, 8);
$t5ok = is_array($aug)
    && count($aug['days']) === 31
    && $aug['days'][0]['date'] === '2026-08-01' && $aug['days'][0]['total'] === 0
    && $aug['days'][2]['date'] === '2026-08-03' && $aug['days'][2]['total'] === 5;
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

$passCount = count(array_filter($results, fn($r) => $r['pass']));
echo "\n$passCount/" . count($results) . " passed\n";
exit($passCount === count($results) ? 0 : 1);
