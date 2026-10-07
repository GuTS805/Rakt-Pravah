// Privacy and access rules for user profiles and their device records.
const { describe, it, before, after, beforeEach } = require('node:test');
const { setup, baseline, as, ids, assertSucceeds, assertFails } = require('./helpers');

describe('users collection', () => {
  let env;
  before(async () => { env = await setup(); });
  after(async () => { await env.cleanup(); });
  beforeEach(async () => { await baseline(env); });

  describe('who can read a profile', () => {
    it('the owner can read their own profile', async () => {
      await assertSucceeds(as(env, ids.donor).doc(`users/${ids.donor}`).get());
    });
    it('another signed-in user cannot read it (phone and location stay private)', async () => {
      await assertFails(as(env, ids.stranger).doc(`users/${ids.donor}`).get());
    });
    it('a signed-out visitor cannot read it', async () => {
      await assertFails(env.unauthenticatedContext().firestore().doc(`users/${ids.donor}`).get());
    });
    it('an operator can read it', async () => {
      await assertSucceeds(as(env, ids.admin).doc(`users/${ids.donor}`).get());
    });
    it('nobody can list the whole users collection', async () => {
      await assertFails(as(env, ids.stranger).collection('users').get());
    });
  });

  describe('creating a profile', () => {
    const newUser = (extra = {}) => ({ name: 'New', email: 'new@example.com', approved: false, isAdmin: false, ...extra });
    const fresh = () => as(env, 'fresh', 'new@example.com');
    it('a new account can create its own, unapproved profile', async () => {
      await assertSucceeds(fresh().doc('users/fresh').set(newUser()));
    });
    it('cannot create a profile for someone else', async () => {
      await assertFails(fresh().doc('users/other').set(newUser()));
    });
    it('cannot create itself already approved', async () => {
      await assertFails(fresh().doc('users/fresh').set(newUser({ approved: true })));
    });
    it('cannot create itself as an admin', async () => {
      await assertFails(fresh().doc('users/fresh').set(newUser({ isAdmin: true })));
    });
    it('cannot create itself with role=admin', async () => {
      await assertFails(fresh().doc('users/fresh').set(newUser({ role: 'admin' })));
    });
    it('rejects an oversized profile photo', async () => {
      await assertFails(fresh().doc('users/fresh').set(newUser({ photo: 'x'.repeat(60001) })));
    });
    it('accepts a normal-sized profile photo', async () => {
      await assertSucceeds(fresh().doc('users/fresh').set(newUser({ photo: 'x'.repeat(5000) })));
    });
  });

  describe('updating a profile', () => {
    const me = () => as(env, ids.donor).doc(`users/${ids.donor}`);
    it('the owner can update their name, phone and saved GPS position', async () => {
      await assertSucceeds(me().set({ name: 'Renamed', phone: '9111111111', latitude: 18.5, longitude: 73.8, location: { lat: 18.5, lng: 73.8 } }, { merge: true }));
    });
    it('the owner cannot make themselves an admin', async () => {
      await assertFails(me().set({ isAdmin: true }, { merge: true }));
    });
    it('the owner cannot set role=admin', async () => {
      await assertFails(me().set({ role: 'admin' }, { merge: true }));
    });
    it('the owner cannot approve their own account', async () => {
      await env.withSecurityRulesDisabled((c) => c.firestore().doc(`users/${ids.donor}`).set({ approved: false }, { merge: true }));
      await assertFails(me().set({ approved: true }, { merge: true }));
    });
    it("another user cannot change someone else's profile", async () => {
      await assertFails(as(env, ids.stranger).doc(`users/${ids.donor}`).set({ name: 'Hacked' }, { merge: true }));
    });
    it('an operator may approve an account', async () => {
      await assertSucceeds(as(env, ids.admin).doc(`users/${ids.donor}`).update({ approved: true }));
    });
    it('an operator may disable an account', async () => {
      await assertSucceeds(as(env, ids.admin).doc(`users/${ids.donor}`).update({ disabled: true }));
    });
    it("an operator cannot rewrite a user's name or phone", async () => {
      await assertFails(as(env, ids.admin).doc(`users/${ids.donor}`).update({ name: 'Edited by ops' }));
      await assertFails(as(env, ids.admin).doc(`users/${ids.donor}`).update({ phone: '1' }));
    });
    it('profiles can never be deleted, even by the owner or an operator', async () => {
      await assertFails(me().delete());
      await assertFails(as(env, ids.admin).doc(`users/${ids.donor}`).delete());
    });
  });

  describe('device records', () => {
    it('the owner manages their own FCM tokens', async () => {
      await assertSucceeds(as(env, ids.donor).doc(`users/${ids.donor}/fcm_tokens/t1`).set({ token: 'abc' }));
      await assertSucceeds(as(env, ids.donor).doc(`users/${ids.donor}/fcm_tokens/t1`).get());
    });
    it('nobody else can read or write them', async () => {
      await assertFails(as(env, ids.stranger).doc(`users/${ids.donor}/fcm_tokens/t1`).set({ token: 'abc' }));
      await assertFails(as(env, ids.admin).doc(`users/${ids.donor}/fcm_tokens/t1`).get());
    });
    it('the owner manages their own devices; others cannot', async () => {
      await assertSucceeds(as(env, ids.donor).doc(`users/${ids.donor}/devices/d1`).set({ model: 'x' }));
      await assertFails(as(env, ids.stranger).doc(`users/${ids.donor}/devices/d1`).get());
    });
    it('push_devices: a user can register only a device that names themselves', async () => {
      await assertSucceeds(as(env, ids.donor).doc('push_devices/p1').set({ user_id: ids.donor, token: 't' }));
      await assertFails(as(env, ids.donor).doc('push_devices/p2').set({ user_id: ids.stranger, token: 't' }));
    });
    it('push_devices: only the owner or an operator can read one', async () => {
      await env.withSecurityRulesDisabled((c) => c.firestore().doc('push_devices/p1').set({ user_id: ids.donor, token: 't' }));
      await assertSucceeds(as(env, ids.donor).doc('push_devices/p1').get());
      await assertSucceeds(as(env, ids.admin).doc('push_devices/p1').get());
      await assertFails(as(env, ids.stranger).doc('push_devices/p1').get());
    });
  });

  describe('operator access', () => {
    // Email/password sign-up does not verify the address, so an email that
    // merely contains "admin" must not make someone an operator.
    it('an ordinary account whose email merely contains "admin" must NOT be an operator',
      async () => {
        const evil = as(env, 'evil', 'myadmin@example.com');
        await assertFails(evil.doc('config/app').set({ requireApproval: false }));
        await assertFails(evil.doc(`users/${ids.donor}`).get());
      });
  });
});
