// Realistic desktop-browser request so YouTube serves the XML/Atom feed. A
// bare User-Agent from a Vercel datacenter IP makes YouTube return its HTML
// consent/bot-check page instead of the feed (the "RSS feed returned HTML
// instead of XML" failure). The CONSENT cookie skips the EU consent wall.
const BROWSER_HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
  Accept:
    'text/html,application/xhtml+xml,application/xml;q=0.9,application/atom+xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.9',
  'Accept-Encoding': 'gzip, deflate, br',
  Cookie: 'CONSENT=YES+cb.20240101-00-p0.en+FX+700',
  Referer: 'https://www.youtube.com/',
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Fetches the target with browser-grade headers. YouTube intermittently
// answers the free feeds endpoint with a bogus 404 / HTML during short
// rate-limit windows, so a couple of spaced retries catch a working window.
async function fetchWithRetry(target, attempts = 2) {
  let lastStatus = 502;
  let lastBody = null;
  let lastContentType = null;
  for (let i = 0; i < attempts; i++) {
    try {
      const upstream = await fetch(target, {
        headers: BROWSER_HEADERS,
        redirect: 'follow',
      });
      const body = await upstream.text();
      // Consent/bot walls and empty 404s are transient — retry a moment later.
      const blocked =
        /consent\.youtube\.com|google\.com\/sorry|ServiceLogin/i.test(body);
      if (
        !blocked &&
        (upstream.ok || (upstream.status === 404 && body.includes('<entry')))
      ) {
        return { status: blocked ? 503 : upstream.status, body, blocked };
      }
      lastStatus = upstream.status;
      lastBody = body;
      lastContentType = upstream.headers.get('content-type');
    } catch (e) {
      lastStatus = 502;
      lastContentType = 'application/json';
      lastBody = JSON.stringify({ error: String((e && e.message) || e) });
    }
    await sleep(1500 * (i + 1));
  }
  if (lastBody && /consent\.youtube\.com|google\.com\/sorry|ServiceLogin/.test(lastBody)) {
    return { status: 503, body: 'YouTube blocked this request (consent/bot-check).', blocked: true, contentType: lastContentType };
  }
  return { status: lastStatus, body: lastBody || '', blocked: false, contentType: lastContentType };
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  const url = new URL(req.url, 'http://local');
  const target = url.searchParams.get('url');
  if (!target || !/^https?:\/\//.test(target)) {
    res.statusCode = 400;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ error: 'Missing or invalid "url" parameter' }));
    return;
  }
  try {
    const { status, body, blocked, contentType } = await fetchWithRetry(target);
    res.statusCode = status;
    res.setHeader(
      'Content-Type',
      contentType || 'text/xml; charset=UTF-8',
    );
    res.end(blocked ? 'YouTube blocked this request (consent/bot-check).' : body);
  } catch (e) {
    res.statusCode = 502;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ error: String((e && e.message) || e) }));
  }
}