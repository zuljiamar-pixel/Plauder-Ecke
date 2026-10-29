/* Plauderecke: gibt einem Handy für einen Anruf Zugangsdaten zu einem TURN-Server von Cloudflare. */
/* Ein TURN-Server leitet den Anruf weiter, wenn zwei Handys sich nicht direkt finden (oft im Handynetz). */
/* In Supabase als Edge Function mit dem Namen "turn" anlegen, "Verify JWT" ausschalten. */
/* Dazu unter Edge Functions › Secrets: CF_TURN_KEY_ID und CF_TURN_TOKEN (aus Cloudflare › Realtime › TURN). */

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') { return new Response('ok', { headers: cors }); }
  const keyId = Deno.env.get('CF_TURN_KEY_ID');
  const token = Deno.env.get('CF_TURN_TOKEN');
  if (!keyId || !token) { return json({ iceServers: [], ready: false }); }
  try {
    /* Nur wer bei Plauderecke angemeldet ist, bekommt Zugangsdaten */
    const user = await fetch(Deno.env.get('SUPABASE_URL') + '/auth/v1/user', {
      headers: { apikey: req.headers.get('apikey') || '', Authorization: req.headers.get('Authorization') || '' },
    });
    await user.body?.cancel();
    if (!user.ok) { return json({ error: 'not signed in' }, 401); }
    const res = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${keyId}/credentials/generate-ice-servers`, {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ ttl: 6 * 3600 }),
    });
    if (!res.ok) { await res.body?.cancel(); return json({ iceServers: [], ready: false, error: 'cloudflare ' + res.status }); }
    const d = await res.json();
    const list = Array.isArray(d.iceServers) ? d.iceServers : d.iceServers ? [d.iceServers] : [];
    return json({ iceServers: list, ready: true });
  } catch (e) {
    return json({ iceServers: [], ready: false, error: String(e) }, 500);
  }
});
