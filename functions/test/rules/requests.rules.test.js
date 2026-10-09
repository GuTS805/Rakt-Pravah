// Access rules for blood requests, the patient's private details and chat.
const { describe, it, before, after, beforeEach } = require('node:test');
const { setup, baseline, seed, as, asUnverified, ids, openRequest, assertSucceeds, assertFails } = require('./helpers');

describe('blood_requests', () => {
  let env;
  before(async () => { env = await setup(); });
  after(async () => { await env.cleanup(); });
  beforeEach(async () => { await baseline(env); });

  const req = (uid) => as(env, uid).doc('blood_requests/r1');
  const accepted = (donorId) => ({ id: donorId, name: donorId, status: 'Accepted' });

  // r1 already has `donorIds` accepted.
  async function withAccepted(donorIds, extra = {}) {
    await seed(env, (db) => db.doc('blood_requests/r1').set(openRequest({
      acceptedDonorIds: donorIds,
      acceptedDonors: donorIds.map(accepted),
      ...extra,
    })));
  }

  describe('reading', () => {
    it('a signed-in user can read a request (that is how donors find them)', async () => {
      await assertSucceeds(req(ids.stranger).get());
    });
    it('a signed-out visitor cannot', async () => {
      await assertFails(env.unauthenticatedContext().firestore().doc('blood_requests/r1').get());
    });
  });

  describe('creating', () => {
    const create = (uid, extra = {}) =>
      as(env, uid).doc('blood_requests/new').set(openRequest({ requesterId: uid, ...extra }));

    it('a user can create a request in their own name', async () => {
      await assertSucceeds(create(ids.requester));
    });
    it('cannot create a request in someone else\'s name', async () => {
      await assertFails(as(env, ids.stranger).doc('blood_requests/new').set(openRequest({ requesterId: ids.requester })));
    });
    it('a signed-out visitor cannot create one', async () => {
      await assertFails(env.unauthenticatedContext().firestore().doc('blood_requests/new').set(openRequest()));
    });
    it('rejects an oversized requester photo', async () => {
      await assertFails(create(ids.requester, { requesterPhoto: 'x'.repeat(60001) }));
    });

    describe('a verified phone number', () => {
      const accept = (db) => db.doc('blood_requests/r1').update({
        acceptedDonorIds: [ids.stranger], acceptedDonors: [accepted(ids.stranger)], status: 'donorAccepted', timeline: [],
      });
      it('is needed to request blood', async () => {
        await assertFails(asUnverified(env, ids.stranger).doc('blood_requests/new').set(openRequest({ requesterId: ids.stranger })));
      });
      it('is needed to accept a request', async () => {
        await assertFails(accept(asUnverified(env, ids.stranger)));
      });
      it('with one, the same account can accept', async () => {
        await assertSucceeds(accept(as(env, ids.stranger)));
      });
      it('is not enough once an operator has switched the account off', async () => {
        await seed(env, (db) => db.doc(`users/${ids.stranger}`).set({ isActive: false }, { merge: true }));
        await assertFails(create(ids.stranger));
        await assertFails(accept(as(env, ids.stranger)));
      });
      it('is not needed by an operator', async () => {
        await assertSucceeds(asUnverified(env, ids.admin).doc('blood_requests/new').set(openRequest({ requesterId: ids.admin })));
      });
    });
  });

  describe('the requester', () => {
    it('can change their own request (cancel)', async () => {
      await assertSucceeds(req(ids.requester).update({ status: 'cancelled' }));
    });
    it('another user cannot cancel it', async () => {
      await assertFails(req(ids.stranger).update({ status: 'cancelled' }));
    });
    it('another user cannot change the units asked for', async () => {
      await assertFails(req(ids.stranger).update({ units: 9 }));
    });
    it('another user cannot reassign the request to themselves', async () => {
      await assertFails(req(ids.stranger).update({ requesterId: ids.stranger }));
    });
    it('a request can never be deleted', async () => {
      await assertFails(req(ids.requester).delete());
      await assertFails(req(ids.admin).delete());
    });
  });

  describe('a donor accepting', () => {
    const accept = (uid, ids_) => req(uid).update({
      acceptedDonorIds: ids_, acceptedDonors: ids_.map(accepted), status: 'donorAccepted', timeline: [],
    });

    it('can commit to an open unit', async () => {
      await assertSucceeds(accept(ids.donor, [ids.donor]));
    });
    it('cannot accept on behalf of someone else', async () => {
      await assertFails(accept(ids.donor, [ids.donor2]));
    });
    it('cannot accept twice', async () => {
      await withAccepted([ids.donor], { units: 3 });
      await assertFails(accept(ids.donor, [ids.donor, ids.donor]));
    });
    it('cannot accept past the units asked for', async () => {
      await withAccepted([ids.donor]); // 1 unit, already covered
      await assertFails(accept(ids.donor2, [ids.donor, ids.donor2]));
    });
    it('can join a multi-unit request that still has room', async () => {
      await withAccepted([ids.donor], { units: 2 });
      await assertSucceeds(accept(ids.donor2, [ids.donor, ids.donor2]));
    });
    it('cannot add two donors in one write', async () => {
      await withAccepted([], { units: 3 });
      await assertFails(accept(ids.donor, [ids.donor, ids.donor2]));
    });
    it('cannot change other fields while accepting', async () => {
      await assertFails(req(ids.donor).update({
        acceptedDonorIds: [ids.donor], acceptedDonors: [accepted(ids.donor)], status: 'donorAccepted', timeline: [], units: 99,
      }));
    });
  });

  describe('a donor declining', () => {
    it('can add themselves to the declined list', async () => {
      await assertSucceeds(req(ids.donor).update({ declinedByDonorIds: [ids.donor] }));
    });
    it('cannot remove someone else from the declined list', async () => {
      await seed(env, (db) => db.doc('blood_requests/r1').set(openRequest({ declinedByDonorIds: [ids.donor2] })));
      await assertFails(req(ids.donor).update({ declinedByDonorIds: [ids.donor] }));
    });
    it('cannot decline on behalf of someone else', async () => {
      await assertFails(req(ids.donor).update({ declinedByDonorIds: [ids.donor2] }));
    });
  });

  describe('live location sharing', () => {
    beforeEach(async () => { await withAccepted([ids.donor, ids.donor2], { units: 2 }); });
    const ping = { lat: 18.5, lng: 73.8 };

    it('an accepted donor can share their own position', async () => {
      await assertSucceeds(req(ids.donor).update({ donorLiveLocations: { [ids.donor]: ping } }));
    });
    it('cannot write another donor\'s position', async () => {
      await assertFails(req(ids.donor).update({ donorLiveLocations: { [ids.donor2]: ping } }));
    });
    it('a donor who has not accepted cannot write a position', async () => {
      await assertFails(req(ids.stranger).update({ donorLiveLocations: { [ids.stranger]: ping } }));
    });
    it('location sharing cannot be used to change anything else', async () => {
      await assertFails(req(ids.donor).update({ donorLiveLocations: { [ids.donor]: ping }, units: 5 }));
    });
  });

  describe('a donor withdrawing', () => {
    beforeEach(async () => { await withAccepted([ids.donor]); });
    it('can come off the list; the request goes back to searching', async () => {
      await assertSucceeds(req(ids.donor).update({ acceptedDonorIds: [], acceptedDonors: [], status: 'searching' }));
    });
    it('cannot withdraw someone else', async () => {
      await assertFails(req(ids.donor2).update({ acceptedDonorIds: [], acceptedDonors: [], status: 'searching' }));
    });
    it('cannot withdraw and mark the request fulfilled', async () => {
      await assertFails(req(ids.donor).update({ acceptedDonorIds: [], acceptedDonors: [], status: 'fulfilled' }));
    });
  });

  describe('operator moderation', () => {
    it('an operator can remove a request', async () => {
      await assertSucceeds(req(ids.admin).update({ status: 'removedByAdmin', timeline: [] }));
    });
    it('cannot use admin access to rewrite the request', async () => {
      await assertFails(req(ids.admin).update({ units: 1, status: 'removedByAdmin', timeline: [], notes: 'x' }));
    });
    it('cannot set any other status', async () => {
      await assertFails(req(ids.admin).update({ status: 'fulfilled', timeline: [] }));
    });
  });

  describe("the patient's private details", () => {
    const patient = (uid) => as(env, uid).doc('blood_requests/r1/private/patient');
    it('the requester can read them', async () => {
      await assertSucceeds(patient(ids.requester).get());
    });
    it('an accepted donor can read them', async () => {
      await withAccepted([ids.donor]);
      await assertSucceeds(patient(ids.donor).get());
    });
    it('a donor who has not accepted cannot', async () => {
      await assertFails(patient(ids.donor).get());
    });
    it('a stranger cannot', async () => {
      await assertFails(patient(ids.stranger).get());
    });
    it('an operator cannot read the patient\'s name', async () => {
      await assertFails(patient(ids.admin).get());
    });
    it('a signed-out visitor cannot', async () => {
      await assertFails(env.unauthenticatedContext().firestore().doc('blood_requests/r1/private/patient').get());
    });
    it('only the requester can write them', async () => {
      await assertSucceeds(patient(ids.requester).set({ name: 'Edited' }));
      await assertFails(patient(ids.stranger).set({ name: 'Hacked' }));
    });
    it('an accepted donor cannot rewrite them', async () => {
      await withAccepted([ids.donor]);
      await assertFails(patient(ids.donor).set({ name: 'Hacked' }));
    });
    it('they can never be deleted', async () => {
      await assertFails(patient(ids.requester).delete());
    });
  });

  describe('request chat', () => {
    const msgs = (uid) => as(env, uid).collection('blood_requests/r1/messages');
    beforeEach(async () => { await withAccepted([ids.donor]); });

    it('the requester can read and send', async () => {
      await assertSucceeds(msgs(ids.requester).get());
      await assertSucceeds(msgs(ids.requester).add({ senderId: ids.requester, text: 'hello' }));
    });
    it('an accepted donor can read and send', async () => {
      await assertSucceeds(msgs(ids.donor).get());
      await assertSucceeds(msgs(ids.donor).add({ senderId: ids.donor, text: 'on my way' }));
    });
    it('cannot send a message in someone else\'s name', async () => {
      await assertFails(msgs(ids.donor).add({ senderId: ids.requester, text: 'spoofed' }));
    });
    it('a stranger cannot read the conversation', async () => {
      await assertFails(msgs(ids.stranger).get());
    });
    it('a stranger cannot post into it', async () => {
      await assertFails(msgs(ids.stranger).add({ senderId: ids.stranger, text: 'hi' }));
    });
    it('a donor who has not accepted cannot read it', async () => {
      await assertFails(msgs(ids.donor2).get());
    });
    it('an operator cannot read private chat', async () => {
      await assertFails(msgs(ids.admin).get());
    });
    it('messages cannot be edited or deleted', async () => {
      await assertFails(as(env, ids.requester).doc('blood_requests/r1/messages/m0').update({ text: 'edited' }));
      await assertFails(as(env, ids.requester).doc('blood_requests/r1/messages/m0').delete());
    });
  });
});
