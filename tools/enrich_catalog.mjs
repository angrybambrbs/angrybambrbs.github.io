// Enriches catalog.json with item stats and official class from EXBO stalzone-database.
// Usage: node tools/enrich_catalog.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const RAW = 'https://raw.githubusercontent.com/EXBO-Studio/stalzone-database/main/global/items/';
const SRC = readFileSync(new URL('../catalog.json', import.meta.url), 'utf8');
const catalog = JSON.parse(SRC);
const items = Array.isArray(catalog) ? catalog : catalog.items;

const txt = v => (v == null ? '' : String(v).trim());
const lines = o => (o && o.lines && o.lines.ru) || null;

function parseItem(j) {
  const out = { s: [], k: null };
  for (const block of j.infoBlocks || []) {
    for (const e of block.elements || []) {
      if (e.type === 'numeric') {
        const name = lines(e.name), v = e.value;
        if (!name || v == null) continue;
        if (/Ранг|Ремонт/i.test(name)) continue;
        let val = typeof v === 'number' ? (Math.round(v * 100) / 100).toString() : txt(v);
        if (/^(Вес|Переносимый вес)$/.test(name) && /^\d+(\.\d+)?$/.test(val)) val += ' кг';
        out.s.push([name, val]);
      } else if (e.type === 'key-value') {
        const name = lines(e.key), val = lines(e.value);
        if (!name || !val) continue;
        if (/^Класс/i.test(name)) out.k = val.replace(/ые$/, 'ая').replace(/Смешанная$/, 'Смешанная');
        else if (/^Ранг/i.test(name)) { /* already have r */ }
        else out.s.push([name, val]);
      }
    }
  }
  // drop exact duplicate stat rows
  const seen = new Set();
  out.s = out.s.filter(([n, v]) => { const key = n + '=' + v; if (seen.has(key)) return false; seen.add(key); return true; });
  return out;
}

// 1. item paths are derivable from the catalog itself: global/items/<c>/<id>.json
const paths = items.map(x => 'global/items/' + x.c + '/' + x.i + '.json');
console.log('item files:', paths.length);

// 2. download and merge by id
const byId = Object.fromEntries(items.map(x => [x.i, x]));
let ok = 0, miss = 0, cls = {};
for (const p of paths) {
  const id = p.split('/').pop().replace('.json', '');
  const j = await fetch(RAW + p.slice('global/items/'.length)).then(r => r.ok ? r.json() : null);
  if (!j) { miss++; continue; }
  const { s, k } = parseItem(j);
  const it = byId[id];
  if (!it) { miss++; continue; }
  if (s.length) it.s = s;
  if (k) { it.k = k; cls[k] = (cls[k] || 0) + 1; }
  ok++;
}
console.log('merged:', ok, 'missing:', miss, 'classes:', JSON.stringify(cls));

// 3. key order: i,c,n,e,r,p,sl,s,cl,k
const out = JSON.stringify(items.map(x => {
  const o = { i: x.i, c: x.c, n: x.n, e: x.e, r: x.r, p: x.p };
  if (x.sl != null) o.sl = x.sl;
  if (x.s) o.s = x.s;
  if (x.cl) o.cl = x.cl;
  if (x.k) o.k = x.k;
  return o;
}));
writeFileSync(new URL('../catalog.json', import.meta.url), out);
console.log('written, bytes:', out.length);
