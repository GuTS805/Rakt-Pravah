// Tests for the pushes sent after a request goes out: accept, can't make it,
// cancel/expire, and chat. Firestore and FCM are in-memory fakes.
const assert = require('assert');
const { describe, it, before, after } = require('node:test');
const { requestUpdatePushes, chatPushes, sendPushes } = require('../updates');

const realLog = { log: console.log, warn: console.warn, error: console.error };
before(() => { console.log = console.warn = console.error = () => {}; });
after(() => Object.assign(console, realLog));

const base = {
  requesterId: 'req',
  destination: { name: 'City Hospital' },
  status: 'searching',
  acceptedDonorIds: [],
  acceptedDonors: [],
};
const withDonor = {
  ...base,
  status: 'donorAccepted',
  acceptedDonorIds: ['d1'],
  acceptedDonors: [{ id: 'd1', name: 'Anirudh' }],
};

describe('requestUpdatePushes', () => {
  it('tells the requester who accepted', () => {
    const out = requestUpdatePushes(base, withDonor);
    assert.deepStrictEqual(out.map((p) => p.uid), ['req']);
    assert.match(out[0].title, /Anirudh accepted/);
    assert.match(out[0].body, /City Hospital/);
    assert.strictEqual(out[0].type, 'request');
  });

  it("tells the requester when a donor can't make it", () => {
    const out = requestUpdatePushes(withDonor, { ...base, declinedByDonorIds: ['d1'] });
    assert.strictEqual(out.length, 1);
    assert.strictEqual(out[0].uid, 'req');
    assert.match(out[0].title, /can't make it/);
  });

  for (const [status, word] of [['cancelled', 'cancelled'], ['expired', 'expired'], ['removedByAdmin', 'removed']]) {
    it(`tells accepted donors the request was ${word}`, () => {
      const out = requestUpdatePushes(withDonor, { ...withDonor, status });
      assert.deepStrictEqual(out.map((p) => p.uid), ['d1']);
      assert.match(out[0].body, new RegExp(word));
      assert.match(out[0].body, /don't need to go/);
      assert.strictEqual(out[0].type, 'invitation');
    });
  }

  it('says nothing when the request is fulfilled', () => {
    assert.deepStrictEqual(requestUpdatePushes(withDonor, { ...withDonor, status: 'fulfilled' }), []);
  });

  it('says nothing on a cancel nobody accepted', () => {
    assert.deepStrictEqual(requestUpdatePushes(base, { ...base, status: 'cancelled' }), []);
  });

  it('says nothing when only tracking changes', () => {
    const moved = { ...withDonor, donorLiveLocations: { d1: { lat: 1, lng: 2 } } };
    assert.deepStrictEqual(requestUpdatePushes(withDonor, moved), []);
  });

  it('does not repeat a cancel on later edits of a cancelled request', () => {
    const cancelled = { ...withDonor, status: 'cancelled' };
    assert.deepStrictEqual(requestUpdatePushes(cancelled, { ...cancelled, note: 'x' }), []);
  });
});

describe('chatPushes', () => {
  const request = { requesterId: 'req', acceptedDonorIds: ['d1', 'd2'] };

  it('goes to everyone in the chat but the sender', () => {
    const out = chatPushes(request, { senderId: 'd1', senderName: 'Anirudh', text: 'On my way' });
    assert.deepStrictEqual(out.map((p) => [p.uid, p.type]), [['req', 'request'], ['d2', 'chat']]);
    assert.strictEqual(out[0].title, '💬 Anirudh');
    assert.strictEqual(out[0].body, 'On my way');
  });

  it('shortens long messages', () => {
    const out = chatPushes(request, { senderId: 'req', senderName: 'A', text: 'x'.repeat(300) });
    assert.strictEqual(out[0].body.length, 120);
  });
});

describe('sendPushes', () => {
  function fakeAdmin(users, fail = new Set()) {
    const sent = [];
    const updates = [];
    const db = {
      collection: () => ({
        doc: (id) => ({
          get: async () => ({ exists: id in users, data: () => users[id] }),
          update: async (d) => updates.push({ id, d }),
        }),
      }),
    };
    const firestore = () => db;
    firestore.FieldValue = {
      arrayRemove: (...v) => ({ op: 'arrayRemove', v }),
      delete: () => ({ op: 'delete' }),
    };
    return {
      sent,
      updates,
      admin: {
        firestore,
        messaging: () => ({
          sendEachForMulticast: async (m) => {
            sent.push(m);
            const responses = m.tokens.map((t) => fail.has(t)
              ? { success: false, error: { code: 'messaging/registration-token-not-registered' } }
              : { success: true });
            return { successCount: responses.filter((r) => r.success).length, responses };
          },
        }),
      },
    };
  }

  it('sends a push a closed app can show and open', async () => {
    const f = fakeAdmin({ req: { fcmTokenList: ['t1'] } });
    await sendPushes(f.admin, 'R1', [{ uid: 'req', title: 'T', body: 'B', type: 'request' }], 'request');
    const m = f.sent[0];
    assert.deepStrictEqual(m.tokens, ['t1']);
    assert.strictEqual(m.notification.title, 'T');
    assert.strictEqual(m.android.priority, 'high');
    assert.strictEqual(m.android.notification.channelId, 'bloodlink_alerts');
    assert.strictEqual(m.android.notification.clickAction, undefined);
    assert.strictEqual(m.android.notification.tag, 'request_R1');
    assert.deepStrictEqual(m.data, { type: 'request', requestId: 'R1', route: '/requests/R1' });
  });

  it("opens a donor's chat", async () => {
    const f = fakeAdmin({ d: { fcmTokenList: ['t'] } });
    await sendPushes(f.admin, 'R1', [{ uid: 'd', title: 'T', body: 'B', type: 'chat' }], 'chat');
    assert.strictEqual(f.sent[0].data.route, '/requests/R1/chat');
    assert.strictEqual(f.sent[0].android.notification.tag, 'chat_R1');
  });

  it('skips people with no devices and removes dead tokens', async () => {
    const f = fakeAdmin({ a: {}, b: { fcmTokenList: ['good', 'dead'] } }, new Set(['dead']));
    await sendPushes(f.admin, 'R1', [
      { uid: 'a', title: 'T', body: 'B', type: 'invitation' },
      { uid: 'missing', title: 'T', body: 'B', type: 'invitation' },
      { uid: 'b', title: 'T', body: 'B', type: 'invitation' },
    ], 'chat');
    assert.strictEqual(f.sent.length, 1);
    assert.strictEqual(f.updates.length, 1);
    assert.strictEqual(f.updates[0].id, 'b');
    assert.deepStrictEqual(f.updates[0].d.fcmTokenList.v, ['dead']);
  });
});
