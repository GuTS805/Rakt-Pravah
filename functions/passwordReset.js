// Password reset with a 6-digit code sent by email, typed back into the app.
// Firebase's own reset email opens a web page instead, so the code, its
// limits and the password change all happen here.
//
// Codes live in `password_resets/{sha256(email)}`, which the security rules
// keep away from every client. Only a hash of the code is stored.

const crypto = require('crypto');

const CODE_TTL_MS = 10 * 60 * 1000;
const RESEND_GAP_MS = 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;
const CODES_PER_HOUR = 5;
const MAX_TRIES = 5;
const MIN_PASSWORD = 6;
const MAX_PASSWORD = 4096;

/** A reset that failed for a reason the app explains to the person. */
class ResetError extends Error {
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}

function normalizeEmail(raw) {
  if (typeof raw !== 'string') return null;
  const email = raw.trim().toLowerCase();
  if (email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return null;
  return email;
}

const docIdFor = (email) => crypto.createHash('sha256').update(email).digest('hex');
const hashCode = (docId, code) => crypto.createHash('sha256').update(`${docId}:${code}`).digest('hex');

function sameHash(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  return crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b));
}

async function findUser(auth, email) {
  try {
    return await auth.getUserByEmail(email);
  } catch (e) {
    if (e && e.code === 'auth/user-not-found') return null;
    throw e;
  }
}

/**
 * Emails a new code to [rawEmail] if it has an account. Answers the same way
 * when it doesn't, so nobody can use this to learn who is registered; the
 * send limits apply either way for the same reason.
 */
async function requestCode({ db, auth, sendMail, now = Date.now, randomInt = crypto.randomInt }, rawEmail) {
  const email = normalizeEmail(rawEmail);
  if (!email) throw new ResetError('bad-email');
  const docId = docIdFor(email);
  const ref = db.collection('password_resets').doc(docId);
  const user = await findUser(auth, email);
  const code = String(randomInt(0, 1000000)).padStart(6, '0');
  const t = now();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const sends = ((snap.exists && snap.data().sends) || []).filter((s) => t - s < HOUR_MS);
    if (sends.length && t - sends[sends.length - 1] < RESEND_GAP_MS) throw new ResetError('too-soon');
    if (sends.length >= CODES_PER_HOUR) throw new ResetError('too-many-codes');
    tx.set(ref, {
      sends: [...sends, t],
      uid: user ? user.uid : null,
      codeHash: user ? hashCode(docId, code) : null,
      expiresAt: t + CODE_TTL_MS,
      tries: 0,
    });
  });

  if (user) await sendMail(email, code);
}

/**
 * Sets [newPassword] on the account of [rawEmail] if [rawCode] is the code
 * last sent there, then signs that account out everywhere else. A code works
 * once, for ten minutes, and stops working after five wrong tries.
 */
async function resetWithCode({ db, auth, now = Date.now }, rawEmail, rawCode, newPassword) {
  if (typeof newPassword !== 'string' || newPassword.length < MIN_PASSWORD || newPassword.length > MAX_PASSWORD) {
    throw new ResetError('weak-password');
  }
  const email = normalizeEmail(rawEmail);
  const code = String(rawCode ?? '').trim();
  if (!email || !/^\d{6}$/.test(code)) throw new ResetError('wrong-code');
  const docId = docIdFor(email);
  const ref = db.collection('password_resets').doc(docId);
  const t = now();

  // A wrong code has to be counted, and a transaction that throws writes
  // nothing, so the outcome is returned and thrown afterwards.
  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return { reason: 'wrong-code' };
    const data = snap.data();
    if (!data.codeHash || !data.uid) return { reason: t > data.expiresAt ? 'expired' : 'wrong-code' };
    if (t > data.expiresAt) return { reason: 'expired' };
    if (data.tries >= MAX_TRIES) return { reason: 'too-many-tries' };
    if (!sameHash(hashCode(docId, code), data.codeHash)) {
      const tries = data.tries + 1;
      tx.update(ref, { tries });
      return { reason: tries >= MAX_TRIES ? 'too-many-tries' : 'wrong-code' };
    }
    return { uid: data.uid };
  });
  if (!outcome.uid) throw new ResetError(outcome.reason);

  try {
    await auth.updateUser(outcome.uid, { password: newPassword });
  } catch (e) {
    if (e && (e.code === 'auth/invalid-password' || e.code === 'auth/password-does-not-meet-requirements')) {
      throw new ResetError('weak-password');
    }
    throw e;
  }
  await ref.update({ codeHash: null, uid: null });
  await auth.revokeRefreshTokens(outcome.uid);
}

/** The email a code goes out in. */
function codeEmail(code) {
  const minutes = CODE_TTL_MS / 60000;
  return {
    subject: `${code} is your Rakt Pravah code`,
    text:
      `Your Rakt Pravah password reset code is ${code}.\n\n` +
      `Type it into the app to choose a new password. It works for ${minutes} minutes.\n\n` +
      "If you didn't ask to reset your password, ignore this email. Your password stays the same.",
    html:
      '<div style="font-family:Arial,sans-serif;font-size:15px;color:#222">' +
      '<p>Your Rakt Pravah password reset code is</p>' +
      `<p style="font-size:30px;font-weight:bold;letter-spacing:6px">${code}</p>` +
      `<p>Type it into the app to choose a new password. It works for ${minutes} minutes.</p>` +
      "<p style=\"color:#666\">If you didn't ask to reset your password, ignore this email. Your password stays the same.</p>" +
      '</div>',
  };
}

module.exports = { requestCode, resetWithCode, codeEmail, ResetError, normalizeEmail, MAX_TRIES };
