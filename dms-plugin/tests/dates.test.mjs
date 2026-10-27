// node dates.test.mjs ~/.config/DankMaterialShell/plugins/Daiban/Dates.js
import fs from 'fs';
import assert from 'assert/strict';
const src = fs.readFileSync(process.argv[2], 'utf8').replace(/^\.pragma library\s*/, '');
const D = new Function(src + '; return {parseQuickAdd, friendly, wall, iso, set: v => { fixedNow = v; }};')();
const OFF = 480; // 北京
// 2026-10-23 10:00 北京时间（周五）
D.set(Date.UTC(2026, 9, 23, 2, 0));
const W = (y, m, d, h = 23, mi = 59) => new Date(Date.UTC(y, m - 1, d, h, mi)).getTime();
const due = s => D.parseQuickAdd(s, OFF).due?.getTime() ?? null;

let r = D.parseQuickAdd('明天下午3点 改报价 !3 +商城 *客户', OFF);
assert.equal(r.title, '改报价'); assert.equal(r.due.getTime(), W(2026,10,24,15,0));
assert.equal(r.priority, 3); assert.equal(r.project, '商城'); assert.deepEqual(r.labels, ['客户']);
assert.equal(D.parseQuickAdd('后天交周报', OFF).title, '交周报');
assert.equal(due('后天交周报'), W(2026,10,25));
assert.equal(new Date(due('周五 复盘')).getUTCDate(), 23);
assert.equal(new Date(due('周一 开会')).getUTCDate(), 26);
assert.equal(new Date(due('下周三 续服务器')).getUTCDate(), 28);
assert.equal(due('11月2日 9:30 面试'), W(2026,11,2,9,30));
assert.equal(due('1/5 年检'), W(2027,1,5));
assert.equal(due('今晚 打电话'), W(2026,10,23,20,0));
r = D.parseQuickAdd('买 3 箱水', OFF); assert.equal(r.title, '买 3 箱水'); assert.equal(r.due, null);
// 时区换算：服务器时间 ↔ 北京墙上时间
assert.equal(D.wall('2026-10-23T23:59:00+08:00', OFF).getTime(), W(2026,10,23));
assert.equal(D.iso(new Date(W(2026,10,23)), OFF), '2026-10-23T15:59:00.000Z');
assert.equal(D.friendly(new Date(W(2026,10,24,15,0)), OFF), '明天 15:00');
console.log('全部通过');
