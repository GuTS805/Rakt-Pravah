/**
 * Rakt Pravah - pushes for what happens after a request is sent out:
 * - a donor accepts, or says they can't make it  -> the requester
 * - the request is cancelled, expires or is removed -> its accepted donors
 * - a new chat message                             -> the other participants
 *
 * The app also shows these itself while it is running, but only the server
 * can reach a phone whose app is closed.
 */
const { extractTokens, sanitizeTokenKey } = require('./matcher');

const TERMINAL = ['fulfilled', 'cancelled', 'expired', 'removedByAdmin'];
const isActive = (status) => !TERMINAL.includes(status);

const ENDED = {
  cancelled: { title: 'Request cancelled', verb: 'was cancelled' },
  expired: { title: 'Request expired', verb: 'has expired' },
  removedByAdmin: { title: 'Request removed', verb: 'was removed' },
};

function ids(data) {
  return Array.isArray(data?.acceptedDonorIds) ? data.acceptedDonorIds : [];
}

function hospitalOf(data) {
  return data?.destination?.name || data?.requestLocationLabel || 'the hospital';
}

function donorName(data, id) {
  const list = Array.isArray(data?.acceptedDonors) ? data.acceptedDonors : [];
  const entry = list.find((d) => d && d.id === id);
  return (entry && entry.name) || 'A donor';
}

/**
 * Which pushes a change to a request calls for. Pure, so it can be tested
 * without Firebase. Each item: { uid, title, body, type } where type is the
 * screen a tap opens ('request' for the requester, 'invitation' for a donor,
 * 'chat' for a donor's chat).
 */
function requestUpdatePushes(before, after) {
  if (!before || !after) return [];
  const out = [];
  const requester = after.requesterId;
  const hospital = hospitalOf(after);
  const was = ids(before);
  const now = ids(after);

  if (isActive(before.status) && ENDED[after.status]) {
    const { title, verb } = ENDED[after.status];
    for (const uid of new Set([...was, ...now])) {
      if (uid === requester) continue;
      out.push({
        uid,
        title,
        body: `The request at ${hospital} ${verb}. You don't need to go.`,
        type: 'invitation',
      });
    }
    return out;
  }

  if (!isActive(after.status) || !requester) return out;

  for (const uid of now) {
    if (was.includes(uid)) continue;
    const name = donorName(after, uid);
    out.push({
      uid: requester,
      title: `🩸 ${name} accepted your request`,
      body: `${name} is coming to ${hospital}. Open the app to chat or follow them.`,
      type: 'request',
    });
  }
  for (const uid of was) {
    if (now.includes(uid)) continue;
    out.push({
      uid: requester,
      title: "A donor can't make it",
      body: `We're looking for another donor for ${hospital}.`,
      type: 'request',
    });
  }
  return out;
}

/** Who should hear about a new chat message: everyone in the chat but its sender. */
function chatPushes(request, message) {
  if (!request || !message || typeof message.text !== 'string') return [];
  const sender = message.senderId;
  const name = message.senderName || 'Someone';
  const text = message.text.length > 120 ? `${message.text.slice(0, 117)}...` : message.text;
  const out = [];
  if (request.requesterId && request.requesterId !== sender) {
    out.push({ uid: request.requesterId, title: `💬 ${name}`, body: text, type: 'request' });
  }
  for (const uid of ids(request)) {
    if (uid === sender || uid === request.requesterId) continue;
    // 'chat', not 'invitation': for a donor who already accepted, that screen
    // has no way into the chat. App 2.0.1 ignores the type and just opens
    // (Home shows the coordination card); later versions open the chat.
    out.push({ uid, title: `💬 ${name}`, body: text, type: 'chat' });
  }
  return out;
}

function buildMessage(item, requestId, tokens, tag) {
  const route = {
    request: `/requests/${requestId}`,
    chat: `/requests/${requestId}/chat`,
  }[item.type] || `/invitations/${requestId}`;
  return {
    notification: { title: item.title, body: item.body },
    data: { type: item.type, requestId, route },
    android: {
      priority: 'high',
      notification: {
        channelId: 'bloodlink_alerts',
        icon: 'ic_notification',
        color: '#D32F2F',
        priority: 'max',
        // One notification per request and kind: a newer one replaces the
        // older instead of stacking (several chat messages, for example).
        tag,
        defaultSound: true,
        defaultVibrateTimings: true,
      },
    },
    apns: {
      headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
      payload: {
        aps: { alert: { title: item.title, body: item.body }, sound: 'default' },
        requestId,
        type: item.type,
        route,
      },
    },
    tokens,
  };
}

/** Sends each item to every device of its user and prunes dead tokens. */
async function sendPushes(admin, requestId, items, tagPrefix) {
  if (items.length === 0) return { sent: 0 };
  const db = admin.firestore();
  let sent = 0;
  for (const item of items) {
    const snap = await db.collection('users').doc(item.uid).get();
    if (!snap.exists) continue;
    const tokens = extractTokens(snap.data());
    if (tokens.length === 0) continue;
    const message = buildMessage(item, requestId, tokens, `${tagPrefix}_${requestId}`);
    try {
      const res = await admin.messaging().sendEachForMulticast(message);
      sent += res.successCount;
      const dead = [];
      res.responses.forEach((r, i) => {
        const code = r.error?.code;
        if (
          !r.success &&
          (code === 'messaging/invalid-registration-token' ||
            code === 'messaging/registration-token-not-registered')
        ) {
          dead.push(tokens[i]);
        }
      });
      if (dead.length > 0) {
        const update = { fcmTokenList: admin.firestore.FieldValue.arrayRemove(...dead) };
        for (const t of dead) update[`fcmTokens.${sanitizeTokenKey(t)}`] = admin.firestore.FieldValue.delete();
        await db.collection('users').doc(item.uid).update(update)
          .catch((e) => console.error('[UpdatePush] Token pruning failed:', e.message));
      }
    } catch (err) {
      console.error(`[UpdatePush] Send failed for request ${requestId}:`, err.message);
    }
  }
  console.log(`[UpdatePush] ${tagPrefix} for ${requestId}: ${items.length} people, ${sent} devices.`);
  return { sent };
}

module.exports = { requestUpdatePushes, chatPushes, buildMessage, sendPushes };
