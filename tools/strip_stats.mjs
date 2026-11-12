// Keeps stats (s) only for containers; keeps official class (k) everywhere.
import { readFileSync, writeFileSync } from 'node:fs';
const items = JSON.parse(readFileSync(new URL('../catalog.json', import.meta.url), 'utf8'));
const out = JSON.stringify(items.map(x => {
  const o = { i: x.i, c: x.c, n: x.n, e: x.e, r: x.r, p: x.p };
  if (x.sl != null) o.sl = x.sl;
  if (x.c === 'containers' && x.s) o.s = x.s;
  if (x.cl) o.cl = x.cl;
  if (x.k) o.k = x.k;
  return o;
}));
writeFileSync(new URL('../catalog.json', import.meta.url), out);
console.log('bytes:', out.length, '| items:', items.length, '| with stats:', items.filter(x => x.s && x.c === 'containers').length);
