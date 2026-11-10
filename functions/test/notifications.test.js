// Tests for the push-notification flow: which donors are alerted for a
// request, what is sent, and what is recorded afterwards. Firestore and FCM
// are replaced with in-memory fakes, so no emulator is needed.
const assert = require('assert');
const { describe, it, before, after } = require('node:test');
const { processBloodRequestNotifications, evaluateDonorEligibility } = require('../matcher');

// Keep the service's own logging out of the test report.
const realLog = { log: console.log, warn: console.warn, error: console.error };
before(() => { console.log = console.warn = console.error = () => {}; });
after(() => Object.assign(console, realLog));

// A fake `admin` with just the surface the matcher touches.
function fakeAdmin({ users = [], config = null, send } = {}) {
  const sent = [];
  const requestUpdates = [];
  const pruned = [];
  const db = {
    collection(name) {
      if (name === 'config') {
        return { doc: () => ({ get: async () => ({ exists: !!config, data: () => config }) }) };
      }
      if (name === 'users') {
        return {
          where: () => ({
            get: async () => ({
              size: users.length,
              forEach: (fn) => users.forEach((u) => fn({ id: u.id, data: () => u.data })),
            }),
          }),
          doc: (id) => ({ id }),
        };
      }
      return { doc: (id) => ({ update: async (d) => { requestUpdates.push({ id, d }); } }) };
    },
    batch: () => ({
      update: (ref, d) => pruned.push({ userId: ref.id, d }),
      commit: async () => {},
    }),
  };
  const firestore = () => db;
  firestore.FieldValue = {
    arrayRemove: (v) => ({ op: 'arrayRemove', v }),
    arrayUnion: (...v) => ({ op: 'arrayUnion', v }),
    increment: (n) => ({ op: 'increment', n }),
    delete: () => ({ op: 'delete' }),
    serverTimestamp: () => ({ op: 'serverTimestamp' }),
  };
  const admin = {
    firestore,
    messaging: () => ({
      sendEachForMulticast: async (msg) => {
        sent.push(msg);
        if (send) return send(msg);
        return { successCount: msg.tokens.length, failureCount: 0, responses: msg.tokens.map(() => ({ success: true })) };
      },
    }),
  };
  return { admin, sent, requestUpdates, pruned };
}

const donor = (id, group, extra = {}) => ({
  id,
  data: {
    name: id,
    phoneVerified: true,
    latitude: 18.53,
    longitude: 73.86,
    fcmTokenList: [`tok_${id}`],
    donor: { availability: 'available', bloodGroup: group, maxDistanceKm: 30, notifyPush: true },
    ...extra,
  },
});

const request = (extra = {}) => ({
  requesterId: 'requester',
  status: 'searching',
  urgency: 'urgent',
  units: 2,
  patientBloodGroup: 'A+',
  bloodGroups: ['A+', 'O+'],
  acceptedDonorIds: [],
  declinedByDonorIds: [],
  notifiedDonorIds: [],
  destination: { name: 'Pune City Hospital', location: { lat: 18.5204, lng: 73.8567 } },
  ...extra,
});

const tokensSent = (sent) => sent.flatMap((m) => m.tokens).sort();

describe('which requests are processed', () => {
  it('skips a request that is no longer searching', async () => {
    const f = fakeAdmin({ users: [donor('d1', 'A+')] });
    const r = await processBloodRequestNotifications(f.admin, 'r1', request({ status: 'cancelled' }));
    assert.strictEqual(r.skipped, true);
    assert.strictEqual(f.sent.length, 0);
  });

  it('skips a request with no data', async () => {
    const f = fakeAdmin({ users: [donor('d1', 'A+')] });
    const r = await processBloodRequestNotifications(f.admin, 'r1', null);
    assert.strictEqual(r.skipped, true);
  });

  it('skips a request whose every unit already has a donor', async () => {
    const f = fakeAdmin({ users: [donor('d2', 'A+')] });
    const r = await processBloodRequestNotifications(f.admin, 'r1', request({ units: 1, acceptedDonorIds: ['d1'] }));
    assert.strictEqual(r.skipped, true);
    assert.strictEqual(r.reason, 'Fully accepted');
    assert.strictEqual(f.sent.length, 0);
  });

  it('keeps alerting while a multi-unit request still has room', async () => {
    const f = fakeAdmin({ users: [donor('d2', 'A+')] });
    const r = await processBloodRequestNotifications(f.admin, 'r1', request({ units: 2, acceptedDonorIds: ['d1'] }));
    assert.strictEqual(r.notifiedCount, 1);
  });
});

describe('who is alerted', () => {
  it('only donors of a group the requester chose', async () => {
    const f = fakeAdmin({ users: [donor('a', 'A+'), donor('o', 'O+'), donor('oneg', 'O-'), donor('b', 'B+')] });
    await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.deepStrictEqual(tokensSent(f.sent), ['tok_a', 'tok_o']);
  });

  it('never the requester, even if they are a matching donor', async () => {
    const f = fakeAdmin({ users: [donor('requester', 'A+'), donor('a', 'A+')] });
    await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.deepStrictEqual(tokensSent(f.sent), ['tok_a']);
  });

  it('not a donor who already accepted or declined', async () => {
    const f = fakeAdmin({ users: [donor('acc', 'A+'), donor('dec', 'A+'), donor('new', 'A+')] });
    await processBloodRequestNotifications(f.admin, 'r1', request({ acceptedDonorIds: ['acc'], declinedByDonorIds: ['dec'] }));
    assert.deepStrictEqual(tokensSent(f.sent), ['tok_new']);
  });

  it('not a donor already notified for this request', async () => {
    const f = fakeAdmin({ users: [donor('seen', 'A+'), donor('new', 'A+')] });
    await processBloodRequestNotifications(f.admin, 'r1', request({ notifiedDonorIds: ['seen'] }));
    assert.deepStrictEqual(tokensSent(f.sent), ['tok_new']);
  });

  it('not a donor outside their own radius', async () => {
    const far = donor('far', 'A+', { latitude: 19.076, longitude: 72.8777 }); // Mumbai
    const f = fakeAdmin({ users: [far, donor('near', 'A+')] });
    await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.deepStrictEqual(tokensSent(f.sent), ['tok_near']);
  });

  it('not a disabled or inactive account, or one without a verified phone', async () => {
    const f = fakeAdmin({
      users: [donor('dis', 'A+', { disabled: true }), donor('ina', 'A+', { isActive: false }), donor('unv', 'A+', { phoneVerified: false }), donor('none', 'A+', { phoneVerified: undefined }), donor('ok', 'A+')],
    });
    await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.deepStrictEqual(tokensSent(f.sent), ['tok_ok']);
  });

  it('not a donor who has switched push off, or wants critical requests only', async () => {
    const off = donor('off', 'A+');
    off.data.donor.notifyPush = false;
    const crit = donor('crit', 'A+');
    crit.data.donor.notifyCritical = true;
    const f = fakeAdmin({ users: [off, crit, donor('ok', 'A+')] });
    await processBloodRequestNotifications(f.admin, 'r1', request({ urgency: 'urgent' }));
    assert.deepStrictEqual(tokensSent(f.sent), ['tok_ok']);
  });

  it('a critical-only donor is alerted for a critical request', async () => {
    const crit = donor('crit', 'A+');
    crit.data.donor.notifyCritical = true;
    const f = fakeAdmin({ users: [crit] });
    await processBloodRequestNotifications(f.admin, 'r1', request({ urgency: 'critical' }));
    assert.deepStrictEqual(tokensSent(f.sent), ['tok_crit']);
  });

  it('not a donor with no registered device', async () => {
    const f = fakeAdmin({ users: [donor('none', 'A+', { fcmTokenList: [] }), donor('ok', 'A+')] });
    await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.deepStrictEqual(tokensSent(f.sent), ['tok_ok']);
  });

  it('every device of a matched donor is alerted', async () => {
    const two = donor('two', 'A+', { fcmTokenList: ['phone', 'tablet'] });
    const f = fakeAdmin({ users: [two] });
    await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.deepStrictEqual(tokensSent(f.sent), ['phone', 'tablet']);
  });

  it('sends nothing when nobody matches', async () => {
    const f = fakeAdmin({ users: [donor('b', 'B+')] });
    const r = await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.strictEqual(f.sent.length, 0);
    assert.strictEqual(r.notifiedCount, 0);
  });
});

describe('cooldown from the operators\' settings', () => {
  const recent = () => {
    const d = donor('recent', 'A+');
    d.data.donor.lastDonation = new Date(Date.now() - 30 * 24 * 3600 * 1000);
    return d;
  };

  it('a donor inside the cooldown is left alone', async () => {
    const f = fakeAdmin({ users: [recent()] });
    await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.strictEqual(f.sent.length, 0);
  });

  it('the cooldown can be switched off in config/app', async () => {
    const f = fakeAdmin({ users: [recent()], config: { cooldownEnabled: false } });
    await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.deepStrictEqual(tokensSent(f.sent), ['tok_recent']);
  });

  it('the cooldown length can be changed in config/app', async () => {
    const f = fakeAdmin({ users: [recent()], config: { cooldownDays: 15 } });
    await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.deepStrictEqual(tokensSent(f.sent), ['tok_recent']);
  });
});

describe('what is sent', () => {
  it('names the request and the route to open it', async () => {
    const f = fakeAdmin({ users: [donor('a', 'A+')] });
    await processBloodRequestNotifications(f.admin, 'req42', request());
    const m = f.sent[0];
    assert.strictEqual(m.data.requestId, 'req42');
    assert.strictEqual(m.data.route, '/invitations/req42');
    assert.strictEqual(m.data.type, 'invitation');
    assert.match(m.notification.body, /A\+/);
    assert.match(m.notification.body, /Pune City Hospital/);
  });

  it('calls an urgent request urgent and a critical one critical', async () => {
    const urgent = fakeAdmin({ users: [donor('a', 'A+')] });
    await processBloodRequestNotifications(urgent.admin, 'r1', request({ urgency: 'urgent' }));
    assert.match(urgent.sent[0].notification.title, /Urgent/);
    const critical = fakeAdmin({ users: [donor('a', 'A+')] });
    await processBloodRequestNotifications(critical.admin, 'r1', request({ urgency: 'critical' }));
    assert.match(critical.sent[0].notification.title, /Critical/);
  });

  it('says platelets when platelets are needed', async () => {
    const f = fakeAdmin({ users: [donor('a', 'A+')] });
    await processBloodRequestNotifications(f.admin, 'r1', request({ bloodType: 'Platelets' }));
    assert.match(f.sent[0].notification.body, /platelets/);
  });

  it('does not put the patient or requester contact details in the push', async () => {
    const f = fakeAdmin({ users: [donor('a', 'A+')] });
    await processBloodRequestNotifications(f.admin, 'r1', request({ phone: '9876543210', fullPhoneNumber: '+919876543210', patientName: 'Sunil', requesterName: 'Ravi' }));
    const payload = JSON.stringify(f.sent[0]);
    for (const secret of ['9876543210', 'Sunil', 'Ravi']) assert(!payload.includes(secret), `push leaked ${secret}`);
  });

  it('splits a large audience into batches of at most 500 devices', async () => {
    const many = Array.from({ length: 1100 }, (_, i) => donor(`d${i}`, 'A+'));
    const f = fakeAdmin({ users: many });
    const r = await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.deepStrictEqual(f.sent.map((m) => m.tokens.length), [500, 500, 100]);
    assert.strictEqual(r.notifiedCount, 1100);
  });
});

describe('what is recorded afterwards', () => {
  it('stores who was notified and how many were contacted', async () => {
    const f = fakeAdmin({ users: [donor('a', 'A+'), donor('o', 'O+')] });
    await processBloodRequestNotifications(f.admin, 'r1', request());
    const update = f.requestUpdates.find((u) => u.id === 'r1').d;
    assert.deepStrictEqual(update.notifiedDonorIds.v.sort(), ['a', 'o']);
    assert.deepStrictEqual(update.donorsContacted, { op: 'increment', n: 2 });
  });

  it('writes nothing when no push got through', async () => {
    const f = fakeAdmin({
      users: [donor('a', 'A+')],
      send: (m) => ({ successCount: 0, failureCount: m.tokens.length, responses: m.tokens.map(() => ({ success: false, error: { code: 'messaging/internal-error', message: 'x' } })) }),
    });
    const r = await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.strictEqual(f.requestUpdates.length, 0);
    assert.strictEqual(r.notifiedCount, 0);
  });

  it('removes a device token that FCM says is dead, keeps the rest', async () => {
    const f = fakeAdmin({
      users: [donor('a', 'A+', { fcmTokenList: ['good', 'dead'] })],
      send: (m) => ({
        successCount: 1,
        failureCount: 1,
        responses: m.tokens.map((t) => (t === 'dead'
          ? { success: false, error: { code: 'messaging/registration-token-not-registered', message: 'gone' } }
          : { success: true })),
      }),
    });
    const r = await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.strictEqual(r.prunedTokens, 1);
    assert.strictEqual(f.pruned.length, 1);
    assert.strictEqual(f.pruned[0].userId, 'a');
    assert.deepStrictEqual(f.pruned[0].d.fcmTokenList, { op: 'arrayRemove', v: 'dead' });
    assert.strictEqual(r.notifiedCount, 1); // the good device still counted
  });

  it('survives FCM throwing', async () => {
    const f = fakeAdmin({ users: [donor('a', 'A+')], send: () => { throw new Error('network down'); } });
    const r = await processBloodRequestNotifications(f.admin, 'r1', request());
    assert.strictEqual(r.notifiedCount, 0);
  });
});

describe('eligibility details', () => {
  const now = new Date();
  const e = (d, req = request()) => evaluateDonorEligibility(d.data, d.id, req, now);

  it('falls back to a city match when there are no coordinates', () => {
    const noCoords = (city) => {
      const d = donor('a', 'A+', { city });
      delete d.data.latitude;
      delete d.data.longitude;
      return d;
    };
    const req = request({ city: 'Pune', destination: { name: 'H', address: 'FC Road, Pune' } });
    assert.strictEqual(e(noCoords('Pune'), req).eligible, true);
    assert.strictEqual(e(noCoords('Mumbai'), req).eligible, false);
  });

  it('reports the distance for an eligible donor', () => {
    const r = e(donor('a', 'A+'));
    assert.strictEqual(r.eligible, true);
    assert(r.distanceKm > 0 && r.distanceKm < 10, `distance ${r.distanceKm}`);
  });

  it('gives a reason when a donor is not eligible', () => {
    assert.match(e(donor('b', 'B+')).reason, /incompatible/i);
  });
});
