const assert = require('assert');
const {
  haversineDistance,
  isBloodCompatible,
  evaluateDonorEligibility,
  extractTokens,
  sanitizeTokenKey,
} = require('../matcher');

console.log('--- Running Matcher & Eligibility Unit Tests ---');

// 1. Distance Calculation Tests
{
  // Test distance between two points in Delhi (~2.4 km)
  const d = haversineDistance(28.6139, 77.2090, 28.6250, 77.2300);
  assert(d > 2.0 && d < 3.0, `Expected distance ~2.4km, got ${d}`);
  console.log('✓ Haversine distance calculation is accurate (~2.4 km)');
}

// 2. Deterministic ABO/Rh Compatibility Tests
{
  // O- can donate to all
  assert.strictEqual(isBloodCompatible('O+', 'O-'), true);
  assert.strictEqual(isBloodCompatible('A+', 'O-'), true);
  assert.strictEqual(isBloodCompatible('AB+', 'O-'), true);

  // O+ cannot donate to O- or A-
  assert.strictEqual(isBloodCompatible('O-', 'O+'), false);
  assert.strictEqual(isBloodCompatible('A-', 'O+'), false);
  assert.strictEqual(isBloodCompatible('A+', 'O+'), true);

  // AB+ cannot donate to A+ or O+
  assert.strictEqual(isBloodCompatible('A+', 'AB+'), false);
  assert.strictEqual(isBloodCompatible('AB+', 'AB+'), true);

  // Explicit request bloodGroups list takes precedence
  assert.strictEqual(isBloodCompatible('O+', 'A+', ['A+', 'O+']), true);
  console.log('✓ Deterministic ABO/Rh blood compatibility verified');
}

// 3. Multi-Device Token Extraction Tests
{
  const user = {
    fcmTokenList: ['token_alpha', 'token_beta'],
    fcmTokens: {
      key1: { token: 'token_beta' }, // Duplicate
      key2: { token: 'token_gamma' },
      key3: 'token_delta',
    },
  };
  const tokens = extractTokens(user);
  assert.strictEqual(tokens.length, 4);
  assert(tokens.includes('token_alpha'));
  assert(tokens.includes('token_beta'));
  assert(tokens.includes('token_gamma'));
  assert(tokens.includes('token_delta'));
  console.log('✓ Multi-device token extraction and deduplication verified');
}

// 4. Eligibility Evaluation Tests
{
  const now = new Date('2026-10-05T12:00:00Z');

  const baseRequest = {
    requesterId: 'user_requester',
    patientBloodGroup: 'A+',
    bloodGroups: ['A+', 'A-', 'O+', 'O-'],
    urgency: 'urgent',
    destination: {
      name: 'City Hospital',
      location: { latitude: 28.6139, longitude: 77.2090 },
    },
    notifiedDonorIds: [],
  };

  const validDonor = {
    name: 'Rahul Kumar',
    bloodGroup: 'A+',
    latitude: 28.6250,
    longitude: 77.2300,
    fcmTokenList: ['fcm_valid_123'],
    donor: {
      availability: 'available',
      bloodGroup: 'A+',
      notifyPush: true,
      notifyCritical: false,
      maxDistanceKm: 10,
    },
  };

  // 4a. Valid available donor matches
  const resValid = evaluateDonorEligibility(validDonor, 'donor_1', baseRequest, now);
  assert.strictEqual(resValid.eligible, true);
  assert(resValid.distanceKm > 2.0 && resValid.distanceKm < 3.0);
  console.log('✓ Eligible nearby donor correctly matches');

  // 4b. Requester cannot be notified for own request
  const resSelf = evaluateDonorEligibility(validDonor, 'user_requester', baseRequest, now);
  assert.strictEqual(resSelf.eligible, false);
  assert.strictEqual(resSelf.reason, 'Requester cannot be notified for own request');
  console.log('✓ Requester self-notification prevented');

  // 4c. Donor Mode OFF must NOT be notified
  const offDonor = {
    ...validDonor,
    donor: { ...validDonor.donor, availability: 'off' },
  };
  const resOff = evaluateDonorEligibility(offDonor, 'donor_2', baseRequest, now);
  assert.strictEqual(resOff.eligible, false);
  console.log('✓ Donors with Donor Mode OFF are excluded');

  // 4d. Duplicate notification prevention
  const reqWithNotified = {
    ...baseRequest,
    notifiedDonorIds: ['donor_1'],
  };
  const resDup = evaluateDonorEligibility(validDonor, 'donor_1', reqWithNotified, now);
  assert.strictEqual(resDup.eligible, false);
  assert.strictEqual(resDup.reason, 'Already notified for this request');
  console.log('✓ Duplicate notifications prevented');

  // 4e. Medical Cooldown (90 days)
  const recentDonationDate = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000); // 30 days ago
  const cooldownDonor = {
    ...validDonor,
    donor: {
      ...validDonor.donor,
      lastDonation: recentDonationDate,
    },
  };
  const resCooldown = evaluateDonorEligibility(cooldownDonor, 'donor_3', baseRequest, now);
  assert.strictEqual(resCooldown.eligible, false);
  assert(resCooldown.reason.includes('cooldown'));
  console.log('✓ Donors in 90-day medical cooldown are excluded');

  // 4e-2. When Cooldown is OFF (enabled: false), donor is eligible even with recent donation
  const resCooldownOff = evaluateDonorEligibility(
    cooldownDonor,
    'donor_3',
    baseRequest,
    now,
    { enabled: false, durationDays: 90 },
  );
  assert.strictEqual(resCooldownOff.eligible, true);
  console.log('✓ When Cooldown is OFF, donors with recent donation remain eligible');

  // 4e-3. When Cooldown duration is custom (e.g. 15 days), donation 30 days ago is eligible
  const resCooldown15 = evaluateDonorEligibility(
    cooldownDonor,
    'donor_3',
    baseRequest,
    now,
    { enabled: true, durationDays: 15 },
  );
  assert.strictEqual(resCooldown15.eligible, true);
  console.log('✓ Custom cooldown duration (15 days) correctly allows 30-day donor');

  // 4f. Incompatible Blood Group
  const bPosDonor = {
    ...validDonor,
    donor: { ...validDonor.donor, bloodGroup: 'B+' },
    bloodGroup: 'B+',
  };
  const resIncompatible = evaluateDonorEligibility(bPosDonor, 'donor_4', baseRequest, now);
  assert.strictEqual(resIncompatible.eligible, false);
  console.log('✓ Incompatible blood group donors are excluded');

  // 4g. Max Distance restriction
  const farDonor = {
    ...validDonor,
    latitude: 28.9000,
    longitude: 77.8000, // ~60 km away
    donor: { ...validDonor.donor, maxDistanceKm: 15 },
  };
  const resFar = evaluateDonorEligibility(farDonor, 'donor_5', baseRequest, now);
  assert.strictEqual(resFar.eligible, false);
  assert(resFar.reason.includes('exceeds donor radius'));
  console.log('✓ Donors beyond their chosen maxDistanceKm radius are excluded');

  // 4h. Critical requests only switch
  const criticalOnlyDonor = {
    ...validDonor,
    donor: { ...validDonor.donor, notifyCritical: true },
  };
  const resCritUrgent = evaluateDonorEligibility(criticalOnlyDonor, 'donor_6', baseRequest, now);
  assert.strictEqual(resCritUrgent.eligible, false);

  const critRequest = { ...baseRequest, urgency: 'critical' };
  const resCritPass = evaluateDonorEligibility(criticalOnlyDonor, 'donor_6', critRequest, now);
  assert.strictEqual(resCritPass.eligible, true);
  console.log('✓ Critical-only notification preference honored');
}

// 5. Token Key Sanitization Tests
{
  const token = 'fcm/token.with#special$chars[and]brackets';
  const clean = sanitizeTokenKey(token);
  assert.strictEqual(clean, 'fcm_token_with_special_chars_and_brackets');
  console.log('✓ Token key sanitization verified');
}

console.log('\nALL MATCHER UNIT TESTS PASSED SUCCESSFULLY!');
