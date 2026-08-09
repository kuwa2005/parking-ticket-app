// 駐車券記録アプリ UI E2Eテスト（ヘッドレスChromium + CDP、外部依存なし）
// 実行: node tests/e2e_ui.mjs
// 前提: PHPサーバーがポート4500で稼働中（PARK_DB_PATHで一時DBを使用）
// メイン画面: 記録・今日一覧・削除(PW)・カレンダー過去閲覧・自動更新
// 管理者画面(admin.php): PWダイアログ・日別集計・日詳細編集/削除・月報・分析

const BASE = 'http://127.0.0.1:4500';
const CDP_HTTP = 'http://127.0.0.1:9222';
const CHROME = process.env.CHROME_BIN || 'google-chrome';

let results = [];
function check(name, cond, detail = '') {
  results.push(cond);
  console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`);
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

setTimeout(() => { console.log('WATCHDOG: 120s timeout'); process.exit(3); }, 120000);

async function findPageTarget() {
  for (let i = 0; i < 50; i++) {
    try {
      const list = await (await fetch(CDP_HTTP + '/json/list')).json();
      const page = list.find(t => t.type === 'page');
      if (page) return page;
    } catch (e) { /* not up yet */ }
    await sleep(200);
  }
  throw new Error('CDP page target not found');
}

let msgId = 0;
const pending = new Map();
function connect(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    ws.onopen = () => resolve(ws);
    ws.onerror = e => reject(new Error('ws error'));
  });
}

async function main() {
  let ws;
  try {
    const target = await findPageTarget();
    ws = await connect(target.webSocketDebuggerUrl);
    console.log('connected to existing chrome');
  } catch (e) {
    console.log('launching chrome...');
    const { spawn } = await import('node:child_process');
    const proc = spawn(CHROME, [
      '--headless=new', '--no-sandbox', '--disable-dev-shm-usage',
      '--remote-debugging-port=9222', '--user-data-dir=/tmp/park_chrome',
      'about:blank',
    ], { stdio: 'ignore', detached: true });
    proc.unref();
    const target = await findPageTarget();
    ws = await connect(target.webSocketDebuggerUrl);
  }

  ws.onmessage = ev => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
    }
  };

  function send(method, params = {}) {
    return new Promise((resolve, reject) => {
      const id = ++msgId;
      pending.set(id, { resolve, reject });
      ws.send(JSON.stringify({ id, method, params }));
    });
  }

  const pageErrors = [];
  await send('Runtime.enable');
  ws.addEventListener('message', ev => {
    const msg = JSON.parse(ev.data);
    if (msg.method === 'Runtime.exceptionThrown') {
      pageErrors.push('EXC: ' + (msg.params.exceptionDetails?.exception?.description || JSON.stringify(msg.params.exceptionDetails)).slice(0, 300));
    }
    if (msg.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].includes(msg.params.type)) {
      pageErrors.push('CONSOLE[' + msg.params.type + ']: ' + (msg.params.args || []).map(a => a.value || a.description || '').join(' ').slice(0, 300));
    }
  });

  // 前回実行の残存セッション（認証済みcookie）を無効化し、決定的な状態から開始する
  await send('Network.enable');
  await send('Network.clearBrowserCookies');

  async function evaluate(expression) {
    const res = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    if (res.exceptionDetails) throw new Error('eval failed: ' + JSON.stringify(res.exceptionDetails));
    return res.result.value;
  }

  async function waitFor(expr, timeoutMs = 6000) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      if (await evaluate(expr)) return true;
      await sleep(100);
    }
    return false;
  }

  // ---------- メイン画面 ----------
  await send('Page.navigate', { url: BASE + '/' });
  if (!(await waitFor("document.getElementById('today-total') !== null"))) {
    throw new Error('page did not load');
  }
  await waitFor("document.getElementById('today-list').children.length > 0");

  // E1: 初期状態（一時DBなので total=0・空メッセージ・管理者リンク）
  check('E1 initial total 0', (await evaluate("document.getElementById('today-total').textContent")) === '0');
  check('E1 empty message', await evaluate("document.getElementById('today-list').textContent.includes('まだ記録がありません')"));
  check('E1 admin link', await evaluate("document.querySelector('a[href=\"admin.php\"]') !== null"));

  // E2: count=3 を記録 → total=3、行が1件
  await evaluate("document.getElementById('count').value = '3';");
  await evaluate("document.getElementById('add-btn').click();");
  check('E2 total=3', await waitFor("document.getElementById('today-total').textContent === '3'"));
  check('E2 one row', (await evaluate("document.querySelectorAll('#today-list .record-row').length")) === 1);
  check('E2 row shows 3枚', await evaluate("document.querySelector('#today-list .record-row').textContent.includes('3 枚')"));

  // E3: count=2 を追加 → total=5、行2件
  await evaluate("document.getElementById('count').value = '2';");
  await evaluate("document.getElementById('add-btn').click();");
  check('E3 total=5', await waitFor("document.getElementById('today-total').textContent === '5'"));
  check('E3 two rows', (await evaluate("document.querySelectorAll('#today-list .record-row').length")) === 2);

  const md = await evaluate("(() => { const n = new Date(); return String(n.getMonth()+1).padStart(2,'0') + '-' + String(n.getDate()).padStart(2,'0'); })()");

  // E4: 画面上部の本日日付クリック → カレンダーが開く（PWなし公開）・今日のセルにバッジ5
  await evaluate("document.getElementById('today-date').click();");
  check('E4 calendar dialog opens', await waitFor("document.getElementById('calendar-dialog')?.classList.contains('show')"));
  check('E4 today cell badge 5', await waitFor(`(() => { const cell = [...document.querySelectorAll('#cal-grid .cal-cell')].find(c => c.dataset.date && c.dataset.date.endsWith('${md}')); return cell ? cell.querySelector('.cal-badge')?.textContent === '5' : false; })()`));

  // E5: 今日のセルクリック → カレンダーが閉じ日詳細モーダル（2行・2件・5枚）
  await evaluate(`(() => { const cell = [...document.querySelectorAll('#cal-grid .cal-cell')].find(c => c.dataset.date && c.dataset.date.endsWith('${md}')); cell.click(); })()`);
  check('E5 day dialog opens', await waitFor("document.getElementById('day-dialog')?.classList.contains('show')"));
  check('E5 dialog shows 2 rows', await evaluate("document.querySelectorAll('#day-list .record-row').length === 2"));
  check('E5 title 2件・5枚', await evaluate("document.getElementById('day-title')?.textContent?.includes('2件・5枚')"));

  // E6: メインの日詳細は見るだけ（削除ボタンなし）
  check('E6 no delete in main day detail', (await evaluate("document.querySelectorAll('#day-list .del').length")) === 0);
  await sleep(800);
  await evaluate("bootstrap.Modal.getInstance(document.getElementById('day-dialog')).hide();");
  await waitFor("!document.getElementById('day-dialog').classList.contains('show')");

  // E7: 今日一覧の「2 枚」行を削除 → PWダイアログが開く
  await evaluate("[...document.querySelectorAll('#today-list .record-row')].find(r => r.textContent.includes('2 枚')).querySelector('.del').click();");
  check('E7 pw dialog opens', await waitFor("document.getElementById('pw-dialog').classList.contains('show')"));
  await sleep(800);

  // E8: 誤PW → エラー / 正PW(1234) → 削除成功 total=3
  await evaluate("document.getElementById('pw').value = '9999';");
  await evaluate("document.getElementById('pw-ok').click();");
  check('E8 wrong pw error', await waitFor("document.getElementById('pw-err').textContent.includes('パスワードが違います')"));
  await evaluate("document.getElementById('pw').value = '1234';");
  await evaluate("document.getElementById('pw-ok').click();");
  check('E8 total=3 after delete', await waitFor("document.getElementById('today-total').textContent === '3'"));
  check('E8 one row left', (await evaluate("document.querySelectorAll('#today-list .record-row').length")) === 1);

  // E9: 残り1件も削除（セッション認証済みなのでPW不要）→ total 0
  await evaluate("document.querySelector('#today-list .del').click();");
  check('E9 total=0', await waitFor("document.getElementById('today-total').textContent === '0'"));
  check('E9 empty again', await evaluate("document.getElementById('today-list').textContent.includes('まだ記録がありません')"));

  // E10: 自動更新連動 — カレンダー表示中に他端末の記録を add → __refreshNow で今日一覧とカレンダーが最新化
  await evaluate("document.getElementById('today-date').click();");
  await waitFor("document.getElementById('calendar-dialog')?.classList.contains('show')");
  if (await evaluate("typeof window.__refreshNow === 'function'")) {
    await evaluate("fetch('api.php?action=add', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({count:5})}).then(r => r.status)");
    await evaluate("window.__refreshNow();");
    check('E10 today total=5 after refreshNow', await waitFor("document.getElementById('today-total').textContent === '5'"));
    check('E10 calendar badge updates to 5', await waitFor(`(() => { const cell = [...document.querySelectorAll('#cal-grid .cal-cell')].find(c => c.dataset.date && c.dataset.date.endsWith('${md}')); return cell ? cell.querySelector('.cal-badge')?.textContent === '5' : false; })()`));
  } else {
    check('E10 refreshNow exists', false);
    check('E10 today total=5 after refreshNow', false);
    check('E10 calendar badge updates to 5', false);
  }

  // E18: カレンダー 7 列固定レイアウト（CSS Grid・等幅・行折返し・行高統一・バッジはみ出しなし）
  const layout = await evaluate(`(() => {
    const grid = document.getElementById('cal-grid');
    const gs = getComputedStyle(grid);
    const gw = grid.getBoundingClientRect().width;
    const header = [...grid.children].slice(0, 7).map(el => { const r = el.getBoundingClientRect(); return { x: r.x, w: r.width }; });
    const all = [...grid.children].map(el => { const r = el.getBoundingClientRect(); return { x: Math.round(r.x), y: Math.round(r.y), h: Math.round(r.height) }; });
    const rows = {};
    for (const c of all) { (rows[c.y] = rows[c.y] || []).push(c); }
    const ys = Object.keys(rows).map(Number).sort((a, b) => a - b);
    const today = [...grid.children].find(el => el.dataset.date && el.dataset.date.endsWith('${md}'));
    const todayRow = today ? rows[Math.round(today.getBoundingClientRect().y)] : null;
    const badge = today ? today.querySelector('.cal-badge') : null;
    return {
      display: gs.display,
      tracks: gs.gridTemplateColumns.split(' ').length,
      gw,
      header,
      row1X: rows[ys[0]][0].x,
      row2X: rows[ys[1]][0].x,
      row1Y: ys[0],
      row2Y: ys[1],
      rowHeights: todayRow ? [...new Set(todayRow.map(c => c.h))] : [],
      badgeOverflow: badge ? badge.scrollWidth > badge.clientWidth : null,
      badgeText: badge ? badge.textContent : null,
    };
  })()`);
  check('E18 grid display grid 7 tracks', layout.display === 'grid' && layout.tracks === 7, 'display=' + layout.display + ' tracks=' + layout.tracks);
  const cellW = layout.gw / 7;
  const wOk = layout.header.every(c => Math.abs(c.w - cellW) / cellW < 0.12);
  check('E18 header cells equal width ~1/7', wOk, 'widths=' + JSON.stringify(layout.header.map(c => Math.round(c.w))) + ' grid=' + Math.round(layout.gw));
  const xs = layout.header.map(c => c.x);
  const gaps = xs.slice(1).map((x, i) => x - xs[i]);
  const gapMean = gaps.reduce((a, b) => a + b, 0) / gaps.length;
  const gapOk = gaps.every(g => Math.abs(g - gapMean) / gapMean < 0.12);
  check('E18 header cells evenly spaced', gapOk, 'gaps=' + JSON.stringify(gaps.map(Math.round)));
  check('E18 rows wrap 7 cols', layout.row2X === layout.row1X && layout.row2Y > layout.row1Y, 'x1=' + layout.row1X + ' x2=' + layout.row2X + ' y1=' + layout.row1Y + ' y2=' + layout.row2Y);
  check('E18 same-row heights equal', layout.rowHeights.length === 1 && layout.rowHeights[0] >= 44, 'heights=' + JSON.stringify(layout.rowHeights));
  check('E18 badge no overflow', layout.badgeOverflow === false, 'badge=' + layout.badgeText);

  // カレンダーの今日セル → 日詳細（1行・5枚）
  await evaluate(`(() => { const cell = [...document.querySelectorAll('#cal-grid .cal-cell')].find(c => c.dataset.date && c.dataset.date.endsWith('${md}')); cell.click(); })()`);
  await waitFor("document.getElementById('day-dialog')?.classList.contains('show')");
  check('E10 day dialog 1 row 5枚', await evaluate("document.querySelectorAll('#day-list .record-row').length === 1 && document.getElementById('day-list').textContent.includes('5 枚')"));
  await sleep(800);
  await evaluate("bootstrap.Modal.getInstance(document.getElementById('day-dialog')).hide();");
  await waitFor("!document.getElementById('day-dialog').classList.contains('show')");

  // E11: カレンダーの前月へ → 日付グリッド → 1日クリック → 記録なし（見るだけ）
  await evaluate("document.getElementById('today-date').click();");
  await waitFor("document.getElementById('calendar-dialog')?.classList.contains('show')");
  await evaluate("document.getElementById('cal-prev').click();");
  check('E11 prev month grid', await waitFor("document.querySelectorAll('#cal-grid .cal-cell').length >= 28"));
  await evaluate("[...document.querySelectorAll('#cal-grid .cal-cell')].find(c => c.dataset.day === '1').click();");
  await waitFor("document.getElementById('day-dialog')?.classList.contains('show')");
  check('E11 empty day message', await evaluate("document.getElementById('day-list').textContent.includes('記録がありません')"));
  await sleep(800);
  await evaluate("bootstrap.Modal.getInstance(document.getElementById('day-dialog')).hide();");
  await waitFor("!document.getElementById('day-dialog').classList.contains('show')");
  await sleep(800);
  await evaluate("bootstrap.Modal.getInstance(document.getElementById('calendar-dialog')).hide();");
  await waitFor("!document.getElementById('calendar-dialog').classList.contains('show')");

  // ---------- 管理者画面 ----------
  // E12: ログアウト → admin.php を開く → PWダイアログ・コンテンツ非表示（未認証）
  await evaluate("fetch('api.php?action=logout').then(r => r.status)");
  await send('Page.navigate', { url: BASE + '/admin.php' });
  check('E12 admin pw dialog', await waitFor("document.getElementById('a-pw-dialog')?.classList.contains('show')"));
  check('E12 admin content hidden', (await evaluate("document.getElementById('admin-content').hidden")) === true);
  await sleep(800);

  // E13: 正PW(1234) → 管理者コンテンツ表示・日別集計テーブル（今日のセル total=5）→ 日詳細（編集/削除ボタン）
  await evaluate("document.getElementById('a-pw').value = '1234';");
  await evaluate("document.getElementById('a-pw-ok').click();");
  check('E13 admin content shown', await waitFor("document.getElementById('admin-content').hidden === false"));
  check('E13 month table shown', await waitFor("document.getElementById('a-month-table').hidden === false"));
  check('E13 today cell total 5', await waitFor(`(() => { const cell = [...document.querySelectorAll('#a-month-table tbody tr td.a-day-link')].find(td => td.textContent.trim() === '${md}'); return cell ? cell.parentElement.querySelector('td:last-child').textContent === '5' : false; })()`));
  await evaluate(`(() => { const cell = [...document.querySelectorAll('#a-month-table tbody tr td.a-day-link')].find(td => td.textContent.trim() === '${md}'); cell.click(); })()`);
  check('E13 admin day dialog', await waitFor("document.getElementById('a-day-dialog')?.classList.contains('show')"));
  check('E13 edit/delete buttons', await evaluate("document.querySelectorAll('#a-day-list .edit').length === 1 && document.querySelectorAll('#a-day-list .del').length === 1"));
  await sleep(800);
  await evaluate("bootstrap.Modal.getInstance(document.getElementById('a-day-dialog')).hide();");
  await waitFor("!document.getElementById('a-day-dialog').classList.contains('show')");

  // E14: 月報タブ → 表 + グラフ（canvas 描画）
  await evaluate("document.getElementById('atab-mreport').click();");
  check('E14 mreport table', await waitFor("document.getElementById('a-mreport-table').hidden === false"));
  check('E14 mreport chart drawn', await waitFor("document.getElementById('a-mreport-chart').width > 0"));

  // E15: 分析タブ → 期間サマリ + 曜日別/時間帯別グラフ
  await evaluate("document.getElementById('atab-analysis').click();");
  check('E15 summary total 5', await waitFor("document.getElementById('a-summary-total').textContent === '5'"));
  check('E15 dow chart drawn', await waitFor("document.getElementById('a-dow-chart').width > 0"));
  check('E15 hour chart drawn', await waitFor("document.getElementById('a-hour-chart').width > 0"));

  // E16: 集計タブ → 日詳細で編集（5→8）→ 行・集計テーブルに反映
  await evaluate("document.getElementById('atab-monthly').click();");
  await waitFor("document.getElementById('a-month-table').hidden === false");
  await evaluate(`(() => { const cell = [...document.querySelectorAll('#a-month-table tbody tr td.a-day-link')].find(td => td.textContent.trim() === '${md}'); cell.click(); })()`);
  await waitFor("document.getElementById('a-day-dialog')?.classList.contains('show')");
  await evaluate("document.querySelector('#a-day-list .edit').click();");
  check('E16 edit dialog opens', await waitFor("document.getElementById('a-edit-dialog')?.classList.contains('show')"));
  await evaluate("document.getElementById('a-edit-count').value = '8';");
  await evaluate("document.getElementById('a-edit-ok').click();");
  check('E16 row updated to 8枚', await waitFor("document.getElementById('a-day-list').textContent.includes('8 枚')"));
  check('E16 table total 8', await waitFor(`(() => { const cell = [...document.querySelectorAll('#a-month-table tbody tr td.a-day-link')].find(td => td.textContent.trim() === '${md}'); return cell ? cell.parentElement.querySelector('td:last-child').textContent === '8' : false; })()`));
  await sleep(800);
  await evaluate("bootstrap.Modal.getInstance(document.getElementById('a-day-dialog')).hide();");
  await waitFor("!document.getElementById('a-day-dialog').classList.contains('show')");

  // E17: 日詳細で削除 → 行消滅・集計テーブル total 0
  await evaluate(`(() => { const cell = [...document.querySelectorAll('#a-month-table tbody tr td.a-day-link')].find(td => td.textContent.trim() === '${md}'); cell.click(); })()`);
  await waitFor("document.getElementById('a-day-dialog')?.classList.contains('show')");
  await evaluate("document.querySelector('#a-day-list .del').click();");
  check('E17 row deleted', await waitFor("document.querySelectorAll('#a-day-list .record-row').length === 0"));
  check('E17 table total 0', await waitFor(`(() => { const cell = [...document.querySelectorAll('#a-month-table tbody tr td.a-day-link')].find(td => td.textContent.trim() === '${md}'); return cell ? cell.parentElement.querySelector('td:last-child').textContent === '0' : false; })()`));

  // E19: ログアウト（記録画面へボタン・確認なし）→ セッション破棄で PW 再要求
  check('E19 admin content visible before logout', (await evaluate("document.getElementById('admin-content').hidden")) === false);
  await evaluate("document.getElementById('a-logout').click();");
  check('E19 navigates to index', await waitFor("document.location.pathname.endsWith('/index.php') && document.getElementById('today-total') !== null"));
  await sleep(400);
  await send('Page.navigate', { url: BASE + '/admin.php' });
  check('E19 pw dialog shown again', await waitFor("document.getElementById('a-pw-dialog')?.classList.contains('show')"));
  check('E19 content hidden after logout', (await evaluate("document.getElementById('admin-content').hidden")) === true);
  await sleep(800);

  // E20: 日別集計 前月/翌月ボタン（年跨ぎ自動・セレクト同期・表再描画）
  await evaluate("document.getElementById('a-pw').value = '1234';");
  await evaluate("document.getElementById('a-pw-ok').click();");
  await waitFor("document.getElementById('admin-content').hidden === false");
  await waitFor("document.getElementById('a-month-table').hidden === false");
  const nowYear = new Date().getFullYear();
  const setMonth = (y, m) => evaluate(`document.getElementById('a-year').value = '${y}'; document.getElementById('a-month').value = '${m}'; document.getElementById('a-month-btn').click();`);
  const firstRowDate = () => evaluate("document.querySelector('#a-month-table tbody tr td.a-day-link')?.textContent?.trim() || ''");
  await setMonth(2026, 6);
  check('E20 set 2026-06', await waitFor("document.querySelector('#a-month-table tbody tr td.a-day-link')?.textContent?.trim() === '06-01'"));
  await evaluate("document.getElementById('a-month-prev').click();");
  check('E20a prev month value', await waitFor("document.getElementById('a-month').value === '5'"));
  check('E20a prev year unchanged', (await evaluate("document.getElementById('a-year').value")) === '2026');
  check('E20a prev table redrawn', await waitFor("document.querySelector('#a-month-table tbody tr td.a-day-link')?.textContent?.trim() === '05-01'"));
  await evaluate("document.getElementById('a-month-next').click();");
  check('E20b next +1', await waitFor("document.getElementById('a-month').value === '6'"));
  await evaluate("document.getElementById('a-month-next').click();");
  check('E20b next +2', await waitFor("document.getElementById('a-month').value === '7'"));
  check('E20b next table redrawn', await waitFor("document.querySelector('#a-month-table tbody tr td.a-day-link')?.textContent?.trim() === '07-01'"));
  await setMonth(2026, 1);
  check('E20c set 2026-01', await waitFor("document.querySelector('#a-month-table tbody tr td.a-day-link')?.textContent?.trim() === '01-01'"));
  await evaluate("document.getElementById('a-month-prev').click();");
  check('E20c prev crosses year', await waitFor("document.getElementById('a-year').value === '2025' && document.getElementById('a-month').value === '12'"));
  await setMonth(nowYear - 10, 12);
  check('E20d set oldest year Dec', await waitFor("document.querySelector('#a-month-table tbody tr td.a-day-link')?.textContent?.trim() === '12-01'"));
  await evaluate("document.getElementById('a-month-next').click();");
  check('E20d next crosses year', await waitFor("document.getElementById('a-year').value === '" + (nowYear - 9) + "' && document.getElementById('a-month').value === '1'"));

  console.log('pageErrors:', pageErrors.length ? '\n' + pageErrors.join('\n') : 'none');

  const passed = results.filter(Boolean).length;
  console.log(`\nRESULT: ${passed}/${results.length} passed`);
  ws.close();
  process.exit(passed === results.length ? 0 : 1);
}

main().catch(e => { console.error('E2E ERROR: ' + e.message); process.exit(1); });
