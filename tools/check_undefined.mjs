import { readFileSync } from 'node:fs';
const s = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const m = /<script[^>]*>([\s\S]*?)<\/script>/g; let sc = '', x;
while ((x = m.exec(s))) if (x[1].trim()) sc = x[1];
const defs = new Set([...sc.matchAll(/\b(?:function|const|let|var|class)\s+([A-Za-z_$][\w$]*)/g)].map(r => r[1]));
const calls = new Set([...sc.matchAll(/(?:^|[^\.\w$'"`])([A-Za-z_$][\w$]*)\s*\(/g)].map(r => r[1]));
const builtin = new Set(['if','for','while','switch','catch','return','function','typeof','new','delete','await','async','do','else','try','void',
  'Promise','Object','Array','String','Number','Boolean','Math','JSON','Date','Set','Map','WeakMap','RegExp','Error','TypeError','RangeError',
  'fetch','alert','confirm','prompt','document','window','localStorage','sessionStorage','location','history','navigator',
  'setTimeout','setInterval','clearTimeout','clearInterval','requestAnimationFrame','queueMicrotask',
  'console','encodeURIComponent','decodeURIComponent','parseInt','parseFloat','isNaN','isFinite','structuredClone','AbortController',
  'URL','URLSearchParams','FormData','Blob','File','FileReader','Image','Audio','MediaRecorder','Notification','WebSocket','Worker',
  'createImageBitmap','CustomEvent','Intl','Proxy','Reflect','Symbol','BigInt','escape','unescape']);
const missing = [...calls].filter(n => !defs.has(n) && !builtin.has(n));
console.log('called but never defined:', missing.join(', ') || '(none)');
