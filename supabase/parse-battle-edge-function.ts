// Supabase Edge Function "parse-battle" — распознавание скриншота боя через Gemini.
// Устойчива к перегрузке: 3 попытки на модель + fallback на резервные модели.
// Секреты: GEMINI_API_KEY (или GOOGLE_API_KEY), SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY подставляются автоматически.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MODELS = ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-flash-latest'];

const PROMPT = `Ты получаешь скриншот экрана «Сводка с поля боя» из игры STALZONE.
Найди таблицу игроков и верни ТОЛЬКО JSON без пояснений в формате:
{"team":"название клана игрока если видно","place":место клана или null,"team_score":очки клана или null,"timer":"время боя если видно",
"teams":[{"name":"название","score":0,"place":0}],
"players":[{"nick":"ник","kills":0,"deaths":0,"assists":0,"score":0,"treasury":0,"rank":"ранг если видно"}]}
Правила: числа — целые; если поле не видно, ставь null; не выдумывай данные; включай всех игроков из таблицы.`;

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const json = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Только POST' }, 405);
  try {
    const apiKey = Deno.env.get('GEMINI_API_KEY') || Deno.env.get('GOOGLE_API_KEY');
    if (!apiKey) return json({ error: 'Секрет GEMINI_API_KEY не задан в проекте' }, 500);

    const body = await req.json();
    const { clan_id, image, mime } = body || {};
    if (!clan_id || !image) return json({ error: 'Нет clan_id или изображения' }, 400);

    // проверяем, что вызывающий — владелец или офицер клана
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: ud } = await admin.auth.getUser(token);
    const uid = ud?.user?.id;
    if (!uid) return json({ error: 'Не авторизован' }, 401);
    const { data: mem } = await admin.from('clan_members')
      .select('role').eq('user_id', uid).eq('clan_id', clan_id).maybeSingle();
    if (!mem || !['owner', 'officer'].includes(mem.role)) return json({ error: 'Нет прав: бой вносят владелец и офицеры' }, 403);

    const payload = {
      contents: [{ parts: [{ text: PROMPT }, { inline_data: { mime_type: mime || 'image/jpeg', data: image } }] }],
      generationConfig: { temperature: 0, responseMimeType: 'application/json' },
    };

    let lastErr = 'нет ответа';
    for (const model of MODELS) {
      for (let attempt = 0; attempt < 3; attempt++) {
        const r = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
          { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) }
        );
        if ([500, 503, 429].includes(r.status)) {
          lastErr = `${model}: HTTP ${r.status}`;
          await sleep(1500 * (attempt + 1)); // 1.5с, 3с, 4.5с
          continue;
        }
        const j = await r.json().catch(() => null);
        const text: string = j?.candidates?.[0]?.content?.parts?.map((p: any) => p.text || '').join('') || '';
        if (!r.ok || !text) { lastErr = `${model}: ${j?.error?.message || 'пустой ответ'}`; continue; }
        try {
          const parsed = JSON.parse(text.replace(/```json|```/g, '').trim());
          return json(parsed); // контракт UI: {players:[...], teams:[...], place, team_score, timer, team}
        } catch {
          lastErr = `${model}: ответ не JSON`;
        }
      }
    }
    return json({ error: 'Gemini перегружен, попробуй через минуту (' + lastErr + ')' }, 502);
  } catch (e) {
    return json({ error: String(e?.message || e) }, 500);
  }
});
