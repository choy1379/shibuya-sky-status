// 1회용 탐색: GitHub Actions에서 클룩 페이지가 열리는지, 날짜·시간 정보가 어떤 API로 오는지 기록한다.
import { chromium } from 'playwright';

const URL = 'https://www.klook.com/ko/activity/70672-shibuya-sky-tokyo/';
const browser = await chromium.launch();
const page = await browser.newPage({ locale: 'ko-KR', userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36' });
page.on('response', async (r) => {
  const u = r.url();
  if (!/klook\.com\/(v\d|api|xos_api)/.test(u)) return;
  let body = '';
  try { body = (await r.text()).slice(0, 600); } catch {}
  console.log(`API ${r.status()} ${u}\n  ${body.replace(/\s+/g, ' ')}`);
});
const res = await page.goto(URL, { waitUntil: 'networkidle', timeout: 60000 }).catch(e => (console.log('goto error', e.message), null));
console.log('PAGE', res && res.status(), await page.title());
// 날짜 선택 버튼을 눌러 달력/시간 API를 유도
for (const label of ['날짜 선택', '날짜', '예약하기', '옵션 선택']) {
  const b = page.getByText(label, { exact: false }).first();
  if (await b.count()) { await b.click({ timeout: 5000 }).catch(() => {}); await page.waitForTimeout(4000); }
}
console.log('TEXT', (await page.innerText('body')).slice(0, 1500).replace(/\s+/g, ' '));
await browser.close();
