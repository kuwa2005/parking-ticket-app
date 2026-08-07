// 駐車券記録アプリ UI E2Eテスト（ヘッドレスChromium + CDP、外部依存なし）
// 実行: node tests/e2e_ui.mjs
// 前提: PHPサーバーがポート4500で稼働中（PARK_DB_PATHで一時DBを使用）

const BASE = 'http://127.0.0.1:4500';
const CDP_HTTP = 'http://127.0.0.1:9222';
const CHROME = process.env.CHROME_BIN || 'google-chrome';

let results = [];
function check(name, cond, detail = '') {
  results.push(cond);
  console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`);
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

setTimeout(() => { console.log('WATCHDOG: 90s timeout'); process.exit(3); }, 90000);

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
  // 既存のchromeプロセスが残っていれば、まず接続を試み、失敗したら起動
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

  // アプリへナビゲート（起動順に依存しないよう CDP で遷移させる）
  await send('Page.navigate', { url: BASE + '/' });

  // ページロード完了（loadToday が実行され #today-total が描画される）
  if (!(await waitFor("document.getElementById('today-total') !== null"))) {
    throw new Error('page did not load');
  }
  await waitFor("document.getElementById('today-list').children.length > 0");

  // E1: 初期状態（一時DBなので total=0・空メッセージ）
  check('E1 initial total 0', (await evaluate("document.getElementById('today-total').textContent")) === '0');
  check('E1 empty message', await evaluate("document.getElementById('today-list').textContent.includes('まだ記録がありません')"));

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

  // E4: 日別集計タブ → 表示 → PWダイアログが開く
  await evaluate("document.getElementById('tab-month').click();");
  check('E4 month panel visible', await waitFor("!document.getElementById('panel-month').hidden"));
  await evaluate("document.getElementById('month-btn').click();");
  check('E4 pw dialog opens', await waitFor("document.getElementById('pw-dialog').classList.contains('show')"));

  // Bootstrap Modal は show 遷移(約500ms)完了まで hide() を guard で無視するため、
  // 遷移完了を待ってから誤PW/正PWの操作を行う（実ユーザーの入力ペースに相当）
  await sleep(800);

  // E5: 誤PW → エラーメッセージ
  await evaluate("document.getElementById('pw').value = '9999';");
  await evaluate("document.getElementById('pw-ok').click();");
  check('E5 wrong pw error', await waitFor("document.getElementById('pw-err').textContent.includes('パスワードが違います')"));

  // E6: 正PW(1234) → ダイアログが閉じ、月別テーブル表示（合計5）
  // 注: テーブル描画を先に待つ（hide() の遷移完了を待つことで決定論的になる）
  await evaluate("document.getElementById('pw').value = '1234';");
  await evaluate("document.getElementById('pw-ok').click();");
  check('E6 month table shown', await waitFor("!document.getElementById('month-table').hidden"));
  check('E6 grand total 5', await evaluate("document.querySelector('#month-table tbody tr:last-child td:last-child').textContent === '5'"));
  check('E6 dialog closes', await waitFor("!document.getElementById('pw-dialog').classList.contains('show')"));

  // E7: 今日の記録へ戻り、「2 枚」の行（昇順で2件目）を削除（セッション認証済みなのでPW不要）→ total 3
  // 注: get_today は時間昇順（DEMO 化要件）のため先頭行は最初に記録した count=3 の行。count=2 の行を削除する。
  await evaluate("document.getElementById('tab-today').click();");
  await waitFor("!document.getElementById('panel-today').hidden");
  await evaluate("[...document.querySelectorAll('#today-list .record-row')].find(r => r.textContent.includes('2 枚')).querySelector('.del').click();");
  check('E7 total=3 after delete', await waitFor("document.getElementById('today-total').textContent === '3'"));
  check('E7 one row left', (await evaluate("document.querySelectorAll('#today-list .record-row').length")) === 1);

  // E8: 2件目も削除 → total 0
  await evaluate("document.querySelector('#today-list .del').click();");
  check('E8 total=0 after delete', await waitFor("document.getElementById('today-total').textContent === '0'"));
  check('E8 empty again', await evaluate("document.getElementById('today-list').textContent.includes('まだ記録がありません')"));

  console.log('pageErrors:', pageErrors.length ? '\n' + pageErrors.join('\n') : 'none');

  const passed = results.filter(Boolean).length;
  console.log(`\nRESULT: ${passed}/${results.length} passed`);
  ws.close();
  process.exit(passed === results.length ? 0 : 1);
}

main().catch(e => { console.error('E2E ERROR: ' + e.message); process.exit(1); });
