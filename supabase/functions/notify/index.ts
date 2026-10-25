/* Plauderecke: verschickt Benachrichtigungen aufs Handy, sobald jemand in einer Gruppe schreibt. */
/* In Supabase als Edge Function mit dem Namen "notify" anlegen, "Verify JWT" ausschalten. */
/* Der Code kommt ohne Zeilenkommentare aus, damit er auch funktioniert, wenn beim Einfügen die Zeilenumbrüche verloren gehen. */

const SUBJECT = 'https://zuljiamar-pixel.github.io/Plauder-Ecke/';
const enc = new TextEncoder();

export function b64uEnc(buf: any): string {
  const bytes = new Uint8Array(buf);
  let s = '';
  for (let i = 0; i < bytes.length; i++) { s += String.fromCharCode(bytes[i]); }
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function b64uDec(str: string): Uint8Array {
  const s = atob(str.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((str.length + 3) % 4));
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) { out[i] = s.charCodeAt(i); }
  return out;
}

function concat(...parts: Uint8Array[]): Uint8Array {
  let len = 0;
  for (const p of parts) { len += p.length; }
  const out = new Uint8Array(len);
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}

async function hkdf(salt: Uint8Array, ikm: Uint8Array, info: Uint8Array, len: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info }, key, len * 8));
}

/* Ein neues Schlüsselpaar für den Absender (VAPID, RFC 8292) */
export async function makeVapidKeys(): Promise<any> {
  const k: any = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const pub = await crypto.subtle.exportKey('raw', k.publicKey);
  const jwk = await crypto.subtle.exportKey('jwk', k.privateKey);
  return { publicKey: b64uEnc(pub), privateJwk: JSON.stringify(jwk) };
}

export async function vapidHeader(endpoint: string, publicKey: string, privateJwk: string): Promise<string> {
  const aud = new URL(endpoint).origin;
  const head = b64uEnc(enc.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const claims = b64uEnc(enc.encode(JSON.stringify({ aud, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: SUBJECT })));
  const key = await crypto.subtle.importKey('jwk', JSON.parse(privateJwk), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(head + '.' + claims));
  return 'vapid t=' + head + '.' + claims + '.' + b64uEnc(sig) + ', k=' + publicKey;
}

/* Verschlüsselt den Inhalt für genau ein Handy (aes128gcm, RFC 8291) */
export async function encryptPayload(p256dh: string, auth: string, text: string): Promise<Uint8Array> {
  const uaPublic = b64uDec(p256dh);
  const authSecret = b64uDec(auth);
  const local: any = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const asPublic = new Uint8Array(await crypto.subtle.exportKey('raw', local.publicKey));
  const uaKey = await crypto.subtle.importKey('raw', uaPublic, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, local.privateKey, 256));
  const ikm = await hkdf(authSecret, shared, concat(enc.encode('WebPush: info\0'), uaPublic, asPublic), 32);
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(salt, ikm, enc.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, enc.encode('Content-Encoding: nonce\0'), 12);
  const key = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);
  const cipher = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, key, concat(enc.encode(text), new Uint8Array([2]))));
  const header = new Uint8Array(21 + asPublic.length);
  header.set(salt, 0);
  new DataView(header.buffer).setUint32(16, 4096);
  header[20] = asPublic.length;
  header.set(asPublic, 21);
  return concat(header, cipher);
}

export async function sendPush(sub: any, text: string, cfg: any): Promise<number> {
  const body = await encryptPayload(sub.p256dh, sub.auth, text);
  const res = await fetch(sub.endpoint, {
    method: 'POST',
    headers: {
      'Content-Encoding': 'aes128gcm',
      'Content-Type': 'application/octet-stream',
      'TTL': '86400',
      'Urgency': 'high',
      'Authorization': await vapidHeader(sub.endpoint, cfg.vapid_public, cfg.vapid_private),
    },
    body,
  });
  await res.body?.cancel();
  return res.status;
}

/* ---------- server ---------- */
import postgres from 'npm:postgres@3.4.5';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};
let db: any = null;
let cached: any = null;

async function config(): Promise<any> {
  if (cached) { return cached; }
  if (!db) { db = postgres(Deno.env.get('SUPABASE_DB_URL') as string, { prepare: false, max: 3 }); }
  await db`insert into public.push_config (id) values (1) on conflict (id) do nothing`;
  let rows = await db`select secret, vapid_public, vapid_private from public.push_config where id = 1`;
  if (!rows[0].vapid_public) {
    const k = await makeVapidKeys();
    await db`update public.push_config set vapid_public = ${k.publicKey}, vapid_private = ${k.privateJwk} where id = 1 and vapid_public is null`;
    rows = await db`select secret, vapid_public, vapid_private from public.push_config where id = 1`;
  }
  cached = rows[0];
  return cached;
}

function label(m: any): string {
  const extra = m.text ? ' ' + String(m.text) : '';
  if (m.kind === 'audio') { return '🎤 Sprachnachricht'; }
  if (m.kind === 'video') { return '🎬 Video' + extra; }
  if (m.kind === 'image') { return '📷 Foto' + extra; }
  return String(m.text || '');
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') { return new Response('ok', { headers: cors }); }
  try {
    const cfg = await config();
    if (req.method === 'GET') {
      return new Response(JSON.stringify({ publicKey: cfg.vapid_public }), { headers: { ...cors, 'Content-Type': 'application/json' } });
    }
    if (req.headers.get('x-plauder-secret') !== cfg.secret) { return new Response('forbidden', { status: 403, headers: cors }); }
    const m = (await req.json()).message;
    const rows = await db`
      select s.endpoint, s.p256dh, s.auth, g.name as group_name, coalesce(snd.name, 'Jemand') as sender
      from public.members mem
      join public.push_subscriptions s on s.user_id = mem.user_id
      join public.groups g on g.id = mem.group_id
      left join public.members snd on snd.group_id = mem.group_id and snd.user_id = ${m.user_id}::uuid
      where mem.group_id = ${m.group_id}::uuid and mem.user_id <> ${m.user_id}::uuid`;
    let sent = 0;
    let removed = 0;
    await Promise.all(rows.map(async (r: any) => {
      const payload = JSON.stringify({ title: r.group_name, body: (r.sender + ': ' + label(m)).slice(0, 200), group: m.group_id });
      try {
        const status = await sendPush(r, payload, cfg);
        if (status === 404 || status === 410) { await db`delete from public.push_subscriptions where endpoint = ${r.endpoint}`; removed++; }
        else if (status < 300) { sent++; }
      } catch (_e) { /* ein Handy, das nicht antwortet, hält die anderen nicht auf */ }
    }));
    return new Response(JSON.stringify({ sent, removed }), { headers: { ...cors, 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } });
  }
});
