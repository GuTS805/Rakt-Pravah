// Shared setup for the Firestore security-rules tests. They run against the
// Firestore emulator (see `npm run test:rules`), so the real firestore.rules
// file is what is being exercised.
const fs = require('fs');
const path = require('path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
require('firebase/firestore').setLogLevel('silent');

const RULES = path.join(__dirname, '..', '..', '..', 'firestore.rules');

async function setup() {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
  return initializeTestEnvironment({
    // Each test file runs in its own process and gets its own namespace, so
    // one file clearing the database never wipes another's data.
    projectId: `demo-rakt-rules-${process.pid}`,
    firestore: { rules: fs.readFileSync(RULES, 'utf8'), host, port: Number(port) },
  });
}

const ids = {
  requester: 'requester1',
  donor: 'donor1',
  donor2: 'donor2',
  stranger: 'stranger1',
  admin: 'admin1',
};

// A new open request for one unit that is open to A+ donors.
const openRequest = (extra = {}) => ({
  requesterId: ids.requester,
  requesterName: 'Ravi',
  status: 'searching',
  units: 1,
  bloodGroups: ['A+'],
  patientBloodGroup: 'A+',
  acceptedDonors: [],
  acceptedDonorIds: [],
  declinedByDonorIds: [],
  viewedByDonorIds: [],
  timeline: [],
  ...extra,
});

// Seeds documents with the rules switched off.
async function seed(env, fn) {
  await env.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
}

async function baseline(env) {
  await env.clearFirestore();
  await seed(env, async (db) => {
    for (const id of [ids.requester, ids.donor, ids.donor2, ids.stranger]) {
      await db.doc(`users/${id}`).set({ name: id, email: `${id}@example.com`, approved: true, isAdmin: false, phone: '9876543210' });
    }
    await db.doc(`users/${ids.admin}`).set({ name: 'Op', email: 'ops@example.com', approved: true, isAdmin: true });
    await db.doc('blood_requests/r1').set(openRequest());
    await db.doc('blood_requests/r1/private/patient').set({ name: 'Sunil', phone: '9000000000' });
    await db.doc('blood_requests/r1/messages/m0').set({ senderId: ids.requester, text: 'hi' });
  });
}

const as = (env, uid, email) => env.authenticatedContext(uid, { email: email || `${uid}@example.com` }).firestore();

module.exports = { setup, baseline, seed, as, ids, openRequest, assertSucceeds, assertFails };
