// Password reset by emailed code (passwordReset.js), on an in-memory
// Firestore and Auth, so nothing real is contacted.
const assert = require('assert');
const { describe, it, beforeEach } = require('node:test');
const { requestCode, resetWithCode, codeEmail, MAX_TRIES } = require('../passwordReset');

function fakeDb() {
  const docs = new Map();
  const ref = (id) => ({
    id,
    get: async () => ({ exists: docs.has(id), data: () => ({ ...docs.get(id) }) }),
    update: async (patch) => docs.set(id, { ...docs.get(id), ...patch }),
  });
  return {
    docs,
    collection: (name) => {
      assert.strictEqual(name, 'password_resets');
      return { doc: ref };
    },
    runTransaction: async (fn) => {
      const writes = [];
      const result = await fn({
        get: (r) => r.get(),
        set: (r, data) => writes.push(() => docs.set(r.id, { ...data })),
        update: (r, patch) => writes.push(() => docs.set(r.id, { ...docs.get(r.id), ...patch })),
      });
      writes.forEach((w) => w()); // only when fn didn't throw, like Firestore
      return result;
    },
  };
}

function fakeAuth(users) {
  const auth = {
    passwords: {},
    revoked: [],
    getUserByEmail: async (email) => {
      const uid = users[email];
      if (!uid) throw Object.assign(new Error('no user'), { code: 'auth/user-not-found' });
      return { uid };
    },
    updateUser: async (uid, { password }) => {
      auth.passwords[uid] = password;
    },
    revokeRefreshTokens: async (uid) => auth.revoked.push(uid),
  };
  return auth;
}

describe('password reset by code', () => {
  let db, auth, mail, clock, deps;

  beforeEach(() => {
    db = fakeDb();
    auth = fakeAuth({ 'dana@example.com': 'u1' });
    mail = [];
    clock = 1_000_000_000;
    deps = {
      db,
      auth,
      sendMail: async (to, code) => mail.push({ to, code }),
      now: () => clock,
      randomInt: () => 42,
    };
  });

  const reason = (r) => (e) => e.reason === r;

  it('emails a six-digit code and stores only its hash', async () => {
    await requestCode(deps, '  Dana@Example.com ');
    assert.deepStrictEqual(mail, [{ to: 'dana@example.com', code: '000042' }]);
    const [stored] = [...db.docs.values()];
    assert.ok(!JSON.stringify(stored).includes('000042'));
    assert.ok(!JSON.stringify([...db.docs.keys()]).includes('dana'));
  });

  it('answers the same for an address without an account, and sends nothing', async () => {
    await requestCode(deps, 'ghost@example.com');
    assert.deepStrictEqual(mail, []);
    await assert.rejects(resetWithCode(deps, 'ghost@example.com', '000042', 'newpass1'), reason('wrong-code'));
  });

  it('rejects a malformed address', async () => {
    await assert.rejects(requestCode(deps, 'nope'), reason('bad-email'));
    await assert.rejects(requestCode(deps, undefined), reason('bad-email'));
  });

  it('waits a minute between codes and allows five an hour', async () => {
    await requestCode(deps, 'dana@example.com');
    await assert.rejects(requestCode(deps, 'dana@example.com'), reason('too-soon'));
    for (let i = 0; i < 4; i++) {
      clock += 61_000;
      await requestCode(deps, 'dana@example.com');
    }
    clock += 61_000;
    await assert.rejects(requestCode(deps, 'dana@example.com'), reason('too-many-codes'));
    clock += 60 * 60 * 1000;
    await requestCode(deps, 'dana@example.com');
    assert.strictEqual(mail.length, 6);
  });

  it('limits an address with no account the same way', async () => {
    await requestCode(deps, 'ghost@example.com');
    await assert.rejects(requestCode(deps, 'ghost@example.com'), reason('too-soon'));
  });

  it('sets the new password with the right code and signs out other devices', async () => {
    await requestCode(deps, 'dana@example.com');
    await resetWithCode(deps, 'DANA@example.com', ' 000042 ', 'newpass1');
    assert.strictEqual(auth.passwords.u1, 'newpass1');
    assert.deepStrictEqual(auth.revoked, ['u1']);
  });

  it('a code works only once', async () => {
    await requestCode(deps, 'dana@example.com');
    await resetWithCode(deps, 'dana@example.com', '000042', 'newpass1');
    await assert.rejects(resetWithCode(deps, 'dana@example.com', '000042', 'other123'), reason('wrong-code'));
    assert.strictEqual(auth.passwords.u1, 'newpass1');
  });

  it('a wrong code changes nothing', async () => {
    await requestCode(deps, 'dana@example.com');
    await assert.rejects(resetWithCode(deps, 'dana@example.com', '123456', 'newpass1'), reason('wrong-code'));
    assert.deepStrictEqual(auth.passwords, {});
  });

  it('stops after five wrong tries, even for the right code', async () => {
    await requestCode(deps, 'dana@example.com');
    for (let i = 1; i < MAX_TRIES; i++) {
      await assert.rejects(resetWithCode(deps, 'dana@example.com', '123456', 'newpass1'), reason('wrong-code'));
    }
    await assert.rejects(resetWithCode(deps, 'dana@example.com', '123456', 'newpass1'), reason('too-many-tries'));
    await assert.rejects(resetWithCode(deps, 'dana@example.com', '000042', 'newpass1'), reason('too-many-tries'));
    assert.deepStrictEqual(auth.passwords, {});
  });

  it('a new code starts the tries again', async () => {
    await requestCode(deps, 'dana@example.com');
    for (let i = 0; i < MAX_TRIES; i++) {
      await assert.rejects(resetWithCode(deps, 'dana@example.com', '123456', 'newpass1'));
    }
    clock += 61_000;
    await requestCode(deps, 'dana@example.com');
    await resetWithCode(deps, 'dana@example.com', '000042', 'newpass1');
    assert.strictEqual(auth.passwords.u1, 'newpass1');
  });

  it('a code expires after ten minutes', async () => {
    await requestCode(deps, 'dana@example.com');
    clock += 10 * 60 * 1000 + 1;
    await assert.rejects(resetWithCode(deps, 'dana@example.com', '000042', 'newpass1'), reason('expired'));
    assert.deepStrictEqual(auth.passwords, {});
  });

  it('a short password is refused before the code is looked at', async () => {
    await requestCode(deps, 'dana@example.com');
    await assert.rejects(resetWithCode(deps, 'dana@example.com', '000042', '12345'), reason('weak-password'));
    await assert.rejects(resetWithCode(deps, 'dana@example.com', '000042', undefined), reason('weak-password'));
    await resetWithCode(deps, 'dana@example.com', '000042', '123456');
    assert.strictEqual(auth.passwords.u1, '123456');
  });

  it('a code that is not six digits is wrong', async () => {
    await requestCode(deps, 'dana@example.com');
    await assert.rejects(resetWithCode(deps, 'dana@example.com', '42', 'newpass1'), reason('wrong-code'));
    await assert.rejects(resetWithCode(deps, 'dana@example.com', null, 'newpass1'), reason('wrong-code'));
  });

  it('a password Auth refuses is reported as weak, and the code still works', async () => {
    auth.updateUser = async () => {
      throw Object.assign(new Error('weak'), { code: 'auth/invalid-password' });
    };
    await requestCode(deps, 'dana@example.com');
    await assert.rejects(resetWithCode(deps, 'dana@example.com', '000042', 'newpass1'), reason('weak-password'));
    auth.updateUser = async (uid, { password }) => (auth.passwords[uid] = password);
    await resetWithCode(deps, 'dana@example.com', '000042', 'better-pass');
    assert.strictEqual(auth.passwords.u1, 'better-pass');
  });

  it('a mail that fails to send is reported, not hidden', async () => {
    deps.sendMail = async () => {
      throw new Error('smtp down');
    };
    await assert.rejects(requestCode(deps, 'dana@example.com'), /smtp down/);
  });

  it('the email shows the code and how long it works', () => {
    const m = codeEmail('004211');
    assert.ok(m.subject.includes('004211'));
    assert.ok(m.text.includes('004211') && m.text.includes('10 minutes'));
    assert.ok(m.html.includes('004211'));
  });
});
