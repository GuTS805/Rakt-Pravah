import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../data/models/models.dart';

/// Read/write access to everyone's data, for operators — deliberately
/// separate from [Backend], which is scoped to "my requests, my invitations".
///
/// Every mutating action here writes an audit entry, because an operator
/// reaching into another person's emergency request is exactly the kind of
/// action that needs to be attributable after the fact.
class AdminBackend {
  AdminBackend(this._db, {required this.actorId, required this.actorName});

  final fs.FirebaseFirestore _db;
  final String actorId;
  final String actorName;

  fs.CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('blood_requests');
  fs.CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  fs.CollectionReference<Map<String, dynamic>> get _audit =>
      _db.collection('admin_audit');
  fs.CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection('reports');

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
    await _db.runTransaction((tx) async {
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
    required this.bloodGroup,
    required this.isAdmin,
    required this.emailVerified,
    this.email,
    this.city,
    this.donorAvailability,
    this.totalDonations = 0,
    this.lastDonation,
  });

  final String id;
  final String name;
  final String phone;
  final BloodGroup bloodGroup;
  final bool isAdmin;
  final bool emailVerified;
  final String? email;
  final String? city;
  final DonorAvailability? donorAvailability;
  final int totalDonations;
  final DateTime? lastDonation;

  bool get isDonorOn =>
      donorAvailability != null && donorAvailability != DonorAvailability.off;

  bool get isInCooldown {
    final last = lastDonation;
    return last != null &&
        DateTime.now().isBefore(last.add(DonorProfile.cooldownDuration));
  }

  static AdminUser fromDoc(fs.QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    final donor = (m['donor'] as Map?)?.cast<String, dynamic>();
    return AdminUser(
      id: doc.id,
      name: m['name'] as String? ?? 'Unknown',
      phone: m['phone'] as String? ?? '',
      bloodGroup: BloodGroup.values.any((g) => g.label == m['bloodGroup'])
          ? BloodGroup.fromLabel(m['bloodGroup'] as String)
          : BloodGroup.oPos,
      isAdmin: m['isAdmin'] as bool? ?? false,
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
