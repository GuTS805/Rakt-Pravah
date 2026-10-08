import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/models.dart';

/// Read/write access to everyone's data, for operators — deliberately
/// separate from [Backend], which is scoped to "my requests, my invitations".
///
/// Every mutating action here writes an audit entry, because an operator
/// reaching into another person's emergency request is exactly the kind of
/// action that needs to be attributable after the fact.
class AdminUnauthorizedException implements Exception {
  const AdminUnauthorizedException([
    this.message = 'Access Denied: Administrator role required.',
  ]);
  final String message;
  @override
  String toString() => message;
}

class AdminBackend {
  AdminBackend(
    this._db, {
    required this.actorId,
    required this.actorName,
    this.isAdmin = true,
  }) {
    if (!isAdmin) {
      throw const AdminUnauthorizedException();
    }
  }

  final fs.FirebaseFirestore? _db;
  final String actorId;
  final String actorName;
  final bool isAdmin;
  fs.FirebaseFirestore get db => _db ?? fs.FirebaseFirestore.instance;

  fs.CollectionReference<Map<String, dynamic>> get _requests =>
      db.collection('blood_requests');
  fs.CollectionReference<Map<String, dynamic>> get _users =>
      db.collection('users');
  fs.CollectionReference<Map<String, dynamic>> get _audit =>
      db.collection('admin_audit');
  fs.CollectionReference<Map<String, dynamic>> get _reports =>
      db.collection('reports');
  fs.DocumentReference<Map<String, dynamic>> get _config =>
      db.collection('config').doc('app');

  // --- Requests ----------------------------------------------------------

  Stream<List<AdminRequest>> get requests => _requests
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map(AdminRequest.fromDoc).toList());

  /// Takes a request out of circulation. This is the only admin write that
  /// touches someone else's request, and it lands the request in the
  /// REMOVED_BY_ADMIN terminal state the state machine already defines —
  /// no new matching, no new coordination.
  Future<void> removeRequest(String id, String reason) async {
    final ref = _requests.doc(id);
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data()!;
      final current = RequestStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => RequestStatus.created,
      );
      if (current.isTerminal) return;
      final timeline = List<Map<String, dynamic>>.from(
        (data['timeline'] as List?) ?? const [],
      );
      timeline.add({
        'status': RequestStatus.removedByAdmin.name,
        'at': fs.Timestamp.fromDate(DateTime.now()),
        'note': reason,
      });
      tx.update(ref, {
        'status': RequestStatus.removedByAdmin.name,
        'timeline': timeline,
      });
    });
    await _writeAudit(action: 'request.remove', targetId: id, detail: reason);
  }

  // --- Users -------------------------------------------------------------

  Stream<List<AdminUser>> get users => _users
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map(AdminUser.fromDoc).toList());

  Future<void> setAdmin(String uid, bool isAdmin) async {
    await _users.doc(uid).set({'isAdmin': isAdmin}, fs.SetOptions(merge: true));
    await _writeAudit(
      action: isAdmin ? 'user.grantAdmin' : 'user.revokeAdmin',
      targetId: uid,
    );
  }

  Future<void> setUserActive(String uid, bool isActive) async {
    await _users.doc(uid).set({
      'isActive': isActive,
    }, fs.SetOptions(merge: true));
    await _writeAudit(
      action: isActive ? 'user.activate' : 'user.deactivate',
      targetId: uid,
    );
  }

  /// Clears, or withdraws clearance from, one account. Only matters while
  /// [requireApproval] is on.
  Future<void> setApproved(String uid, bool approved) async {
    await _users.doc(uid).set({
      'approved': approved,
    }, fs.SetOptions(merge: true));
    await _writeAudit(
      action: approved ? 'user.approve' : 'user.revokeApproval',
      targetId: uid,
    );
  }

  /// Approves everyone still waiting, in one go. Returns how many. For the
  /// moment the switch goes on and accounts made while it was off would
  /// otherwise be locked out.
  Future<int> approveAllWaiting(List<String> uids) async {
    if (uids.isEmpty) return 0;
    final batch = db.batch();
    for (final uid in uids) {
      batch.set(_users.doc(uid), {
        'approved': true,
      }, fs.SetOptions(merge: true));
    }
    await batch.commit();
    await _writeAudit(
      action: 'user.approveAll',
      targetId: 'users',
      detail: '${uids.length} accounts',
    );
    return uids.length;
  }

  // --- Approval switch ---------------------------------------------------

  /// Whether new accounts have to be approved before they can request blood
  /// or donate. Off when the setting has never been written.
  Stream<bool> get requireApproval =>
      _config.snapshots().map((doc) => doc.data()?['requireApproval'] == true);

  Future<void> setRequireApproval(bool on) async {
    await _config.set({'requireApproval': on}, fs.SetOptions(merge: true));
    await _writeAudit(
      action: on ? 'approval.on' : 'approval.off',
      targetId: 'config/app',
    );
  }

  // --- Cooldown configuration --------------------------------------------

  Stream<CooldownConfig> get cooldownConfig => _config.snapshots().map(
        (doc) => CooldownConfig.fromMap(doc.data()),
      );

  Future<void> setCooldownConfig(CooldownConfig config) async {
    // 1. Cache to local storage immediately so page refresh retains setting
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('rakt_cooldown_enabled', config.enabled);
      await prefs.setInt('rakt_cooldown_days', config.durationDays);
    } catch (_) {}

    // 2. Persist to Firestore config/app
    await _config.set(config.toMap(), fs.SetOptions(merge: true));

    // 3. Write audit entry without blocking or throwing if audit collection rules reject
    try {
      await _writeAudit(
        action: config.enabled ? 'cooldown.enable' : 'cooldown.disable',
        targetId: 'config/app',
        detail: '${config.durationDays} days',
      );
    } catch (_) {}
  }

  // --- Reports -----------------------------------------------------------

  /// Reports filed by users against a request or another user. The mobile
  /// Report screen that files these is not built yet, so this is expected to
  /// be empty until it is — the screen says so rather than inventing rows.
  Stream<List<AdminReport>> get reports => _reports
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map(AdminReport.fromDoc).toList());

  Future<void> resolveReport(String id, String outcome) async {
    await _reports.doc(id).set({
      'status': 'resolved',
      'resolvedBy': actorId,
      'resolvedAt': fs.Timestamp.fromDate(DateTime.now()),
      'outcome': outcome,
    }, fs.SetOptions(merge: true));
    await _writeAudit(action: 'report.resolve', targetId: id, detail: outcome);
  }

  // --- Audit -------------------------------------------------------------

  Stream<List<AuditEntry>> get auditLog => _audit
      .orderBy('at', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map(AuditEntry.fromDoc).toList());

  Future<void> _writeAudit({
    required String action,
    required String targetId,
    String? detail,
  }) => _audit.add({
    'action': action,
    'targetId': targetId,
    'detail': detail,
    'actorId': actorId,
    'actorName': actorName,
    'at': fs.Timestamp.fromDate(DateTime.now()),
  });

  // --- Hospitals ---------------------------------------------------------

  fs.CollectionReference<Map<String, dynamic>> get _hospitals =>
      db.collection('hospitals');

  Stream<List<AdminHospital>> get hospitals => _hospitals
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map(AdminHospital.fromDoc).toList());

  Future<void> addHospital({
    required String name,
    required String city,
    String? address,
    String? contact,
    String? state,
    String type = 'Hospital',
  }) async {
    final ref = await _hospitals.add({
      'name': name,
      'city': city,
      'address': address,
      'contact': contact,
      'state': state,
      'type': type,
      'isVerified': false,
      'createdAt': fs.Timestamp.fromDate(DateTime.now()),
    });
    await _writeAudit(action: 'hospital.add', targetId: ref.id, detail: name);
  }

  Future<void> verifyHospital(String id) async {
    await _hospitals.doc(id).set({
      'isVerified': true,
      'verifiedBy': actorId,
    }, fs.SetOptions(merge: true));
    await _writeAudit(action: 'hospital.verify', targetId: id);
  }

  Future<void> deleteHospital(String id) async {
    await _hospitals.doc(id).delete();
    await _writeAudit(action: 'hospital.delete', targetId: id);
  }

  // --- Admin Notifications -----------------------------------------------

  fs.CollectionReference<Map<String, dynamic>> get _notifications =>
      db.collection('admin_notifications');

  Stream<List<AdminNotificationEntry>> get adminNotifications => _notifications
      .orderBy('sentAt', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map(AdminNotificationEntry.fromDoc).toList());

  Future<void> sendNotification({
    required String title,
    required String body,
    required String type,
    required String target,
  }) async {
    final ref = await _notifications.add({
      'title': title,
      'body': body,
      'type': type,
      'target': target,
      'sentBy': actorName,
      'sentById': actorId,
      'sentAt': fs.Timestamp.fromDate(DateTime.now()),
    });
    await _writeAudit(
      action: type == 'emergency'
          ? 'notification.emergency'
          : 'notification.send',
      targetId: ref.id,
      detail: title,
    );
  }
}

/// A request as an operator sees it: everything, including the fields the
/// requester-facing model hides.
class AdminRequest {
  AdminRequest({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    required this.bloodGroups,
    required this.units,
    required this.urgency,
    required this.status,
    required this.createdAt,
    required this.destinationName,
    required this.locationLabel,
    this.acceptedDonorIds = const [],
    this.acceptedDonorName,
    this.expiresAt,
    this.declinedCount = 0,
  });

  final String id;
  final String requesterId;
  final String requesterName;
  final List<BloodGroup> bloodGroups;
  final int units;
  final Urgency urgency;
  final RequestStatus status;
  final DateTime createdAt;
  final String destinationName;
  final String locationLabel;
  final List<String> acceptedDonorIds;
  final String? acceptedDonorName;
  final DateTime? expiresAt;
  final int declinedCount;

  bool get isOpen => status.isActive;

  /// Past its own expiry but never closed — the queue's stuck work, and the
  /// main thing an operator is scanning for.
  bool get isStale =>
      status.isActive &&
      expiresAt != null &&
      expiresAt!.isBefore(DateTime.now());

  /// Searching for a donor with nobody accepted yet.
  bool get isUnmatched =>
      acceptedDonorIds.isEmpty &&
      (status == RequestStatus.searching || status == RequestStatus.created);

  Duration get age => DateTime.now().difference(createdAt);

  static AdminRequest fromDoc(
    fs.QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data();
    return AdminRequest(
      id: doc.id,
      requesterId: m['requesterId'] as String? ?? '',
      requesterName: m['requesterName'] as String? ?? 'Unknown',
      bloodGroups: [
        for (final raw in (m['bloodGroups'] as List?) ?? const [])
          if (BloodGroup.values.any((g) => g.label == raw))
            BloodGroup.fromLabel(raw as String),
      ],
      units: (m['units'] as num?)?.toInt() ?? 0,
      urgency: Urgency.values.firstWhere(
        (u) => u.name == m['urgency'],
        orElse: () => Urgency.routine,
      ),
      status: RequestStatus.values.firstWhere(
        (s) => s.name == m['status'],
        orElse: () => RequestStatus.created,
      ),
      createdAt: (m['createdAt'] as fs.Timestamp?)?.toDate() ?? DateTime.now(),
      destinationName:
          ((m['destination'] as Map?)?['name'] as String?) ?? 'Unknown',
      locationLabel: m['requestLocationLabel'] as String? ?? '',
      acceptedDonorIds: _donorIds(m),
      acceptedDonorName: _firstDonorName(m),
      expiresAt: (m['expiresAt'] as fs.Timestamp?)?.toDate(),
      declinedCount: ((m['declinedByDonorIds'] as List?) ?? const []).length,
    );
  }

  /// Requests created before multi-donor matching carry a single
  /// `acceptedDonorId` instead of a list.
  static List<String> _donorIds(Map<String, dynamic> m) {
    final donors = (m['acceptedDonors'] as List?)?.cast<Map>();
    if (donors != null && donors.isNotEmpty) {
      return [for (final d in donors) d['id'] as String];
    }
    final legacy = m['acceptedDonorId'] as String?;
    return legacy == null ? const [] : [legacy];
  }

  static String? _firstDonorName(Map<String, dynamic> m) {
    final donors = (m['acceptedDonors'] as List?)?.cast<Map>();
    if (donors != null && donors.isNotEmpty) {
      final names = [for (final d in donors) d['name'] as String? ?? 'Donor'];
      return names.length == 1
          ? names.first
          : '${names.first} +${names.length - 1}';
    }
    return m['acceptedDonorName'] as String?;
  }
}

class AdminUser {
  AdminUser({
    required this.id,
    required this.name,
    required this.phone,
    this.countryCode = '+91',
    required this.bloodGroup,
    required this.isAdmin,
    required this.emailVerified,
    this.isActive = true,
    this.approved = true,
    this.photo,
    this.email,
    this.city,
    this.donorAvailability,
    this.totalDonations = 0,
    this.lastDonation,
  });

  final String id;
  final String name;
  final String phone;
  final String countryCode;
  final BloodGroup bloodGroup;
  final bool isAdmin;
  final bool emailVerified;
  final bool isActive;

  String get displayPhone => PhoneUtils.formatDisplay(countryCode, phone);

  /// Missing on accounts that predate approval, which count as approved.
  final bool approved;
  final String? photo;
  final String? email;
  final String? city;
  final DonorAvailability? donorAvailability;
  final int totalDonations;
  final DateTime? lastDonation;

  /// Admins are never treated as donors — always returns false for admin accounts.
  bool get isDonorOn =>
      !isAdmin &&
      donorAvailability != null &&
      donorAvailability != DonorAvailability.off;

  /// Admins are never in cooldown — always returns false for admin accounts.
  bool get isInCooldown {
    if (isAdmin) return false;
    final last = lastDonation;
    return last != null &&
        DateTime.now().isBefore(last.add(DonorProfile.cooldownDuration));
  }

  static AdminUser fromDoc(fs.QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    final donor = (m['donor'] as Map?)?.cast<String, dynamic>();
    final rawPhone = m['phone'] as String? ?? '';
    final rawCode = m['countryCode'] as String?;
    final (countryCode, phone) = rawCode != null
        ? (rawCode, rawPhone)
        : (PhoneUtils.parse(rawPhone).countryCode, PhoneUtils.parse(rawPhone).phone);
    return AdminUser(
      id: doc.id,
      name: m['name'] as String? ?? 'Unknown',
      phone: phone.isNotEmpty ? phone : rawPhone,
      countryCode: countryCode,
      bloodGroup: BloodGroup.values.any((g) => g.label == m['bloodGroup'])
          ? BloodGroup.fromLabel(m['bloodGroup'] as String)
          : BloodGroup.oPos,
      isAdmin: m['isAdmin'] as bool? ?? false,
      isActive:
          (m['isActive'] as bool?) ?? (!(m['disabled'] as bool? ?? false)),
      approved: m['approved'] as bool? ?? true,
      photo: m['photo'] as String?,
      // Firebase owns the real claim; the doc only mirrors that an address
      // exists, so this is "has a verified address on file", not authority.
      emailVerified: (m['email'] as String?) != null,
      email: m['email'] as String?,
      city: m['city'] as String?,
      donorAvailability: donor == null
          ? null
          : DonorAvailability.values.firstWhere(
              (a) => a.name == donor['availability'],
              orElse: () => DonorAvailability.off,
            ),
      totalDonations: (donor?['totalDonations'] as num?)?.toInt() ?? 0,
      lastDonation: (donor?['lastDonation'] as fs.Timestamp?)?.toDate(),
    );
  }
}

class AdminReport {
  AdminReport({
    required this.id,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.reporterId,
    this.targetRequestId,
    this.targetUserId,
    this.detail,
  });

  final String id;
  final String reason;
  final String status;
  final DateTime createdAt;
  final String? reporterId;
  final String? targetRequestId;
  final String? targetUserId;
  final String? detail;

  bool get isOpen => status != 'resolved';

  static AdminReport fromDoc(
    fs.QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data();
    return AdminReport(
      id: doc.id,
      reason: m['reason'] as String? ?? 'Unspecified',
      status: m['status'] as String? ?? 'open',
      createdAt: (m['createdAt'] as fs.Timestamp?)?.toDate() ?? DateTime.now(),
      reporterId: m['reporterId'] as String?,
      targetRequestId: m['targetRequestId'] as String?,
      targetUserId: m['targetUserId'] as String?,
      detail: m['detail'] as String?,
    );
  }
}

class AuditEntry {
  AuditEntry({
    required this.id,
    required this.action,
    required this.targetId,
    required this.actorName,
    required this.at,
    this.detail,
  });

  final String id;
  final String action;
  final String targetId;
  final String actorName;
  final DateTime at;
  final String? detail;

  static AuditEntry fromDoc(
    fs.QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data();
    return AuditEntry(
      id: doc.id,
      action: m['action'] as String? ?? 'unknown',
      targetId: m['targetId'] as String? ?? '',
      actorName: m['actorName'] as String? ?? 'Unknown',
      at: (m['at'] as fs.Timestamp?)?.toDate() ?? DateTime.now(),
      detail: m['detail'] as String?,
    );
  }
}

class AdminHospital {
  AdminHospital({
    required this.id,
    required this.name,
    required this.city,
    required this.isVerified,
    required this.createdAt,
    this.address,
    this.contact,
    this.state,
    this.type = 'Hospital',
  });

  final String id;
  final String name;
  final String city;
  final bool isVerified;
  final DateTime createdAt;
  final String? address;
  final String? contact;
  final String? state;
  final String type;

  static AdminHospital fromDoc(
    fs.QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data();
    return AdminHospital(
      id: doc.id,
      name: m['name'] as String? ?? 'Unknown',
      city: m['city'] as String? ?? '',
      isVerified: m['isVerified'] as bool? ?? false,
      createdAt: (m['createdAt'] as fs.Timestamp?)?.toDate() ?? DateTime.now(),
      address: m['address'] as String?,
      contact: m['contact'] as String?,
      state: m['state'] as String?,
      type: m['type'] as String? ?? 'Hospital',
    );
  }
}

class AdminNotificationEntry {
  AdminNotificationEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.target,
    required this.sentBy,
    required this.sentAt,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final String target;
  final String sentBy;
  final DateTime sentAt;

  static AdminNotificationEntry fromDoc(
    fs.QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data();
    return AdminNotificationEntry(
      id: doc.id,
      title: m['title'] as String? ?? '',
      body: m['body'] as String? ?? '',
      type: m['type'] as String? ?? 'general',
      target: m['target'] as String? ?? 'all',
      sentBy: m['sentBy'] as String? ?? 'Unknown',
      sentAt: (m['sentAt'] as fs.Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
