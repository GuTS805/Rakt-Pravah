// Who may ask for a notification run by hand: the person who made the
// request, or an operator. Notifications normally go out from the
// Firestore triggers on their own; these checks guard the manual endpoints
// so nobody else can make donors' phones ring.

/** The signed-in uid from an `Authorization: Bearer <Firebase ID token>`
 * header, or null when there is none or it doesn't verify. */
async function uidFromBearer(admin, req) {
  const header =
    (typeof req.get === 'function' && req.get('Authorization')) ||
    (req.headers && req.headers.authorization) ||
    '';
  const match = /^Bearer (.+)$/.exec(header);
  if (!match) return null;
  try {
    return (await admin.auth().verifyIdToken(match[1])).uid;
  } catch (_) {
    return null;
  }
}

/** Whether [uid] owns the request or is an operator. */
async function mayTrigger(admin, uid, requestData) {
  if (!uid) return false;
  if (requestData && requestData.requesterId === uid) return true;
  const user = await admin.firestore().collection('users').doc(uid).get();
  if (!user.exists) return false;
  const data = user.data() || {};
  return data.isAdmin === true || data.role === 'admin';
}

module.exports = { uidFromBearer, mayTrigger };
