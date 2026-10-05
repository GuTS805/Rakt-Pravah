/**
 * Rakt Pravah - Cloud Functions
 * Automated Push Notifications for Emergency Blood Requests
 */

const admin = require('firebase-admin');
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onRequest, onCall, HttpsError } = require('firebase-functions/v2/https');
const { processBloodRequestNotifications } = require('./matcher');

if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Triggered automatically when a new blood request is created in Firestore.
 */
exports.onBloodRequestCreated = onDocumentCreated(
  {
    document: 'blood_requests/{requestId}',
    region: 'us-central1',
    memory: '256MiB',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      console.log('No snapshot data found on document creation.');
      return null;
    }

    const requestId = event.params.requestId;
    const requestData = snap.data();

    return processBloodRequestNotifications(admin, requestId, requestData);
  }
);

/**
 * Triggered when a blood request is updated.
 * Handles cases where a request is reactivated to 'searching' or a new search wave begins.
 */
exports.onBloodRequestUpdated = onDocumentUpdated(
  {
    document: 'blood_requests/{requestId}',
    region: 'us-central1',
    memory: '256MiB',
  },
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const requestId = event.params.requestId;

    // Only process if status transitioned into 'searching' or radius expanded
    const becameSearching = beforeData.status !== 'searching' && afterData.status === 'searching';
    const radiusExpanded = (afterData.searchRadiusKm || 0) > (beforeData.searchRadiusKm || 0);

    if (becameSearching || radiusExpanded) {
      console.log(`[PushService] Request ${requestId} transitioned or expanded. Processing notifications.`);
      return processBloodRequestNotifications(admin, requestId, afterData);
    }

    return null;
  }
);

/**
 * Callable Function: Can be called by authenticated users or backend tasks to dispatch notifications.
 */
exports.notifyMatchingDonors = onCall(
  {
    region: 'us-central1',
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be signed in to invoke notification matching.');
    }

    const { requestId } = request.data || {};
    if (!requestId) {
      throw new HttpsError('invalid-argument', 'Missing required requestId.');
    }

    const doc = await admin.firestore().collection('blood_requests').doc(requestId).get();
    if (!doc.exists) {
      throw new HttpsError('not-found', `Blood request ${requestId} not found.`);
    }

    const result = await processBloodRequestNotifications(admin, requestId, doc.data());
    return result;
  }
);

/**
 * HTTP Webhook: Can be invoked via standard HTTP POST request.
 */
exports.apiNotifyRequest = onRequest(
  {
    region: 'us-central1',
    cors: true,
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      return res.status(405).json({ error: 'Method not allowed. Use POST.' });
    }

    const requestId = req.body?.requestId || req.query?.requestId;
    if (!requestId) {
      return res.status(400).json({ error: 'Missing requestId parameter.' });
    }

    try {
      const doc = await admin.firestore().collection('blood_requests').doc(requestId).get();
      if (!doc.exists) {
        return res.status(404).json({ error: `Blood request ${requestId} not found.` });
      }

      const result = await processBloodRequestNotifications(admin, requestId, doc.data());
      return res.status(200).json({ success: true, result });
    } catch (err) {
      console.error(`[PushService] HTTP trigger error for request ${requestId}:`, err);
      return res.status(500).json({ error: err.message });
    }
  }
);
