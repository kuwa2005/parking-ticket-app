<?php
// デモデータ投入スクリプト（DEMO 化仕様 §2）
// 使用: php scripts/seed_demo.php        … 既定 data/parking.db へ投入
//       PARK_DB_PATH=/tmp/x.db php scripts/seed_demo.php  … 任意のDBへ投入
// 統計（本番実測と一致）: 401件 / 2026-06-01〜2026-08-07（68日）/ 各記録 count=1
//   日ごと 5〜10件・中央値5 / 時刻 09:00〜17:05（同一日・同一分の重複なし）
// 範囲内（2026-06-01〜08-07）の既存データは差し替え。範囲外は温存。冪等。

require_once __DIR__ . '/../lib/db.php';

$start = new DateTimeImmutable('2026-06-01', new DateTimeZone(APP_TZ));
$end   = new DateTimeImmutable('2026-08-07', new DateTimeZone(APP_TZ));
$days  = (int)$start->diff($end)->days + 1; // 68

// 日ごとの件数（決定的・中央値5・範囲5〜10・合計401）: 35日=5件 / 5日=6件 / 28日=7件
$counts = array_merge(
    array_fill(0, 35, 5),  // 175
    array_fill(0, 5, 6),   //  30 → 205
    array_fill(0, 28, 7)   // 196 → 401
);
mt_srand(20260807); // 決定的シャッフル（同じ結果を再現）
$order = range(0, $days - 1);
shuffle($order);
$perDay = array_fill(0, $days, 0);
foreach ($counts as $i => $c) { $perDay[$order[$i]] = $c; }

// 分プール（09:00〜17:05）: 485 分
$minutePool = [];
for ($h = 9; $h <= 17; $h++) {
    for ($m = 0; $m < 60; $m++) {
        if ($h === 17 && $m > 5) { break; }
        $minutePool[] = sprintf('%02d:%02d', $h, $m);
    }
}

$pdo = db_open();
$pdo->beginTransaction();
$del = $pdo->prepare('DELETE FROM records WHERE created_at >= ? AND created_at < ?');
$del->execute([$start->format('Y-m-d') . ' 00:00:00', $end->modify('+1 day')->format('Y-m-d') . ' 00:00:00']);
$ins = $pdo->prepare('INSERT INTO records (count, created_at) VALUES (1, ?)');
$total = 0;
for ($d = 0; $d < $days; $d++) {
    $date = $start->modify('+' . $d . ' days')->format('Y-m-d');
    $slots = $minutePool;
    shuffle($slots);
    $times = [];
    for ($i = 0; $i < $perDay[$d]; $i++) {
        $times[] = $slots[$i] . ':' . str_pad((string)mt_rand(0, 59), 2, '0', STR_PAD_LEFT);
    }
    sort($times);
    foreach ($times as $t) {
        $ins->execute([$date . ' ' . $t]);
        $total++;
    }
}
$pdo->commit();
printf("投入完了: %d 件 / %d 日（%s〜%s） → %s\n", $total, $days, $start->format('Y-m-d'), $end->format('Y-m-d'), DB_PATH);
