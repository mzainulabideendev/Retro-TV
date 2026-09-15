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

// ------------------------------------------------ YouTube Data API path
// Permanent + fully free solution. The YouTube Data API v3 key is free
// forever (10,000 units/day, ~130 full playlist imports of 300 items/day, no
// trial, no credit card). When YOUTUBE_API_KEY is set as a Vercel env var,
// playlist imports skip the scraped feeds entirely and use the official API —
// immune to YouTube's datacenter-IP blocking of the RSS feeds.
const YT_API_KEY = process.env.YOUTUBE_API_KEY || '';
const MAX_ITEMS = 300;

// Resolves a playlist via the Data API, paginating until done.
async function fetchViaDataApi(playlistId) {
  const items = [];
  let pageToken = '';
  do {
    const url = new URL('https://www.googleapis.com/youtube/v3/playlistItems');
    url.searchParams.set('part', 'snippet,contentDetails');
    url.searchParams.set('maxResults', '50');
    url.searchParams.set('playlistId', playlistId);
    url.searchParams.set('key', YT_API_KEY);
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) {
      let reason = `YouTube API HTTP ${res.status}`;
      try {
        const err = await res.json();
        if (err && err.error && err.error.message) reason = err.error.message;
      } catch (_) {}
      throw new Error(reason);
    }
    const data = await res.json();
    for (const it of data.items || []) {
      const s = it.snippet || {};
      const videoId = (it.contentDetails && it.contentDetails.videoId) || (s.resourceId && s.resourceId.videoId);
      if (!videoId) continue;
      items.push({
        videoId,
        title: (s.title || '').trim() || 'Untitled',
        thumb:
          (s.thumbnails && (s.thumbnails.high || s.thumbnails.default || {}).url) || null,
        position: items.length + 1,
      });
      if (items.length >= MAX_ITEMS) break;
    }
    pageToken = data.nextPageToken || '';
  } while (pageToken && items.length < MAX_ITEMS);
  return items;
}

const esc = (s) =>
  String(s === null || s === undefined ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

// Builds an Atom feed the Flutter client's RSS parser already understands.
function toAtomRss(playlistId, items) {
  const entries = items
    .map(
      (it) => `  <entry>
    <id>yt:video:${esc(it.videoId)}</id>
    <yt:videoId>${esc(it.videoId)}</yt:videoId>
    <title>${esc(it.title)}</title>
    <position>${it.position}</position>
    <link rel="alternate" href="https://www.youtube.com/watch?v=${esc(it.videoId)}" />
    <media:group>
      <media:title>${esc(it.title)}</media:title>
      ${it.thumb ? `      <media:thumbnail url="${esc(it.thumb)}" />` : ''}
    </media:group>
  </entry>`,
    )
    .join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/" xmlns:yt="http://www.youtube.com/xml/schemas/2015">
  <id>yt:playlist:${esc(playlistId)}</id>
  <link rel="alternate" href="https://www.youtube.com/playlist?list=${esc(playlistId)}" />
  <title>Playlist</title>
${entries}
</feed>
`;
}

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

  // Official Data API path (only active once YOUTUBE_API_KEY is configured):
  // if the target looks like a YouTube playlist feeds URL, resolve it through
  // the free, permanent YouTube Data API instead of scraping.
  const feedMatch = target.match(/feeds\/videos\.xml.*[?&]playlist_id=([A-Za-z0-9_-]+)/);
  if (YT_API_KEY && feedMatch) {
    try {
      const items = await fetchViaDataApi(feedMatch[1]);
      if (items.length > 0) {
        res.statusCode = 200;
        res.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        res.end(toAtomRss(feedMatch[1], items));
        return;
      }
    } catch (e) {
      // fall through to the keyless path rather than failing the import
      try {
        const parsed = JSON.parse((e && e.message) || '');
        if (parsed && parsed.error) {
          res.setHeader('Content-Type', 'application/json');
        }
      } catch (_) {}
    }
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