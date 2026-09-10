// Receiver assertion logic only. This does NOT simulate or prove a native drag.
import assert from 'node:assert/strict';
const root = new URL('../', import.meta.url);
const html = await Bun.file(new URL('tests/drop-receiver.html', root)).text();
assert.ok(html.includes("connect-src 'none'"));
const elements = new Map();
const document = {querySelector(selector) {
  if (!elements.has(selector)) elements.set(selector, {addEventListener() {}});
  return elements.get(selector);
}};
const window = {};
const receive = new Function('window', 'document', html.match(/<script>([\s\S]*?)<\/script>/)[1] + '\nreturn receive;')(window, document);
const fixture = new File([await Bun.file(new URL('fixtures/Hello bucket.txt', root)).arrayBuffer()], 'Hello bucket.txt');
await receive([fixture], 'assertion unit test', false);
assert.equal(window.dropReport.pass, false);
await receive([], 'assertion unit test', true);
assert.equal(window.dropReport.pass, false);
await receive([new File(['wrong bytes'], 'Hello bucket.txt')], 'assertion unit test', true);
assert.equal(window.dropReport.pass, false);
await receive([fixture], 'assertion unit test', true);
assert.equal(window.dropReport.pass, true);
assert.equal(window.dropReport.received[0].size, 30);
console.log('PASS: offline receiver syntax and assertion logic. NOT native drag evidence.');
