// Retro TV — import-youtube-playlist Edge Function
//
// Fetches the full video list of a YouTube playlist SERVER-SIDE, so the
// browser never talks to YouTube directly (important: YouTube's public RSS
// endpoint sends no CORS headers, so a browser fetch fails with
// "ClientException: Failed to fetch" — this function sidesteps that).
//
// Free keyless method (every request): YouTube's public playlist RSS feed +
// `ytInitialData` page scrape — no API key, no Google Cloud setup. Supabase is
// the ONLY service the app talks to for playlist import (the client never
// touches YouTube directly; the browser can't because YouTube sends no CORS
// headers).
//
// An optional YOUTUBE_API_KEY secret makes imports more reliable (YouTube
// intermittently rate-limits the free RSS endpoint), but the feature works
// fully without it. The caller's Supabase JWT is verified against the
// database: only admins / content managers may import.
//
// Deploy (no secret required for the free method):
//   supabase functions deploy import-youtube-playlist --no-verify-jwt
// Optional (more reliable imports):
//   supabase secrets set YOUTUBE_API_KEY=<your key>

import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const YOUTUBE_API_KEY = Deno.env.get('YOUTUBE_API_KEY') ?? '';
const MAX_TOTAL_ITEMS = 300;

// A desktop-browser user-agent plus the EU "CONSENT" cookie are required in
// 2024+: YouTube's public RSS endpoint serves an HTML consent page (or a bot
// challenge) to datacenter IPs / non-browser agents instead of the XML feed.
const BROWSER_HEADERS: Record<string, string> = {
  'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
  Accept:
    'text/html,application/xhtml+xml,application/xml;q=0.9,application/atom+xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.9',
  'Accept-Encoding': 'gzip, deflate, br',
  Cookie: 'CONSENT=YES+cb.20240101-00-p0.en+FX+700',
  Referer: 'https://www.youtube.com/',
};

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

async function fetchPlaylistItems(playlistId: string): Promise<unknown[]> {
  if (!YOUTUBE_API_KEY) {
    throw new Error('SERVER_YOUTUBE_API_KEY_NOT_CONFIGURED');
  }

  const all: unknown[] = [];
  let pageToken = '';
  let page = 0;
  do {
    if (page++ > 0) await sleep(250); // stay inside YouTube quota/rate limits
    const params = new URLSearchParams({
      part: 'snippet,contentDetails',
      maxResults: '50',
      playlistId,
      key: YOUTUBE_API_KEY,
    });
    if (pageToken) params.set('pageToken', pageToken);

    const res = await fetch(
      `https://www.googleapis.com/youtube/v3/playlistItems?${params}`,
      { headers: { Accept: 'application/json' } },
    );
    if (!res.ok) {
      let reason = `YouTube API HTTP ${res.status}`;
      try {
        const err = (await res.json()) as { error?: { message?: string } };
        if (err?.error?.message) reason = err.error.message;
      } catch {
        /* ignore parse errors */
      }
      throw new Error(reason);
    }
    const data = (await res.json()) as {
      items?: Array<{
        snippet?: {
          resourceId?: { videoId?: string };
          title?: string;
          description?: string;
          position?: number;
          thumbnails?: Record<
            string,
            { url?: string }
          >;
        };
        contentDetails?: { videoId?: string };
      }>;
      nextPageToken?: string;
    };

    for (const item of data.items ?? []) {
      const videoId =
        item.contentDetails?.videoId ??
        item.snippet?.resourceId?.videoId;
      if (!videoId) continue;
      all.push({
        youtube_video_id: videoId,
        title: item.snippet?.title?.trim() ?? 'Untitled',
        description: item.snippet?.description?.trim() || null,
        thumbnail_url:
          item.snippet?.thumbnails?.high?.url ??
          item.snippet?.thumbnails?.default?.url ??
          null,
        playlist_position:
          (item.snippet?.position ?? 0) + 1,
      });
      if (all.length >= MAX_TOTAL_ITEMS) break;
    }
    pageToken = data.nextPageToken ?? '';
  } while (pageToken && all.length < MAX_TOTAL_ITEMS);

  return all;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------
// ---------------------------------------------------------------
// FREE keyless method (primary): YouTube's public playlist RSS feed, fetched
// server-side (Supabase = the only service the app talks to for playlist
// import, so no API key is required and no Google/oauth setup is needed).
//
// YouTube intermittently blocks the feeds/videos.xml endpoint with bogus
// 404 / HTML responses during rate-limit windows (this is a known, time-boxed
// behaviour). A few retries with browser-grade headers + the CONSENT cookie
// catch a working window; if the feed still refuses, the `ytInitialData`
// JSON embedded in the playlist page is scraped as a second free option.
// ---------------------------------------------------------------
async function fetchPlaylistViaRss(playlistId: string): Promise<unknown[]> {
  const feedUrl = `https://www.youtube.com/feeds/videos.xml?playlist_id=${playlistId}`;
  let lastError = 'RSS feed unavailable. YouTube is intermittently blocking free playlist feeds — try again in a few minutes.';

  for (let attempt = 0; attempt < 4; attempt++) {
    if (attempt > 0) await sleep(2000 * attempt);
    try {
      const res = await fetch(feedUrl, {
        headers: BROWSER_HEADERS,
        redirect: 'follow',
      });
      if (!res.ok) {
        // 404/403 during the block window — retry before giving up.
        lastError = `Playlist not found or private (HTTP ${res.status}).`;
        continue;
      }
      const body = await res.text();
      const items = parseRssItems(body);
      if (items.length > 0) return items;
      // Feed wasn't XML (or had no entries): scrape the `ytInitialData` JSON
      // embedded in the playlist page. The body returned at the feeds URL is
      // often already that HTML page, so it is reused when possible.
      return fetchPlaylistViaPage(playlistId, body);
    } catch (e) {
      lastError = e instanceof Error ? e.message : String(e);
    }
  }
  throw new Error(lastError);
}

// Fetches the `/playlist` page and extracts the video list from the
// `ytInitialData` JSON blob (*before* YouTube's JS runs). Succeeds even
// when the RSS feed is replaced by an HTML page.
async function fetchPlaylistViaPage(
  playlistId: string,
  maybeHtml?: string,
): Promise<unknown[]> {
  let html = maybeHtml;
  if (!html || !html.includes('ytInitialData')) {
    const res = await fetch(
      `https://www.youtube.com/playlist?list=${playlistId}&hl=en`,
      { headers: BROWSER_HEADERS, redirect: 'follow' },
    );
    if (!res.ok) {
      throw new Error(`Playlist page could not be loaded (HTTP ${res.status}).`);
    }
    html = await res.text();
  }
  return parsePlaylistPage(html);
}

function parseRssItems(xml: string): unknown[] {
  const items: unknown[] = [];
  const entries = xml.match(/<entry>[\s\S]*?<\/entry>/g) ?? [];
  for (let index = 0; index < entries.length; index++) {
    const body = entries[index];

    let videoId = matchTag(body, 'yt:videoId') ?? matchTag(body, 'videoid');
    if (!videoId) {
      const idText = matchTag(body, 'id');
      const idMatch = idText?.match(/yt:video:([A-Za-z0-9_-]{6,})/);
      videoId = idMatch?.[1];
    }
    if (!videoId) {
      const link = matchTag(body, 'link');
      const linkMatch = link?.match(/[?&]v=([A-Za-z0-9_-]{6,})/);
      videoId = linkMatch?.[1];
    }
    if (!videoId || videoId.trim().length === 0) continue;

    const group = body.match(/<media:group>[\s\S]*?<\/media:group>/)?.[0] ?? body;
    const title = matchTag(group, 'media:title') ?? matchTag(group, 'title') ?? 'Untitled';
    const description = matchTag(group, 'media:description') ?? null;
    const thumbMatch = group.match(/<media:thumbnail[^>]*url="([^"]+)"/);
    const thumbnail = thumbMatch?.[1] ?? null;
    const positionMatch = matchTag(body, 'yt:position') ?? matchTag(body, 'position');
    const position = positionMatch ? parseInt(positionMatch, 10) : index + 1;

    items.push({
      youtube_video_id: videoId.trim(),
      title: stripCdata(title).trim(),
      description: description ? stripCdata(description).trim() || null : null,
      thumbnail_url: thumbnail,
      playlist_position: Number.isFinite(position) ? position : index + 1,
    });
  }
  return items;
}

function matchTag(xml: string, tag: string): string | null {
  const m = xml.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`));
  return m ? m[1] : null;
}

function stripCdata(s: string): string {
  return s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1');
}

// ---------------------------------------------------------------
// Playlist HTML page scraping (ytInitialData)
// ---------------------------------------------------------------
function parsePlaylistPage(html: string): unknown[] {
  if (/consent\.youtube\.com|google\.com\/sorry|ServiceLogin/i.test(html)) {
    throw new Error(
      'YouTube blocked this request (consent / bot-check page). Try again later.',
    );
  }
  const jsonText = extractJsonObject(html, 'ytInitialData');
  if (!jsonText) {
    throw new Error(
      'Could not read the playlist page. The playlist may be private or empty.',
    );
  }
  const data = JSON.parse(jsonText) as unknown;
  const renderer = findPlaylistRenderer(data);
  if (!renderer) {
    throw new Error('No videos found. The playlist may be private or empty.');
  }

  const contents = renderer.contents;
  const items: unknown[] = [];
  let position = 1;
  if (Array.isArray(contents)) {
    for (const c of contents) {
      if (!c || typeof c !== 'object') continue;
      const p = (c as Record<string, unknown>).playlistVideoRenderer;
      if (!p || typeof p !== 'object') continue;
      const videoId = (p as Record<string, unknown>).videoId;
      if (typeof videoId !== 'string' || videoId.trim().length === 0) continue;
      items.push({
        youtube_video_id: videoId.trim(),
        title: initialDataText((p as Record<string, unknown>).title) ?? 'Untitled',
        description: null,
        thumbnail_url: initialDataThumb((p as Record<string, unknown>).thumbnail),
        playlist_position: position++,
      });
    }
  }

  if (items.length === 0) {
    throw new Error('No videos found. The playlist may be private or empty.');
  }
  return items;
}

// Extracts the first JSON object assigned to `var <name> =` in a <script>
// blurb. Brace-matching is used instead of regex so titles containing
// brackets, quotes or semicolons can never truncate the payload.
function extractJsonObject(html: string, name: string): string | null {
  const marker = `var ${name} =`;
  const startIndex = html.indexOf(marker);
  if (startIndex < 0) return null;
  const start = html.indexOf('{', startIndex + marker.length);
  if (start < 0) return null;

  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < html.length; i++) {
    const ch = html[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }
    if (ch === '"') {
      inString = true;
    } else if (ch === '{') {
      depth++;
    } else if (ch === '}') {
      depth--;
      if (depth === 0) return html.substring(start, i + 1);
    }
  }
  return null;
}

// Locates the `playlistVideoListRenderer` subtree anywhere in the payload.
// Only its entries are real playlist items (the sidebar holds unrelated
// "recommended" videos too, which must not be imported).
function findPlaylistRenderer(data: unknown): Record<string, unknown> | null {
  if (!data || typeof data !== 'object') return null;
  if (Array.isArray(data)) {
    for (const v of data) {
      const r = findPlaylistRenderer(v);
      if (r) return r;
    }
    return null;
  }
  const obj = data as Record<string, unknown>;
  const direct = obj.playlistVideoListRenderer;
  if (direct && typeof direct === 'object') {
    return direct as Record<string, unknown>;
  }
  for (const v of Object.values(obj)) {
    const r = findPlaylistRenderer(v);
    if (r) return r;
  }
  return null;
}

function initialDataText(value: unknown): string | null {
  if (typeof value === 'string') {
    const t = value.trim();
    return t.length === 0 ? null : t;
  }
  if (!value || typeof value !== 'object') return null;
  const v = value as Record<string, unknown>;
  if (Array.isArray(v.runs)) {
    let buffer = '';
    for (const r of v.runs) {
      if (r && typeof r === 'object') {
        const text = (r as Record<string, unknown>).text;
        if (typeof text === 'string') buffer += text;
      }
    }
    const t = buffer.trim();
    if (t.length > 0) return t;
  }
  const simple = v.simpleText;
  if (typeof simple === 'string' && simple.trim().length > 0) return simple.trim();
  return null;
}

function initialDataThumb(value: unknown): string | null {
  if (!value || typeof value !== 'object') return null;
  const thumbs = (value as Record<string, unknown>).thumbnails;
  if (Array.isArray(thumbs) && thumbs.length > 0) {
    const last = thumbs[thumbs.length - 1];
    if (last && typeof last === 'object') {
      const url = (last as Record<string, unknown>).url;
      if (typeof url === 'string' && url.length > 0) {
        return url.startsWith('//') ? `https:${url}` : url;
      }
    }
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'GET') {
    return json({ error: 'Method not allowed' }, 405);
  }

  try {
    const url = new URL(req.url);
    const playlistId = url.searchParams.get('playlist_id')?.trim();
    if (!playlistId || !/^[A-Za-z0-9_-]{10,}$/.test(playlistId)) {
      return json({ error: 'Invalid playlist_id' }, 400);
    }

    // Authorize: forward the caller's JWT so the DB can verify they are
    // an admin / content manager. Anonymous calls are rejected.
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.replace(/^Bearer\s+/i, '');
    if (!token) return json({ error: 'Unauthorized' }, 401);

    const userClient = createClient(
      SUPABASE_URL,
      SUPABASE_ANON_KEY,
      {
        auth: { persistSession: false, autoRefreshToken: false },
        global: {
          headers: { Authorization: `Bearer ${token}` },
        },
      },
    );
    const isManager = await userClient.rpc('is_content_manager');
    if (isManager.error) {
      return json({ error: 'Unauthorized — admin/content-manager only.' }, 403);
    }

    // Primary: FREE keyless RSS/page-scrape method (no Google API key, no
    // oauth). If an optional YOUTUBE_API_KEY happens to be configured, the
    // more reliable Data API is tried first and the free method is used only
    // if that call fails.
    let items: unknown[];
    if (YOUTUBE_API_KEY) {
      try {
        items = await fetchPlaylistItems(playlistId);
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        try {
          items = await fetchPlaylistViaRss(playlistId);
        } catch (rssErr) {
          const rssMessage =
            rssErr instanceof Error ? rssErr.message : String(rssErr);
          return json(
            { error: `YouTube API error: ${message}. ${rssMessage}` },
            502,
          );
        }
      }
    } else {
      try {
        items = await fetchPlaylistViaRss(playlistId);
      } catch (rssErr) {
        const rssMessage =
          rssErr instanceof Error ? rssErr.message : String(rssErr);
        return json({ error: rssMessage }, 502);
      }
    }

    if (items.length === 0) {
      return json({ error: 'Playlist is private, empty, or was not found.' }, 404);
    }

    return json({ items });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return json({ error: `Unexpected error: ${message}` }, 500);
  }
});