// Privacy and access rules for user profiles and their device records.
const { describe, it, before, after, beforeEach } = require('node:test');
const { setup, baseline, as, asUnverified, ids, PHONE, assertSucceeds, assertFails } = require('./helpers');

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
    const newUser = (extra = {}) => ({ name: 'New', email: 'new@example.com', isAdmin: false, countryCode: '+91', phone: PHONE, phoneVerified: false, ...extra });
    const fresh = () => asUnverified(env, 'fresh', 'new@example.com');
    it('a new account can create its own profile, not yet verified', async () => {
      await assertSucceeds(fresh().doc('users/fresh').set(newUser()));
    });
    it('cannot create a profile for someone else', async () => {
      await assertFails(fresh().doc('users/other').set(newUser()));
    });
    it('cannot claim a verified phone it has no code for', async () => {
      await assertFails(fresh().doc('users/fresh').set(newUser({ phoneVerified: true })));
    });
    it('with a verified phone, can say so for that same number', async () => {
      await assertSucceeds(as(env, 'fresh', 'new@example.com').doc('users/fresh').set(newUser({ phoneVerified: true })));
    });
    it('with a verified phone, cannot put a different number on the profile as verified', async () => {
      await assertFails(as(env, 'fresh', 'new@example.com').doc('users/fresh').set(newUser({ phone: '9111111111', phoneVerified: true })));
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
    it('the owner can update their name and saved GPS position', async () => {
      await assertSucceeds(me().set({ name: 'Renamed', latitude: 18.5, longitude: 73.8, location: { lat: 18.5, lng: 73.8 } }, { merge: true }));
    });
    it('rewriting the same verified number is not a change', async () => {
      await assertSucceeds(me().set({ name: 'Renamed', countryCode: '+91', phone: PHONE }, { merge: true }));
    });
    it('a verified number cannot be swapped for another on the profile', async () => {
      await assertFails(me().set({ phone: '9111111111' }, { merge: true }));
    });
    it('before verifying, the owner can fix their number', async () => {
      await env.withSecurityRulesDisabled((c) => c.firestore().doc(`users/${ids.donor}`).set({ phoneVerified: false }, { merge: true }));
      await assertSucceeds(asUnverified(env, ids.donor).doc(`users/${ids.donor}`).set({ phone: '9111111111' }, { merge: true }));
    });
    it('before verifying, the owner cannot mark the number verified', async () => {
      await env.withSecurityRulesDisabled((c) => c.firestore().doc(`users/${ids.donor}`).set({ phoneVerified: false }, { merge: true }));
      await assertFails(asUnverified(env, ids.donor).doc(`users/${ids.donor}`).set({ phoneVerified: true }, { merge: true }));
    });
    it('once the code is confirmed, the owner marks that number verified', async () => {
      await env.withSecurityRulesDisabled((c) => c.firestore().doc(`users/${ids.donor}`).set({ phone: '9000000000', phoneVerified: false }, { merge: true }));
      await assertSucceeds(me().set({ countryCode: '+91', phone: PHONE, phoneVerified: true }, { merge: true }));
    });
    it('the owner cannot make themselves an admin', async () => {
      await assertFails(me().set({ isAdmin: true }, { merge: true }));
    });
    it('the owner cannot set role=admin', async () => {
      await assertFails(me().set({ role: 'admin' }, { merge: true }));
    });
    it('the owner cannot switch their account back on after an operator turned it off', async () => {
      await env.withSecurityRulesDisabled((c) => c.firestore().doc(`users/${ids.donor}`).set({ isActive: false }, { merge: true }));
      await assertFails(me().set({ isActive: true }, { merge: true }));
    });
    it('the owner cannot clear a disabled flag either', async () => {
      await env.withSecurityRulesDisabled((c) => c.firestore().doc(`users/${ids.donor}`).set({ disabled: true }, { merge: true }));
      await assertFails(me().set({ disabled: false }, { merge: true }));
    });
    it("another user cannot change someone else's profile", async () => {
      await assertFails(as(env, ids.stranger).doc(`users/${ids.donor}`).set({ name: 'Hacked' }, { merge: true }));
    });
    it('an operator may switch an account off', async () => {
      await assertSucceeds(as(env, ids.admin).doc(`users/${ids.donor}`).update({ isActive: false }));
    });
    it('an operator cannot change whether a number is verified', async () => {
      await assertFails(as(env, ids.admin).doc(`users/${ids.donor}`).update({ phoneVerified: false }));
    });
    it('an operator may disable an account', async () => {
      await assertSucceeds(as(env, ids.admin).doc(`users/${ids.donor}`).update({ disabled: true }));
    });
    it("an operator cannot rewrite a user's name or phone", async () => {
      await assertFails(as(env, ids.admin).doc(`users/${ids.donor}`).update({ name: 'Edited by ops' }));
      await assertFails(as(env, ids.admin).doc(`users/${ids.donor}`).update({ phone: '1' }));
    });
    it('the owner can delete their own profile, to delete their account', async () => {
      await assertSucceeds(me().delete());
    });
    it("nobody else can delete a profile, not even an operator", async () => {
      await assertFails(as(env, ids.requester).doc(`users/${ids.donor}`).delete());
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
