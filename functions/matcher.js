/**
 * Rakt Pravah - Blood Request Matching & Push Notification Engine
 * 
 * Rules:
 * - Donor Mode must be ON (donor.availability === 'available').
 * - Respect 90-day medical donation cooldown (lastDonation).
 * - Deterministic ABO/Rh blood compatibility.
 * - Distance calculation via Haversine formula against donor maxDistanceKm.
 * - Respect donor.notifyPush and donor.notifyCritical settings.
 * - Prevent duplicate notifications via request.notifiedDonorIds.
 * - Multi-device token support per user.
 * - Automatic pruning of invalid/expired FCM tokens.
 */

// Universal ABO/Rh donor compatibility matrix
// Keys: Patient blood group -> Array of acceptable donor blood groups
const COMPATIBLE_DONORS_FOR_PATIENT = {
  'O-': ['O-'],
  'O+': ['O-', 'O+'],
  'A-': ['O-', 'A-'],
  'A+': ['O-', 'O+', 'A-', 'A+'],
  'B-': ['O-', 'B-'],
  'B+': ['O-', 'O+', 'B-', 'B+'],
  'AB-': ['O-', 'A-', 'B-', 'AB-'],
  'AB+': ['O-', 'O+', 'A-', 'A+', 'B-', 'B+', 'AB-', 'AB+'],
};

// 90 days medical cooldown between whole-blood donations
const COOLDOWN_MS = 90 * 24 * 60 * 60 * 1000;

/**
 * Calculates distance in kilometers between two lat/lng coordinates using Haversine formula.
 */
function haversineDistance(lat1, lon1, lat2, lon2) {
  if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) {
    return null;
  }
  const toRad = (x) => (x * Math.PI) / 180;
  const R = 6371; // Earth radius in km

  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Reads a coordinate pair in any shape the app or Firestore produces:
 * the client's { lat, lng } maps, { latitude, longitude } objects (GeoPoint),
 * and flat latitude/longitude fields. Returns null unless both are finite.
 */
function readPoint(obj) {
  if (!obj || typeof obj !== 'object') return null;
  const lat = obj.lat ?? obj.latitude ?? obj._latitude;
  const lng = obj.lng ?? obj.longitude ?? obj._longitude;
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return { lat, lng };
}

/**
 * Checks whether donor's blood group is compatible with the patient's requirement.
 */
function isBloodCompatible(patientGroup, donorGroup, requestBloodGroups = []) {
  if (!donorGroup) return false;
  
  // The requester chose exactly which donor groups the request is open to;
  // that list is final. Falling through to the ABO table would notify donors
  // the requester deliberately left out.
  if (Array.isArray(requestBloodGroups) && requestBloodGroups.length > 0) {
    return requestBloodGroups.includes(donorGroup);
  }

  // Fallback to standard ABO/Rh compatibility table
  if (patientGroup && COMPATIBLE_DONORS_FOR_PATIENT[patientGroup]) {
    return COMPATIBLE_DONORS_FOR_PATIENT[patientGroup].includes(donorGroup);
  }

  return false;
}

/**
 * Sanitizes a token string for use as a Firestore map key.
 */
function sanitizeTokenKey(token) {
  return token.replace(/[\/.\#$\[\]]/g, '_');
}

/**
 * Evaluates whether a donor is eligible to receive a push notification for this blood request.
 * Returns { eligible: boolean, distanceKm: number | null, reason?: string }
 */
function evaluateDonorEligibility(
  donorDocData,
  donorId,
  requestData,
  now = new Date(),
  cooldownConfig = { enabled: true, durationDays: 90 },
) {
  // 1. Never notify the requester themselves
  if (donorId === requestData.requesterId) {
    return { eligible: false, reason: 'Requester cannot be notified for own request' };
  }

  // 2. Prevent duplicate notifications
  const alreadyNotified = Array.isArray(requestData.notifiedDonorIds)
    ? requestData.notifiedDonorIds.includes(donorId)
    : false;
  if (alreadyNotified) {
    return { eligible: false, reason: 'Already notified for this request' };
  }

  // 2b. Donors who already accepted or declined don't need another alert
  if (
    (Array.isArray(requestData.acceptedDonorIds) && requestData.acceptedDonorIds.includes(donorId)) ||
    (Array.isArray(requestData.declinedByDonorIds) && requestData.declinedByDonorIds.includes(donorId))
  ) {
    return { eligible: false, reason: 'Donor already responded to this request' };
  }

  // 3. User account status
  if (donorDocData.disabled === true || donorDocData.isActive === false) {
    return { eligible: false, reason: 'User account is inactive or disabled' };
  }
  if (donorDocData.approved === false) {
    return { eligible: false, reason: 'User account is not approved' };
  }

  const donorProfile = donorDocData.donor || {};

  // 4. Donor Mode check: must be explicitly 'available' (spec: Do not notify if Donor Mode is OFF)
  if (donorProfile.availability !== 'available') {
    return { eligible: false, reason: 'Donor Mode is OFF or paused' };
  }

  // 5. Cooldown check: respect dynamic cooldownConfig from admin/backend
  const isCooldownEnabled = cooldownConfig ? cooldownConfig.enabled !== false : true;
  if (isCooldownEnabled) {
    const cooldownDays = (cooldownConfig && typeof cooldownConfig.durationDays === 'number')
      ? cooldownConfig.durationDays
      : 90;
    const cooldownMs = cooldownDays * 24 * 60 * 60 * 1000;

    let lastDonationDate = null;
    if (donorProfile.lastDonation) {
      lastDonationDate = donorProfile.lastDonation.toDate
        ? donorProfile.lastDonation.toDate()
        : new Date(donorProfile.lastDonation);
    } else if (donorDocData.lastDonation) {
      lastDonationDate = donorDocData.lastDonation.toDate
        ? donorDocData.lastDonation.toDate()
        : new Date(donorDocData.lastDonation);
    }

    if (lastDonationDate && !isNaN(lastDonationDate.getTime())) {
      const elapsed = now.getTime() - lastDonationDate.getTime();
      if (elapsed < cooldownMs) {
        return {
          eligible: false,
          reason: `Donor is in medical donation cooldown (${cooldownDays} days)`,
        };
      }
    }
  }

  // 6. Notification preference switches
  if (donorProfile.notifyPush === false) {
    return { eligible: false, reason: 'Donor has disabled push notifications' };
  }
  if (donorProfile.notifyCritical === true && requestData.urgency !== 'critical') {
    return { eligible: false, reason: 'Donor only accepts critical urgency requests' };
  }

  // 7. Blood Group Compatibility
  const donorBloodGroup = donorProfile.bloodGroup || donorDocData.bloodGroup;
  const patientBloodGroup = requestData.patientBloodGroup;
  const requestBloodGroups = requestData.bloodGroups || [];

  if (!isBloodCompatible(patientBloodGroup, donorBloodGroup, requestBloodGroups)) {
    return { eligible: false, reason: `Blood group ${donorBloodGroup} incompatible with patient need` };
  }

  // 8. Location & Distance calculation
  // The donor travels to the hospital, so that's the point that matters; the
  // requester's own position is only a fallback.
  const reqPoint =
    readPoint(requestData.destination?.location) ||
    readPoint(requestData.requestLocation) ||
    readPoint(requestData);
  const reqLat = reqPoint?.lat;
  const reqLng = reqPoint?.lng;

  // Prefer the donor's last saved real position over the city-centre
  // coordinates stored at sign-up.
  const donorPoint =
    readPoint(donorDocData.location) ||
    readPoint(donorDocData) ||
    readPoint(donorProfile);
  const donorLat = donorPoint?.lat;
  const donorLng = donorPoint?.lng;
  const maxDistanceKm = typeof donorProfile.maxDistanceKm === 'number' ? donorProfile.maxDistanceKm : 30;

  let distanceKm = null;
  if (reqLat != null && reqLng != null && donorLat != null && donorLng != null) {
    distanceKm = haversineDistance(donorLat, donorLng, reqLat, reqLng);
    if (distanceKm > maxDistanceKm) {
      return { eligible: false, distanceKm, reason: `Distance ${distanceKm.toFixed(1)}km exceeds donor radius ${maxDistanceKm}km` };
    }
  } else {
    // If coordinates are missing, fallback to city/state area match
    const reqCity = (requestData.city || requestData.destination?.address || '').toLowerCase().trim();
    const donorCity = (donorDocData.city || '').toLowerCase().trim();
    if (donorCity && reqCity && !reqCity.includes(donorCity) && !donorCity.includes(reqCity)) {
      return { eligible: false, reason: 'City mismatch when coordinates unavailable' };
    }
  }

  // 9. Tokens check: Ensure donor has at least one active FCM token
  const tokens = extractTokens(donorDocData);
  if (tokens.length === 0) {
    return { eligible: false, reason: 'No registered FCM device tokens' };
  }

  return { eligible: true, distanceKm, tokens };
}

/**
 * Extracts all valid FCM token strings for a donor document.
 * Handles both fcmTokenList array and fcmTokens map (for multi-device support).
 */
function extractTokens(userData) {
  const tokenSet = new Set();

  if (Array.isArray(userData.fcmTokenList)) {
    for (const t of userData.fcmTokenList) {
      if (typeof t === 'string' && t.trim().length > 0) {
        tokenSet.add(t.trim());
      }
    }
  }

  if (userData.fcmTokens && typeof userData.fcmTokens === 'object') {
    for (const [key, val] of Object.entries(userData.fcmTokens)) {
      if (typeof val === 'string' && val.trim().length > 0) {
        tokenSet.add(val.trim());
      } else if (val && typeof val === 'object' && typeof val.token === 'string') {
        tokenSet.add(val.token.trim());
      }
    }
  }

  return Array.from(tokenSet);
}

/**
 * Matches eligible donors for a blood request and dispatches push notifications.
 * Handles invalid token cleanup, duplicate prevention, and request statistics.
 */
async function processBloodRequestNotifications(admin, requestId, requestData) {
  const db = admin.firestore();
  console.log(`[PushService] Processing notifications for request ${requestId}...`);

  if (!requestData || requestData.status !== 'searching') {
    console.log(`[PushService] Request ${requestId} is not in searching state. Skipping.`);
    return { notifiedCount: 0, skipped: true, reason: 'Not searching' };
  }

  // A multi-unit request stays 'searching' while donors join, so check the
  // units too: once every unit has a donor, nobody else should be alerted.
  const accepted = Array.isArray(requestData.acceptedDonorIds) ? requestData.acceptedDonorIds.length : 0;
  if (typeof requestData.units === 'number' && accepted >= requestData.units) {
    console.log(`[PushService] Request ${requestId} already has all units accepted. Skipping.`);
    return { notifiedCount: 0, skipped: true, reason: 'Fully accepted' };
  }

  const alreadyNotified = new Set(requestData.notifiedDonorIds || []);

  // Fetch dynamic cooldown config from config/app
  let cooldownConfig = { enabled: true, durationDays: 90 };
  try {
    const configSnap = await db.collection('config').doc('app').get();
    if (configSnap.exists) {
      const cfg = configSnap.data();
      if (typeof cfg.cooldownEnabled === 'boolean') {
        cooldownConfig.enabled = cfg.cooldownEnabled;
      }
      if (typeof cfg.cooldownDays === 'number') {
        cooldownConfig.durationDays = cfg.cooldownDays;
      }
    }
  } catch (err) {
    console.warn('[PushService] Could not read cooldown config, using defaults:', err.message);
  }

  // Query all users who have Donor Mode enabled
  const usersSnapshot = await db
    .collection('users')
    .where('donor.availability', '==', 'available')
    .get();

  console.log(`[PushService] Found ${usersSnapshot.size} total available donor candidates.`);

  const matchedDonors = [];
  const allTokens = [];
  const tokenToUserMap = new Map(); // token -> { userId, token }

  const now = new Date();

  usersSnapshot.forEach((doc) => {
    const data = doc.data();
    const evalResult = evaluateDonorEligibility(data, doc.id, requestData, now, cooldownConfig);

    if (evalResult.eligible) {
      matchedDonors.push({
        id: doc.id,
        name: data.name,
        bloodGroup: data.donor?.bloodGroup || data.bloodGroup,
        distanceKm: evalResult.distanceKm,
        tokens: evalResult.tokens,
      });

      for (const token of evalResult.tokens) {
        allTokens.push(token);
        tokenToUserMap.set(token, { userId: doc.id, token });
      }
    } else {
      // Diagnostic log (without sensitive data)
      // console.log(`[PushService] Donor ${doc.id} ineligible: ${evalResult.reason}`);
    }
  });

  console.log(`[PushService] Matched ${matchedDonors.length} eligible donors with ${allTokens.length} device tokens.`);

  if (allTokens.length === 0) {
    return { notifiedCount: 0, matchedDonors: matchedDonors.length, sentTokens: 0 };
  }

  // Construct Notification Content according to specification
  const urgencyLabel = requestData.urgency === 'critical' ? 'Urgent' : 'Urgent';
  const patientBlood =
    requestData.patientBloodGroup ||
    (Array.isArray(requestData.bloodGroups) && requestData.bloodGroups[0]) ||
    'Blood';
  const hospitalName =
    requestData.destination?.name ||
    requestData.requestLocationLabel ||
    'Nearby Hospital';

  const title = `🩸 ${urgencyLabel} Blood Request`;

  // Build message per token or multicast batches (max 500 per batch for FCM sendEachForMulticast)
  const invalidTokens = [];
  const successfullyNotifiedDonorIds = new Set();
  const BATCH_SIZE = 500;

  for (let i = 0; i < allTokens.length; i += BATCH_SIZE) {
    const batchTokens = allTokens.slice(i, i + BATCH_SIZE);

    // Dynamic distance text if available, or hospital address
    let bodyText = `${patientBlood} blood is urgently needed near ${hospitalName}.`;

    const message = {
      notification: {
        title: title,
        body: bodyText,
      },
      data: {
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        type: 'invitation',
        requestId: requestId,
        route: `/invitations/${requestId}`,
        urgency: String(requestData.urgency || 'urgent'),
        patientBloodGroup: String(patientBlood),
        destinationName: String(hospitalName),
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'bloodlink_alerts',
          icon: 'ic_notification',
          color: '#D32F2F',
          priority: 'max',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
      apns: {
        headers: {
          'apns-priority': '10',
          'apns-push-type': 'alert',
        },
        payload: {
          aps: {
            alert: {
              title: title,
              body: bodyText,
            },
            sound: 'default',
            badge: 1,
            category: 'BLOOD_REQUEST_CATEGORY',
            'content-available': 1,
            'mutable-content': 1,
          },
          requestId: requestId,
          type: 'invitation',
          route: `/invitations/${requestId}`,
        },
      },
      tokens: batchTokens,
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(`[PushService] Multicast batch result: ${response.successCount} succeeded, ${response.failureCount} failed.`);

      response.responses.forEach((resp, idx) => {
        const token = batchTokens[idx];
        const userMapping = tokenToUserMap.get(token);

        if (resp.success) {
          if (userMapping) {
            successfullyNotifiedDonorIds.add(userMapping.userId);
          }
        } else {
          const errCode = resp.error?.code;
          console.warn(`[PushService] Token send error (${errCode}): ${resp.error?.message}`);

          // Automatic cleanup of invalid or expired registration tokens
          if (
            errCode === 'messaging/invalid-registration-token' ||
            errCode === 'messaging/registration-token-not-registered'
          ) {
            invalidTokens.push({ token, userId: userMapping?.userId });
          }
        }
      });
    } catch (sendErr) {
      console.error(`[PushService] Failed sending multicast batch:`, sendErr);
    }
  }

  // Remove invalid/expired tokens from user documents
  if (invalidTokens.length > 0) {
    console.log(`[PushService] Pruning ${invalidTokens.length} expired/invalid FCM tokens...`);
    const batch = db.batch();
    for (const item of invalidTokens) {
      if (item.userId) {
        const userRef = db.collection('users').doc(item.userId);
        const safeKey = sanitizeTokenKey(item.token);
        batch.update(userRef, {
          fcmTokenList: admin.firestore.FieldValue.arrayRemove(item.token),
          [`fcmTokens.${safeKey}`]: admin.firestore.FieldValue.delete(),
        });
      }
    }
    await batch.commit().catch((e) => console.error('[PushService] Batch pruning error:', e));
  }

  // Record notified donors and update stats on the blood request document
  const newlyNotifiedList = Array.from(successfullyNotifiedDonorIds);
  if (newlyNotifiedList.length > 0) {
    await db
      .collection('blood_requests')
      .doc(requestId)
      .update({
        notifiedDonorIds: admin.firestore.FieldValue.arrayUnion(...newlyNotifiedList),
        donorsContacted: admin.firestore.FieldValue.increment(newlyNotifiedList.length),
        lastNotificationSentAt: admin.firestore.FieldValue.serverTimestamp(),
      })
      .catch((e) => console.error('[PushService] Failed updating request document:', e));
  }

  return {
    notifiedCount: newlyNotifiedList.length,
    matchedDonors: matchedDonors.length,
    sentTokens: allTokens.length,
    prunedTokens: invalidTokens.length,
  };
}

module.exports = {
  readPoint,
  haversineDistance,
  isBloodCompatible,
  evaluateDonorEligibility,
  extractTokens,
  sanitizeTokenKey,
  processBloodRequestNotifications,
};
