// Who may trigger the notification endpoints in index.js. firebase-admin is
// replaced with an in-memory fake before the module loads, so nothing real is
// contacted.
const assert = require('assert');
const { EventEmitter } = require('events');
const path = require('path');
const { describe, it, before, after } = require('node:test');

const requestDoc = { requesterId: 'owner', status: 'searching', units: 1, bloodGroups: ['A+'] };
let sendCount = 0;

const fakeAdmin = {
  apps: [{}],
  initializeApp() {},
  firestore: Object.assign(
    () => ({
      collection: (name) => {
        if (name === 'blood_requests') {
          return { doc: (id) => ({ get: async () => ({ exists: id === 'r1', data: () => requestDoc }), update: async () => {} }) };
        }
        if (name === 'users') {
          return {
            where: () => ({ get: async () => ({ size: 0, forEach: () => {} }) }),
            doc: (id) => ({ id, get: async () => ({ exists: id === 'admin1', data: () => ({ isAdmin: true }) }) }),
          };
        }
        return { doc: () => ({ get: async () => ({ exists: false }) }) };
      },
      batch: () => ({ update() {}, commit: async () => {} }),
    }),
    { FieldValue: { arrayUnion: () => 0, increment: () => 0, serverTimestamp: () => 0, arrayRemove: () => 0, delete: () => 0 } },
  ),
  messaging: () => ({ sendEachForMulticast: async (m) => { sendCount += 1; return { successCount: m.tokens.length, failureCount: 0, responses: [] }; } }),
};

const realLog = { log: console.log, warn: console.warn, error: console.error };
let fns;

before(() => {
  console.log = console.warn = console.error = () => {};
  const key = require.resolve(path.join(__dirname, '..', 'node_modules', 'firebase-admin'));
  require.cache[key] = { id: key, filename: key, loaded: true, exports: fakeAdmin };
  fns = require('../index.js');
});
after(() => Object.assign(console, realLog));

describe('exported functions', () => {
  it('exposes the two triggers and the two ways to ask for a notification run', () => {
    for (const name of ['onBloodRequestCreated', 'onBloodRequestUpdated', 'notifyMatchingDonors', 'apiNotifyRequest']) {
      assert.strictEqual(typeof fns[name], 'function', name);
    }
  });
});

describe('notifyMatchingDonors (callable)', () => {
  const call = (request) => fns.notifyMatchingDonors.run(request);

  it('refuses someone who is not signed in', async () => {
    await assert.rejects(call({ data: { requestId: 'r1' } }), (e) => e.code === 'unauthenticated');
  });

  it('refuses a call with no request id', async () => {
    await assert.rejects(call({ auth: { uid: 'owner' }, data: {} }), (e) => e.code === 'invalid-argument');
  });

  it('says so when the request does not exist', async () => {
    await assert.rejects(call({ auth: { uid: 'owner' }, data: { requestId: 'nope' } }), (e) => e.code === 'not-found');
  });

  it('runs for the request\'s owner', async () => {
    const r = await call({ auth: { uid: 'owner' }, data: { requestId: 'r1' } });
    assert.ok(r);
  });

  it('refuses a signed-in user who does not own the request',
    { todo: 'KNOWN GAP: any signed-in user can trigger a notification run for any request' },
    async () => {
      await assert.rejects(call({ auth: { uid: 'stranger' }, data: { requestId: 'r1' } }), (e) => e.code === 'permission-denied');
    });
});

// An Express-like response that resolves once the handler has answered.
function call(handler, { method = 'POST', body = { requestId: 'r1' } } = {}) {
  return new Promise((resolve, reject) => {
    const res = new EventEmitter();
    res.statusCode = 200;
    res.headers = {};
    res.status = (c) => { res.statusCode = c; return res; };
    res.setHeader = (k, v) => { res.headers[k] = v; };
    res.getHeader = (k) => res.headers[k];
    res.set = res.setHeader;
    res.writeHead = (c) => { res.statusCode = c; return res; };
    const done = (b) => { res.body = b; resolve(res); return res; };
    res.json = done;
    res.send = done;
    res.end = done;
    const req = Object.assign(new EventEmitter(), {
      method,
      body,
      query: {},
      url: '/',
      headers: { origin: 'https://example.com' },
      get: () => undefined,
    });
    Promise.resolve(handler(req, res)).catch(reject);
    setTimeout(() => reject(new Error('handler never answered')), 3000).unref();
  });
}

describe('apiNotifyRequest (public HTTP endpoint)', () => {
  it('only accepts POST', async () => {
    assert.strictEqual((await call(fns.apiNotifyRequest, { method: 'GET' })).statusCode, 405);
  });

  it('needs a request id', async () => {
    assert.strictEqual((await call(fns.apiNotifyRequest, { body: {} })).statusCode, 400);
  });

  it('says so when the request does not exist', async () => {
    assert.strictEqual((await call(fns.apiNotifyRequest, { body: { requestId: 'nope' } })).statusCode, 404);
  });

  it('refuses an anonymous caller',
    { todo: 'KNOWN SECURITY HOLE: apiNotifyRequest has no authentication, so anyone on the internet can trigger notification runs' },
    async () => {
      const res = await call(fns.apiNotifyRequest);
      assert.ok([401, 403].includes(res.statusCode), `got HTTP ${res.statusCode}`);
    });
});
