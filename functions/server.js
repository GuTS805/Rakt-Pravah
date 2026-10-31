/**
 * Rakt Pravah - Push Notification Backend Server
 * 
 * Runs as a standalone Node.js server daemon.
 * - Listens in real-time to active blood requests in Firestore.
 * - Exposes HTTP REST API for on-demand triggering or health checks.
 */

const express = require('express');
const cors = require('cors');
const admin = require('firebase-admin');
const { processBloodRequestNotifications } = require('./matcher');

// Initialize Firebase Admin SDK
if (!admin.apps.length) {
  // Uses GOOGLE_APPLICATION_CREDENTIALS or Firebase project defaults
  admin.initializeApp({
    projectId: process.env.FIREBASE_PROJECT_ID || 'nobloodlink',
  });
}

const db = admin.firestore();
const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 8080;

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'rakt-pravah-push-notifications',
    timestamp: new Date().toISOString(),
  });
});

// Manual / Webhook trigger endpoint
app.post('/api/notify-request', async (req, res) => {
  const { requestId } = req.body;
  if (!requestId) {
    return res.status(400).json({ error: 'Missing required field: requestId' });
  }

  try {
    const doc = await db.collection('blood_requests').doc(requestId).get();
    if (!doc.exists) {
      return res.status(404).json({ error: `Blood request ${requestId} not found` });
    }

    const result = await processBloodRequestNotifications(admin, requestId, doc.data());
    return res.json({ success: true, result });
  } catch (err) {
    console.error(`[Server] Error processing request ${requestId}:`, err);
    return res.status(500).json({ error: err.message });
  }
});

// Real-time Firestore Listener
let isFirstSnapshot = true;
const processedRequestTimestamps = new Map();

function startFirestoreListener() {
  console.log('[Server] Starting real-time listener on blood_requests collection...');

  db.collection('blood_requests')
    .where('status', '==', 'searching')
    .onSnapshot(
      (snapshot) => {
        snapshot.docChanges().forEach(async (change) => {
          const doc = change.doc;
          const data = doc.data();
          const requestId = doc.id;

          if (change.type === 'added' || change.type === 'modified') {
            const createdAt = data.createdAt ? (data.createdAt.toDate ? data.createdAt.toDate() : new Date(data.createdAt)) : new Date();
            const ageMs = Date.now() - createdAt.getTime();

            // On server boot, only process active requests created in the last 2 hours
            if (isFirstSnapshot && ageMs > 2 * 60 * 60 * 1000) {
              return;
            }

            // Check if already notified
            const notifiedDonorIds = data.notifiedDonorIds || [];
            const previousCount = processedRequestTimestamps.get(requestId) || 0;

            if (notifiedDonorIds.length <= previousCount && !isFirstSnapshot && change.type !== 'added') {
              return;
            }

            processedRequestTimestamps.set(requestId, notifiedDonorIds.length);

            try {
              console.log(`[Server] Dispatching notifications for ${change.type} request ${requestId}`);
              await processBloodRequestNotifications(admin, requestId, data);
            } catch (err) {
              console.error(`[Server] Error processing ${requestId}:`, err);
            }
          }
        });

        isFirstSnapshot = false;
      },
      (error) => {
        console.error('[Server] Firestore listener error:', error);
      }
    );
}

// Start server
app.listen(PORT, () => {
  console.log(`[Server] Rakt Pravah Push Notification Server listening on port ${PORT}`);
  try {
    startFirestoreListener();
  } catch (err) {
    console.warn('[Server] Could not initialize automatic listener (waiting for valid credentials):', err.message);
  }
});
