// Rules for app config, the operators' audit trail, abuse reports, and the
// default-deny behaviour for anything the rules do not mention.
const { describe, it, before, after, beforeEach } = require('node:test');
const { setup, baseline, seed, as, ids, assertSucceeds, assertFails } = require('./helpers');

describe('operations collections', () => {
  let env;
  before(async () => { env = await setup(); });
  after(async () => { await env.cleanup(); });
  beforeEach(async () => { await baseline(env); });

  describe('config/app', () => {
    it('any signed-in user can read it', async () => {
      await assertSucceeds(as(env, ids.stranger).doc('config/app').get());
    });
    it('a signed-out visitor cannot', async () => {
      await assertFails(env.unauthenticatedContext().firestore().doc('config/app').get());
    });
    it('an ordinary user cannot change it', async () => {
      await assertFails(as(env, ids.stranger).doc('config/app').set({ cooldownDays: 1 }));
    });
    it('an operator can change it', async () => {
      await assertSucceeds(as(env, ids.admin).doc('config/app').set({ cooldownEnabled: true, cooldownDays: 60 }));
    });
  });

  describe('admin_audit (append-only)', () => {
    const entry = (actorId) => ({ actorId, action: 'approve', at: new Date() });
    it('an operator can record an action in their own name', async () => {
      await assertSucceeds(as(env, ids.admin).doc('admin_audit/e1').set(entry(ids.admin)));
    });
    it('cannot record an action in someone else\'s name', async () => {
      await assertFails(as(env, ids.admin).doc('admin_audit/e1').set(entry(ids.stranger)));
    });
    it('an ordinary user cannot write or read it', async () => {
      await assertFails(as(env, ids.stranger).doc('admin_audit/e1').set(entry(ids.stranger)));
      await seed(env, (db) => db.doc('admin_audit/e1').set(entry(ids.admin)));
      await assertFails(as(env, ids.stranger).doc('admin_audit/e1').get());
    });
    it('an operator can read it', async () => {
      await seed(env, (db) => db.doc('admin_audit/e1').set(entry(ids.admin)));
      await assertSucceeds(as(env, ids.admin).doc('admin_audit/e1').get());
    });
    it('history cannot be rewritten or deleted, even by an operator', async () => {
      await seed(env, (db) => db.doc('admin_audit/e1').set(entry(ids.admin)));
      await assertFails(as(env, ids.admin).doc('admin_audit/e1').update({ action: 'nothing happened' }));
      await assertFails(as(env, ids.admin).doc('admin_audit/e1').delete());
    });
  });

  describe('reports', () => {
    const report = (uid) => ({ reporterId: uid, reason: 'spam' });
    it('any signed-in user can file a report in their own name', async () => {
      await assertSucceeds(as(env, ids.stranger).doc('reports/x1').set(report(ids.stranger)));
    });
    it('cannot file one in someone else\'s name', async () => {
      await assertFails(as(env, ids.stranger).doc('reports/x1').set(report(ids.donor)));
    });
    it('cannot file one already marked resolved', async () => {
      await assertFails(as(env, ids.stranger).doc('reports/x1')
        .set({ ...report(ids.stranger), status: 'resolved' }));
    });
    it('cannot attach a very long text', async () => {
      await assertSucceeds(as(env, ids.stranger).doc('reports/x1')
        .set({ ...report(ids.stranger), detail: 'x'.repeat(2000) }));
      await assertFails(as(env, ids.stranger).doc('reports/x2')
        .set({ ...report(ids.stranger), detail: 'x'.repeat(2001) }));
    });
    it('the reporter cannot read reports back, only operators can', async () => {
      await seed(env, (db) => db.doc('reports/x1').set(report(ids.stranger)));
      await assertFails(as(env, ids.stranger).doc('reports/x1').get());
      await assertSucceeds(as(env, ids.admin).doc('reports/x1').get());
    });
    it('only an operator can resolve a report', async () => {
      await seed(env, (db) => db.doc('reports/x1').set(report(ids.stranger)));
      await assertFails(as(env, ids.stranger).doc('reports/x1').update({ resolved: true }));
      await assertSucceeds(as(env, ids.admin).doc('reports/x1').update({ resolved: true }));
    });
    it('reports can never be deleted', async () => {
      await seed(env, (db) => db.doc('reports/x1').set(report(ids.stranger)));
      await assertFails(as(env, ids.admin).doc('reports/x1').delete());
    });
  });

  describe('default deny', () => {
    it('a collection the rules do not mention is closed to everyone', async () => {
      await assertFails(as(env, ids.admin).doc('secrets/s1').get());
      await assertFails(as(env, ids.admin).doc('secrets/s1').set({ a: 1 }));
    });
  });
});
