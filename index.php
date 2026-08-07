<?php
// 駐車券記録アプリ — 単一ページUI（モバイルファースト・Bootstrap 5.3.3 CDN）
require_once __DIR__ . '/lib/config.php';
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('Referrer-Policy: no-referrer');
?><!DOCTYPE html>
<html lang="ja" data-bs-theme="auto">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>駐車券 記録(DEMO)</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">
<style>
body{padding-bottom:60px}
.today-total .num{font-size:3.2rem;font-weight:700;line-height:1.1}
.record-row{display:flex;justify-content:space-between;align-items:center;padding:.55rem 0;border-bottom:1px solid var(--bs-border-color)}
.record-row:last-child{border-bottom:none}
#toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);background:var(--bs-body-color);color:var(--bs-body-bg);padding:.6rem 1.2rem;border-radius:999px;font-size:.9rem;opacity:0;transition:opacity .25s;pointer-events:none;z-index:1080}
#toast.show{opacity:1}
</style>
</head>
<body class="bg-body-tertiary">
<div class="container" style="max-width:560px">

  <header class="d-flex justify-content-between align-items-baseline mt-3">
    <h1 class="h4 mb-0">駐車券 記録(DEMO)</h1>
    <span id="today-date" class="text-body-secondary small"></span>
  </header>

  <div class="card mt-3 text-center">
    <div class="card-body py-4">
      <div class="text-body-secondary">今日の合計</div>
      <div class="today-total"><span class="num" id="today-total">0</span> <span class="text-body-secondary">枚</span></div>
    </div>
  </div>

  <div class="card mt-3">
    <div class="card-body d-flex gap-2">
      <input type="number" id="count" value="1" min="1" max="999" inputmode="numeric"
             class="form-control form-control-lg text-center" aria-label="枚数">
      <button id="add-btn" class="btn btn-primary btn-lg px-4 flex-shrink-0">記録する</button>
    </div>
  </div>

  <ul class="nav nav-pills nav-fill mt-3">
    <li class="nav-item"><button id="tab-today" class="nav-link active w-100">今日の記録</button></li>
    <li class="nav-item"><button id="tab-month" class="nav-link w-100">日別集計</button></li>
  </ul>

  <div class="card mt-3" id="panel-today">
    <div class="card-body">
      <h2 class="h6 mb-3">今日の記録</h2>
      <div id="today-list"></div>
    </div>
  </div>

  <div class="card mt-3" id="panel-month" hidden>
    <div class="card-body">
      <h2 class="h6 mb-3">日別集計</h2>
      <div class="d-flex gap-2 mb-3">
        <select id="year" class="form-select form-select-lg"></select>
        <select id="month" class="form-select form-select-lg"></select>
        <button id="month-btn" class="btn btn-primary btn-lg flex-shrink-0">表示</button>
      </div>
      <div class="text-danger small mb-2" id="month-err"></div>
      <table class="table table-sm" id="month-table" hidden>
        <thead><tr><th class="text-start">日付</th><th class="text-end">枚数</th></tr></thead>
        <tbody></tbody>
      </table>
    </div>
  </div>
</div>

<!-- PWモーダル -->
<div class="modal fade" id="pw-dialog" tabindex="-1" aria-hidden="true">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content">
      <div class="modal-header">
        <h3 class="modal-title h6">パスワード(<?= htmlspecialchars(ADMIN_PW, ENT_QUOTES, 'UTF-8') ?>)</h3>
      </div>
      <div class="modal-body">
        <p class="text-body-secondary small mb-2">デモ用のためパスワードは形式的なものです。</p>
        <input type="password" id="pw" class="form-control form-control-lg text-center" inputmode="numeric"
               autocomplete="off" value="<?= htmlspecialchars(ADMIN_PW, ENT_QUOTES, 'UTF-8') ?>"
               placeholder="<?= htmlspecialchars(ADMIN_PW, ENT_QUOTES, 'UTF-8') ?>">
        <div class="text-danger small mt-2" id="pw-err"></div>
      </div>
      <div class="modal-footer">
        <button id="pw-cancel" class="btn btn-outline-secondary">キャンセル</button>
        <button id="pw-ok" class="btn btn-primary">確定</button>
      </div>
    </div>
  </div>
</div>

<!-- 日詳細モーダル -->
<div class="modal fade" id="day-dialog" tabindex="-1" aria-hidden="true">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content">
      <div class="modal-header">
        <h3 class="modal-title h6" id="day-title"></h3>
        <button type="button" class="btn-close" id="day-close" aria-label="閉じる"></button>
      </div>
      <div class="modal-body">
        <div id="day-list"></div>
      </div>
    </div>
  </div>
</div>

<div id="toast"></div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
<script>
'use strict';
const $ = id => document.getElementById(id);

function toast(msg) {
  const t = $('toast');
  t.textContent = msg;
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 1800);
}

async function api(method, action, body) {
  const opts = { method, headers: {} };
  if (body !== undefined) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  const res = await fetch('api.php?action=' + action, opts);
  let data = null;
  try { data = await res.json(); } catch (e) { /* 204等 */ }
  return { status: res.status, data };
}

const pwModal = new bootstrap.Modal($('pw-dialog'), { backdrop: 'static', keyboard: false });
let pendingAuthAction = null;

function showPwDialog(afterAuth) {
  pendingAuthAction = afterAuth;
  $('pw').value = $('pw').defaultValue;
  $('pw-err').textContent = '';
  pwModal.show();
}
$('pw-dialog').addEventListener('shown.bs.modal', () => $('pw').focus());

async function submitPw() {
  const { status } = await api('POST', 'login', { pw: $('pw').value });
  if (status === 200) {
    pwModal.hide();
    const action = pendingAuthAction;
    pendingAuthAction = null;
    if (action) await action();
  } else {
    $('pw-err').textContent = 'パスワードが違います';
  }
}

$('pw-ok').addEventListener('click', submitPw);
$('pw-cancel').addEventListener('click', () => {
  pwModal.hide();
  pendingAuthAction = null;
});
$('pw').addEventListener('keydown', e => { if (e.key === 'Enter') submitPw(); });

const dayModal = new bootstrap.Modal($('day-dialog'), { backdrop: 'static', keyboard: false });
let dayModalVisibleDate = null;
$('day-dialog').addEventListener('hidden.bs.modal', () => { dayModalVisibleDate = null; });
$('day-close').addEventListener('click', () => dayModal.hide());

async function openDayDetail(date) {
  const { status, data } = await api('GET', 'day&date=' + date);
  if (status === 401) { showPwDialog(() => openDayDetail(date)); return; }
  if (status !== 200) { toast('読み込みに失敗しました'); return; }
  const dt = new Date(date + 'T00:00:00');
  $('day-title').textContent = `${dt.getMonth() + 1}月${dt.getDate()}日（${data.records.length}件・${data.total}枚）`;
  const list = $('day-list');
  list.textContent = '';
  if (data.records.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'text-body-secondary text-center py-3';
    empty.textContent = '記録がありません';
    list.append(empty);
  } else {
    for (const r of data.records) {
      const row = document.createElement('div');
      row.className = 'record-row';
      const time = document.createElement('span');
      time.className = 'text-body-secondary small';
      time.textContent = r.created_at.slice(11, 16);
      const mid = document.createElement('span');
      mid.className = 'fw-semibold';
      mid.textContent = r.count + ' 枚';
      row.append(time, mid);
      list.append(row);
    }
  }
  dayModalVisibleDate = date;
  dayModal.show();
}

function rowNode(r) {
  const row = document.createElement('div');
  row.className = 'record-row';
  const time = document.createElement('span');
  time.className = 'text-body-secondary small';
  time.textContent = r.created_at.slice(11, 16);
  const mid = document.createElement('span');
  mid.className = 'fw-semibold';
  mid.textContent = r.count + ' 枚';
  const del = document.createElement('button');
  del.className = 'del btn btn-sm btn-outline-danger';
  del.textContent = '削除';
  del.addEventListener('click', () => {
    const doDelete = async () => {
      const { status } = await api('DELETE', 'delete&id=' + r.id);
      if (status === 204) { toast('削除しました'); await loadToday(); }
      else if (status === 401) { showPwDialog(doDelete); }
      else if (status === 404) { toast('既に削除済みです'); await loadToday(); }
    };
    doDelete();
  });
  row.append(time, mid, del);
  return row;
}

async function loadToday() {
  const { status, data } = await api('GET', 'today');
  if (status !== 200) { return; }
  $('today-total').textContent = String(data.total);
  const list = $('today-list');
  list.textContent = '';
  if (data.records.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'text-body-secondary text-center py-3';
    empty.textContent = 'まだ記録がありません';
    list.append(empty);
    return;
  }
  data.records.forEach(r => list.append(rowNode(r)));
}

$('add-btn').addEventListener('click', async () => {
  const v = parseInt($('count').value, 10);
  if (!Number.isInteger(v) || v < 1 || v > 999) { toast('枚数は1〜999で入力してください'); return; }
  const { status } = await api('POST', 'add', { count: v });
  if (status === 201) {
    $('count').value = '1'; toast('記録しました');
    await loadToday();
    if (!$('panel-month').hidden) await loadMonthly();
    if (dayModalVisibleDate !== null) await openDayDetail(dayModalVisibleDate);
  }
  else if (status === 400) { toast('枚数は1〜999で入力してください'); }
  else { toast('エラーが発生しました'); }
});

// 日別集計
const now = new Date();
for (let y = now.getFullYear(); y >= now.getFullYear() - 10; y--) {
  const opt = document.createElement('option');
  opt.value = y; opt.textContent = y + '年';
  if (y === now.getFullYear()) opt.selected = true;
  $('year').append(opt);
}
for (let m = 1; m <= 12; m++) {
  const opt = document.createElement('option');
  opt.value = m; opt.textContent = m + '月';
  if (m === now.getMonth() + 1) opt.selected = true;
  $('month').append(opt);
}

async function loadMonthly() {
  const { status, data } = await api('GET', 'monthly&year=' + $('year').value + '&month=' + $('month').value);
  if (status === 401) { showPwDialog(loadMonthly); return; }
  if (status === 400) { $('month-err').textContent = '指定が不正です'; return; }
  $('month-err').textContent = '';
  const tbody = $('month-table').querySelector('tbody');
  tbody.textContent = '';
  let grand = 0;
  for (const d of data.days) {
    grand += d.total;
    const tr = document.createElement('tr');
    const tdDate = document.createElement('td');
    tdDate.className = 'text-start day-link text-primary';
    tdDate.textContent = d.date.slice(5);
    tdDate.style.cursor = 'pointer';
    tdDate.style.textDecoration = 'underline';
    tdDate.addEventListener('click', () => openDayDetail(d.date));
    const tdTotal = document.createElement('td');
    tdTotal.className = 'text-end';
    tdTotal.textContent = d.total;
    tr.append(tdDate, tdTotal);
    tbody.append(tr);
  }
  const tr = document.createElement('tr');
  const tdDate = document.createElement('td');
  tdDate.className = 'text-start fw-bold';
  tdDate.textContent = '合計';
  const tdTotal = document.createElement('td');
  tdTotal.className = 'text-end fw-bold';
  tdTotal.textContent = grand;
  tr.append(tdDate, tdTotal);
  tbody.append(tr);
  $('month-table').hidden = false;
}

$('month-btn').addEventListener('click', loadMonthly);
$('tab-today').addEventListener('click', () => {
  $('tab-today').classList.add('active');
  $('tab-month').classList.remove('active');
  $('panel-today').hidden = false;
  $('panel-month').hidden = true;
});
$('tab-month').addEventListener('click', () => {
  $('tab-month').classList.add('active');
  $('tab-today').classList.remove('active');
  $('panel-today').hidden = true;
  $('panel-month').hidden = false;
});

$('today-date').textContent = new Date().toLocaleDateString('ja-JP', { year: 'numeric', month: 'long', day: 'numeric', weekday: 'short' });
loadToday();

// 自動更新チェック: 60 秒ごとに version を取得し、変化があれば表示中のパネルを最新化
let lastVersion = null;
async function checkVersion() {
  const { status, data } = await api('GET', 'version');
  if (status !== 200) return;
  const sig = data.count + ':' + data.maxId;
  if (lastVersion !== null && lastVersion !== sig) {
    await loadToday();
    if (!$('panel-month').hidden) await loadMonthly();
    if (dayModalVisibleDate !== null) await openDayDetail(dayModalVisibleDate);
  }
  lastVersion = sig;
}
window.__refreshNow = checkVersion;
setInterval(checkVersion, 60000);
checkVersion();
</script>
</body>
</html>
