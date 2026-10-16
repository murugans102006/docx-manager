const test = require('node:test');
const assert = require('node:assert/strict');
const app = require('../src/app');

test('health and centralized error responses use the documented envelope', async (t) => {
  const server = app.listen(0);
  t.after(() => new Promise((resolve) => server.close(resolve)));
  await new Promise((resolve) => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;

  const health = await fetch(`${base}/health`);
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { success: true, data: { status: 'ok' } });

  const missing = await fetch(`${base}/not-a-route`);
  assert.equal(missing.status, 404);
  const payload = await missing.json();
  assert.equal(payload.success, false);
  assert.equal(payload.error.code, 'NOT_FOUND');
  assert.equal(typeof payload.error.message, 'string');
});
