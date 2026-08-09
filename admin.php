<?php
// 駐車券記録アプリ — 管理者画面（PW 保護・日別集計/日詳細編集/月報/年報/分析）
require_once __DIR__ . '/lib/config.php';
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('Referrer-Policy: no-referrer');
?><!DOCTYPE html>
<html lang="ja" data-bs-theme="auto">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>管理者 — 駐車券 記録(DEMO)</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">
<style>
.record-row{display:flex;justify-content:space-between;align-items:center;gap:.5rem;padding:.55rem 0;border-bottom:1px solid var(--bs-border-color)}
.record-row:last-child{border-bottom:none}
#a-toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);background:var(--bs-body-color);color:var(--bs-body-bg);padding:.6rem 1.2rem;border-radius:999px;font-size:.9rem;opacity:0;transition:opacity .25s;pointer-events:none;z-index:1080}
#a-toast.show{opacity:1}
</style>
</head>
<body class="bg-body-tertiary">
<div class="container" style="max-width:640px">

  <header class="d-flex justify-content-between align-items-center mt-3">
    <h1 class="h4 mb-0">管理者画面</h1>
    <a href="index.php" id="a-logout" class="btn btn-sm btn-outline-secondary">← 記録画面へ</a>
  </header>

  <div id="admin-content" hidden>
    <ul class="nav nav-pills nav-fill mt-3">
      <li class="nav-item"><button id="atab-monthly" class="nav-link active w-100">日別集計</button></li>
      <li class="nav-item"><button id="atab-mreport" class="nav-link w-100">月報</button></li>
      <li class="nav-item"><button id="atab-yreport" class="nav-link w-100">年報</button></li>
      <li class="nav-item"><button id="atab-analysis" class="nav-link w-100">分析</button></li>
    </ul>

    <!-- 日別集計 -->
    <div class="card mt-3" id="a-monthly-panel">
      <div class="card-body">
        <div class="d-flex gap-2 mb-3 flex-wrap">
          <select id="a-year" class="form-select form-select-lg"></select>
          <div class="d-flex gap-2">
            <button id="a-month-prev" type="button" class="btn btn-outline-secondary btn-lg flex-shrink-0">‹ 前月</button>
            <select id="a-month" class="form-select form-select-lg"></select>
            <button id="a-month-next" type="button" class="btn btn-outline-secondary btn-lg flex-shrink-0">翌月 ›</button>
          </div>
          <button id="a-month-btn" class="btn btn-primary btn-lg flex-shrink-0">表示</button>
        </div>
        <div class="text-danger small mb-2" id="a-month-err"></div>
        <table class="table table-sm" id="a-month-table" hidden>
          <thead><tr><th class="text-start">日付</th><th class="text-end">件数</th><th class="text-end">枚数</th></tr></thead>
          <tbody></tbody>
        </table>
        <p class="text-body-secondary small mt-2 mb-0">日付をクリックすると詳細の編集・削除ができます</p>
      </div>
    </div>

    <!-- 月報 -->
    <div class="card mt-3" id="a-mreport-panel" hidden>
      <div class="card-body">
        <div class="d-flex gap-2 mb-3">
          <select id="a-mr-year" class="form-select form-select-lg"></select>
          <select id="a-mr-month" class="form-select form-select-lg"></select>
          <button id="a-mr-btn" class="btn btn-primary btn-lg flex-shrink-0">表示</button>
        </div>
        <table class="table table-sm" id="a-mreport-table" hidden>
          <thead><tr><th class="text-start">日付</th><th class="text-end">枚数</th></tr></thead>
          <tbody></tbody>
        </table>
        <h3 class="h6 mt-3">日別合計の推移</h3>
        <div style="height:220px"><canvas id="a-mreport-chart"></canvas></div>
      </div>
    </div>

    <!-- 年報 -->
    <div class="card mt-3" id="a-yreport-panel" hidden>
      <div class="card-body">
        <div class="d-flex gap-2 mb-3">
          <select id="a-yr-year" class="form-select form-select-lg"></select>
          <button id="a-yr-btn" class="btn btn-primary btn-lg flex-shrink-0">表示</button>
        </div>
        <table class="table table-sm" id="a-yreport-table" hidden>
          <thead><tr><th class="text-start">月</th><th class="text-end">枚数</th></tr></thead>
          <tbody></tbody>
        </table>
        <h3 class="h6 mt-3">月別合計の推移</h3>
        <div style="height:220px"><canvas id="a-yreport-chart"></canvas></div>
      </div>
    </div>

    <!-- 分析 -->
    <div class="card mt-3" id="a-analysis-panel" hidden>
      <div class="card-body">
        <div class="d-flex gap-2 mb-3">
          <select id="a-an-year" class="form-select form-select-lg"></select>
          <select id="a-an-month" class="form-select form-select-lg"></select>
          <button id="a-an-btn" class="btn btn-primary btn-lg flex-shrink-0">表示</button>
        </div>
        <div id="a-analysis-empty" class="text-body-secondary text-center py-3" hidden>記録がありません</div>
        <div id="a-analysis-body">
          <div class="d-flex flex-wrap gap-3 mb-3 small">
            <span>期間: <span id="a-summary-days">-</span>日</span>
            <span>総件数: <span id="a-summary-records">-</span>件</span>
            <span>総枚数: <span id="a-summary-total">-</span>枚</span>
            <span>日別最大: <span id="a-summary-max">-</span></span>
            <span>日別平均: <span id="a-summary-avg">-</span>枚/日</span>
          </div>
          <h3 class="h6">曜日別（枚数）</h3>
          <div style="height:180px"><canvas id="a-dow-chart"></canvas></div>
          <h3 class="h6 mt-3">時間帯別（枚数）</h3>
          <div style="height:180px"><canvas id="a-hour-chart"></canvas></div>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- 管理者PWモーダル -->
<div class="modal fade" id="a-pw-dialog" tabindex="-1" aria-hidden="true">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content">
      <div class="modal-header">
        <h3 class="modal-title h6">パスワード(<?= htmlspecialchars(ADMIN_PW, ENT_QUOTES, 'UTF-8') ?>)</h3>
      </div>
      <div class="modal-body">
        <p class="text-body-secondary small mb-2">デモ用のためパスワードは形式的なものです。</p>
        <input type="password" id="a-pw" class="form-control form-control-lg text-center" inputmode="numeric"
               autocomplete="off" value="<?= htmlspecialchars(ADMIN_PW, ENT_QUOTES, 'UTF-8') ?>"
               placeholder="<?= htmlspecialchars(ADMIN_PW, ENT_QUOTES, 'UTF-8') ?>">
        <div class="text-danger small mt-2" id="a-pw-err"></div>
      </div>
      <div class="modal-footer">
        <button id="a-pw-cancel" class="btn btn-outline-secondary">キャンセル</button>
        <button id="a-pw-ok" class="btn btn-primary">確定</button>
      </div>
    </div>
  </div>
</div>

<!-- 管理者 日詳細モーダル（編集・削除あり） -->
<div class="modal fade" id="a-day-dialog" tabindex="-1" aria-hidden="true">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content">
      <div class="modal-header">
        <h3 class="modal-title h6" id="a-day-title"></h3>
        <button type="button" class="btn-close" id="a-day-close" aria-label="閉じる"></button>
      </div>
      <div class="modal-body">
        <div id="a-day-list"></div>
      </div>
    </div>
  </div>
</div>

<!-- 管理者 編集モーダル -->
<div class="modal fade" id="a-edit-dialog" tabindex="-1" aria-hidden="true">
  <div class="modal-dialog modal-dialog-centered">
    <div class="modal-content">
      <div class="modal-header">
        <h3 class="modal-title h6">記録を編集</h3>
      </div>
      <div class="modal-body">
        <label class="form-label" for="a-edit-count">枚数（1〜999）</label>
        <input type="number" id="a-edit-count" class="form-control" min="1" max="999" inputmode="numeric">
        <label class="form-label mt-2" for="a-edit-datetime">日時</label>
        <input type="datetime-local" id="a-edit-datetime" class="form-control">
        <div class="text-danger small mt-2" id="a-edit-err"></div>
      </div>
      <div class="modal-footer">
        <button id="a-edit-cancel" class="btn btn-outline-secondary">キャンセル</button>
        <button id="a-edit-ok" class="btn btn-primary">保存</button>
      </div>
    </div>
  </div>
</div>

<div id="a-toast"></div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
<script>
'use strict';
const $ = id => document.getElementById(id);

function toast(msg) {
  const t = $('a-toast');
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

// ---------- 認証 ----------
const aPwModal = new bootstrap.Modal($('a-pw-dialog'), { backdrop: 'static', keyboard: false });

$('a-pw-dialog').addEventListener('shown.bs.modal', () => $('a-pw').focus());

async function submitAdminPw() {
  const { status } = await api('POST', 'login', { pw: $('a-pw').value });
  if (status === 200) {
    $('a-pw-err').textContent = '';
    if ($('a-pw-dialog').classList.contains('show')) aPwModal.hide();
    showContent();
  } else {
    $('a-pw-err').textContent = 'パスワードが違います';
  }
}

$('a-pw-ok').addEventListener('click', submitAdminPw);
$('a-pw-cancel').addEventListener('click', () => aPwModal.hide());
$('a-pw').addEventListener('keydown', e => { if (e.key === 'Enter') submitAdminPw(); });

// 「記録画面へ」= ログアウト（確認なし）: セッション破棄後に記録画面へ遷移
$('a-logout').addEventListener('click', async e => {
  e.preventDefault();
  try { await fetch('api.php?action=logout', { method: 'POST' }); } catch (err) { /* 遷移を妨げない */ }
  location.href = 'index.php';
});

// ---------- タブ ----------
const TABS = {
  monthly: ['atab-monthly', 'a-monthly-panel'],
  mreport: ['atab-mreport', 'a-mreport-panel'],
  yreport: ['atab-yreport', 'a-yreport-panel'],
  analysis: ['atab-analysis', 'a-analysis-panel'],
};
let activeTab = 'monthly';

function activateTab(name) {
  activeTab = name;
  for (const [key, [tabId, panelId]] of Object.entries(TABS)) {
    $(tabId).classList.toggle('active', key === name);
    $(panelId).hidden = key !== name;
  }
}

function populateYears(selectId) {
  const sel = $(selectId);
  const nowYear = new Date().getFullYear();
  for (let y = nowYear; y >= nowYear - 10; y--) {
    const opt = document.createElement('option');
    opt.value = y; opt.textContent = y + '年';
    if (y === nowYear) opt.selected = true;
    sel.append(opt);
  }
}

function populateMonths(selectId, withAll) {
  const sel = $(selectId);
  const nowMonth = new Date().getMonth() + 1;
  if (withAll) {
    const all = document.createElement('option');
    all.value = ''; all.textContent = '年間';
    sel.append(all);
  }
  for (let m = 1; m <= 12; m++) {
    const opt = document.createElement('option');
    opt.value = m; opt.textContent = m + '月';
    if (m === nowMonth) opt.selected = true;
    sel.append(opt);
  }
}

populateYears('a-year'); populateMonths('a-month');
populateYears('a-mr-year'); populateMonths('a-mr-month');
populateYears('a-yr-year');
populateYears('a-an-year'); populateMonths('a-an-month', true);

// ---------- 日別集計 ----------
let monthlyToken = 0;
async function renderMonthly() {
  const token = ++monthlyToken;
  const { status, data } = await api('GET', 'monthly&year=' + $('a-year').value + '&month=' + $('a-month').value);
  if (token !== monthlyToken) return; // 連続操作時は古い応答を破棄
  if (status === 400) { $('a-month-err').textContent = '指定が不正です'; return; }
  $('a-month-err').textContent = '';
  const tbody = $('a-month-table').querySelector('tbody');
  tbody.textContent = '';
  let sumCount = 0, sumTotal = 0;
  for (const d of data.days) {
    sumCount += d.count; sumTotal += d.total;
    const tr = document.createElement('tr');
    const tdDate = document.createElement('td');
    tdDate.className = 'text-start a-day-link text-primary';
    tdDate.textContent = d.date.slice(5);
    tdDate.style.cursor = 'pointer';
    tdDate.style.textDecoration = 'underline';
    tdDate.addEventListener('click', () => openAdminDayDetail(d.date));
    const tdCount = document.createElement('td');
    tdCount.className = 'text-end';
    tdCount.textContent = d.count;
    const tdTotal = document.createElement('td');
    tdTotal.className = 'text-end';
    tdTotal.textContent = d.total;
    tr.append(tdDate, tdCount, tdTotal);
    tbody.append(tr);
  }
  const tr = document.createElement('tr');
  const tdDate = document.createElement('td');
  tdDate.className = 'text-start fw-bold';
  tdDate.textContent = '合計';
  const tdCount = document.createElement('td');
  tdCount.className = 'text-end fw-bold';
  tdCount.textContent = sumCount;
  const tdTotal = document.createElement('td');
  tdTotal.className = 'text-end fw-bold';
  tdTotal.textContent = sumTotal;
  tr.append(tdDate, tdCount, tdTotal);
  tbody.append(tr);
  $('a-month-table').hidden = false;
}

$('a-month-btn').addEventListener('click', renderMonthly);
$('a-year').addEventListener('change', renderMonthly);
$('a-month').addEventListener('change', renderMonthly);

// 前月/翌月（年跨ぎ自動・セレクト範囲外は移動しない）
function shiftMonth(delta) {
  let y = parseInt($('a-year').value, 10);
  let m = parseInt($('a-month').value, 10) + delta;
  if (m < 1) { m = 12; y--; }
  if (m > 12) { m = 1; y++; }
  if (!$('a-year').querySelector('option[value="' + y + '"]')) return;
  $('a-year').value = y;
  $('a-month').value = m;
  renderMonthly();
}
$('a-month-prev').addEventListener('click', () => shiftMonth(-1));
$('a-month-next').addEventListener('click', () => shiftMonth(1));

// ---------- 日詳細（編集・削除） ----------
const aDayModal = new bootstrap.Modal($('a-day-dialog'), { backdrop: 'static', keyboard: false });
let aDayModalVisible = false;
$('a-day-dialog').addEventListener('shown.bs.modal', () => { aDayModalVisible = true; });
$('a-day-dialog').addEventListener('hidden.bs.modal', () => { aDayModalVisible = false; });
$('a-day-close').addEventListener('click', () => aDayModal.hide());

async function openAdminDayDetail(date) {
  await renderAdminDayDetail(date);
  if (!aDayModalVisible) aDayModal.show();
}

async function renderAdminDayDetail(date) {
  const { status, data } = await api('GET', 'day&date=' + date);
  if (status !== 200) { toast('読み込みに失敗しました'); return; }
  const dt = new Date(date + 'T00:00:00');
  $('a-day-title').textContent = `${dt.getMonth() + 1}月${dt.getDate()}日（${data.records.length}件・${data.total}枚）`;
  const list = $('a-day-list');
  list.textContent = '';
  if (data.records.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'text-body-secondary text-center py-3';
    empty.textContent = '記録がありません';
    list.append(empty);
    return;
  }
  for (const r of data.records) {
    const row = document.createElement('div');
    row.className = 'record-row';
    const time = document.createElement('span');
    time.className = 'text-body-secondary small';
    time.textContent = r.created_at.slice(11, 16);
    const mid = document.createElement('span');
    mid.className = 'fw-semibold';
    mid.textContent = r.count + ' 枚';
    const btns = document.createElement('span');
    btns.className = 'd-flex gap-2 flex-shrink-0';
    const edit = document.createElement('button');
    edit.className = 'edit btn btn-sm btn-outline-primary';
    edit.textContent = '編集';
    edit.addEventListener('click', () => openEditDialog(r, date));
    const del = document.createElement('button');
    del.className = 'del btn btn-sm btn-outline-danger';
    del.textContent = '削除';
    del.addEventListener('click', () => deleteAdminRecord(r.id, date));
    btns.append(edit, del);
    row.append(time, mid, btns);
    list.append(row);
  }
}

// ---------- 編集 ----------
const aEditModal = new bootstrap.Modal($('a-edit-dialog'), { backdrop: 'static', keyboard: false });
let editingId = null, editingDate = null;

function openEditDialog(record, date) {
  editingId = record.id;
  editingDate = date;
  $('a-edit-count').value = record.count;
  $('a-edit-datetime').value = record.created_at.slice(0, 16).replace(' ', 'T');
  $('a-edit-err').textContent = '';
  aEditModal.show();
}

async function saveEdit() {
  const count = parseInt($('a-edit-count').value, 10);
  if (!Number.isInteger(count) || count < 1 || count > 999) {
    $('a-edit-err').textContent = '枚数は1〜999で入力してください';
    return;
  }
  const body = { id: editingId, count };
  const dt = $('a-edit-datetime').value;
  if (dt) body.created_at = dt.replace('T', ' ');
  const { status } = await api('POST', 'update', body);
  if (status === 200) {
    $('a-edit-err').textContent = '';
    aEditModal.hide();
    toast('保存しました');
    await renderAdminDayDetail(editingDate);
    await renderMonthly();
  } else if (status === 400) {
    $('a-edit-err').textContent = '入力が正しくありません';
  } else if (status === 404) {
    $('a-edit-err').textContent = '既に削除されています';
  } else {
    $('a-edit-err').textContent = 'エラーが発生しました';
  }
}

$('a-edit-ok').addEventListener('click', saveEdit);
$('a-edit-cancel').addEventListener('click', () => aEditModal.hide());

// ---------- 削除 ----------
async function deleteAdminRecord(id, date) {
  const { status } = await api('DELETE', 'delete&id=' + id);
  if (status === 204) { toast('削除しました'); }
  else if (status === 404) { toast('既に削除済みです'); }
  else { toast('エラーが発生しました'); return; }
  await renderAdminDayDetail(date);
  await renderMonthly();
}

// ---------- グラフ ----------
const charts = {};
function drawChart(key, canvasId, labels, data, label) {
  if (charts[key]) charts[key].destroy();
  charts[key] = new Chart($(canvasId), {
    type: 'bar',
    data: { labels, datasets: [{ label, data, backgroundColor: 'rgba(13,110,253,0.75)' }] },
    options: {
      maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: { y: { beginAtZero: true } },
    },
  });
}

// ---------- 月報 ----------
let mreportToken = 0;
async function renderMonthlyReport() {
  const token = ++mreportToken;
  const { status, data } = await api('GET', 'monthly&year=' + $('a-mr-year').value + '&month=' + $('a-mr-month').value);
  if (token !== mreportToken) return; // 連続操作時は古い応答を破棄
  if (status !== 200) return;
  const tbody = $('a-mreport-table').querySelector('tbody');
  tbody.textContent = '';
  let sumTotal = 0;
  const labels = [], totals = [];
  for (const d of data.days) {
    sumTotal += d.total;
    const tr = document.createElement('tr');
    const tdDate = document.createElement('td');
    tdDate.className = 'text-start';
    tdDate.textContent = d.date.slice(5);
    const tdTotal = document.createElement('td');
    tdTotal.className = 'text-end';
    tdTotal.textContent = d.total;
    tr.append(tdDate, tdTotal);
    tbody.append(tr);
    labels.push(d.date.slice(5));
    totals.push(d.total);
  }
  const tr = document.createElement('tr');
  const tdDate = document.createElement('td');
  tdDate.className = 'text-start fw-bold';
  tdDate.textContent = '合計';
  const tdTotal = document.createElement('td');
  tdTotal.className = 'text-end fw-bold';
  tdTotal.textContent = sumTotal;
  tr.append(tdDate, tdTotal);
  tbody.append(tr);
  $('a-mreport-table').hidden = false;
  drawChart('mreport', 'a-mreport-chart', labels, totals, '枚数');
}

// ---------- 年報 ----------
let yreportToken = 0;
async function renderYearlyReport() {
  const token = ++yreportToken;
  const { status, data } = await api('GET', 'yearly&year=' + $('a-yr-year').value);
  if (token !== yreportToken) return; // 連続操作時は古い応答を破棄
  if (status !== 200) return;
  const tbody = $('a-yreport-table').querySelector('tbody');
  tbody.textContent = '';
  let sumTotal = 0;
  const labels = [], totals = [];
  for (const m of data.months) {
    sumTotal += m.total;
    const tr = document.createElement('tr');
    const tdMonth = document.createElement('td');
    tdMonth.className = 'text-start';
    tdMonth.textContent = m.month + '月';
    const tdTotal = document.createElement('td');
    tdTotal.className = 'text-end';
    tdTotal.textContent = m.total;
    tr.append(tdMonth, tdTotal);
    tbody.append(tr);
    labels.push(m.month + '月');
    totals.push(m.total);
  }
  const tr = document.createElement('tr');
  const tdMonth = document.createElement('td');
  tdMonth.className = 'text-start fw-bold';
  tdMonth.textContent = '合計';
  const tdTotal = document.createElement('td');
  tdTotal.className = 'text-end fw-bold';
  tdTotal.textContent = sumTotal;
  tr.append(tdMonth, tdTotal);
  tbody.append(tr);
  $('a-yreport-table').hidden = false;
  drawChart('yreport', 'a-yreport-chart', labels, totals, '枚数');
}

// ---------- 分析 ----------
let analysisToken = 0;
async function renderAnalysis() {
  const token = ++analysisToken;
  const year = $('a-an-year').value;
  const month = $('a-an-month').value;
  const { status, data } = await api('GET', 'stats&year=' + year + '&month=' + month);
  if (token !== analysisToken) return; // 連続操作時は古い応答を破棄
  if (status !== 200) return;
  const empty = data.summary.total === 0;
  $('a-analysis-empty').hidden = !empty;
  $('a-analysis-body').hidden = empty;
  if (empty) return;
  $('a-summary-days').textContent = data.summary.days;
  $('a-summary-records').textContent = data.summary.records;
  $('a-summary-total').textContent = data.summary.total;
  $('a-summary-max').textContent = data.summary.max_day ? `${data.summary.max_day.date.slice(5)}（${data.summary.max_day.total}枚）` : '-';
  $('a-summary-avg').textContent = data.summary.avg_per_day;
  const dowLabels = ['日', '月', '火', '水', '木', '金', '土'];
  drawChart('dow', 'a-dow-chart', dowLabels, data.dow.map(d => d.sum), '枚数');
  const hourLabels = Array.from({ length: 24 }, (_, i) => i + '時');
  drawChart('hour', 'a-hour-chart', hourLabels, data.hour.map(h => h.sum), '枚数');
}

// ---------- タブ切替・初期化 ----------
function bindTab(tabId, name, renderFn) {
  $(tabId).addEventListener('click', () => {
    activateTab(name);
    renderFn();
  });
}
bindTab('atab-monthly', 'monthly', renderMonthly);
bindTab('atab-mreport', 'mreport', renderMonthlyReport);
bindTab('atab-yreport', 'yreport', renderYearlyReport);
bindTab('atab-analysis', 'analysis', renderAnalysis);
$('a-mr-btn').addEventListener('click', renderMonthlyReport);
$('a-mr-year').addEventListener('change', renderMonthlyReport);
$('a-mr-month').addEventListener('change', renderMonthlyReport);
$('a-yr-btn').addEventListener('click', renderYearlyReport);
$('a-yr-year').addEventListener('change', renderYearlyReport);
$('a-an-btn').addEventListener('click', renderAnalysis);
$('a-an-year').addEventListener('change', renderAnalysis);
$('a-an-month').addEventListener('change', renderAnalysis);

async function showContent() {
  $('admin-content').hidden = false;
  activateTab('monthly');
  await renderMonthly();
}

(async () => {
  const { status } = await api('GET', 'auth');
  if (status === 200) { showContent(); }
  else { aPwModal.show(); }
})();
</script>
</body>
</html>
