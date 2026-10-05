import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/models.dart';
import '../data/providers.dart';
import 'admin_backend.dart';

/// Null until someone with the admin flag is signed in — every admin screen
/// hangs off this, so losing the flag closes the console rather than leaving
/// stale data on screen.
final adminBackendProvider = Provider<AdminBackend?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null || !user.isAdmin) return null;
  return AdminBackend(
    fs.FirebaseFirestore.instance,
    actorId: user.id,
    actorName: user.name,
    isAdmin: user.isAdmin,
  );
});

final adminRequestsProvider = StreamProvider<List<AdminRequest>>((ref) {
  final admin = ref.watch(adminBackendProvider);
  return admin?.requests ?? const Stream.empty();
});

final adminUsersProvider = StreamProvider<List<AdminUser>>((ref) {
  final admin = ref.watch(adminBackendProvider);
  return admin?.users ?? const Stream.empty();
});

/// The operators' switch: must new accounts be approved before acting.
final adminRequireApprovalProvider = StreamProvider<bool>((ref) {
  final admin = ref.watch(adminBackendProvider);
  return admin?.requireApproval ?? const Stream.empty();
});

/// System-wide donor cooldown configuration (ON/OFF and duration in days).
final adminCooldownConfigProvider = StreamProvider<CooldownConfig>((ref) async* {
  // 1. Immediately yield cached local preference to prevent resetting on page reload
  try {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('rakt_cooldown_enabled');
    final days = prefs.getInt('rakt_cooldown_days');
    if (enabled != null || days != null) {
      yield CooldownConfig(
        enabled: enabled ?? true,
        durationDays: days ?? 90,
      );
    }
  } catch (_) {}

  final admin = ref.watch(adminBackendProvider);
  final stream = admin != null
      ? admin.cooldownConfig
      : ref.watch(backendProvider).cooldownConfigStream;

  yield* stream.handleError((_) {});
});

final adminReportsProvider = StreamProvider<List<AdminReport>>((ref) {
  final admin = ref.watch(adminBackendProvider);
  return admin?.reports ?? const Stream.empty();
});

final adminAuditProvider = StreamProvider<List<AuditEntry>>((ref) {
  final admin = ref.watch(adminBackendProvider);
  return admin?.auditLog ?? const Stream.empty();
});

final adminHospitalsProvider = StreamProvider<List<AdminHospital>>((ref) {
  final admin = ref.watch(adminBackendProvider);
  return admin?.hospitals ?? const Stream.empty();
});

final adminNotificationsProvider = StreamProvider<List<AdminNotificationEntry>>(
  (ref) {
    final admin = ref.watch(adminBackendProvider);
    return admin?.adminNotifications ?? const Stream.empty();
  },
);

/// The numbers an operator is actually scanning for. Deliberately about work
/// state — what's stuck, what's unmatched — rather than vanity totals.
class AdminStats {
  const AdminStats({
    required this.total,
    required this.open,
    required this.unmatched,
    required this.stale,
    required this.critical,
    required this.coordinating,
    required this.fulfilled,
  });

  final int total;
  final int open;
  final int unmatched;
  final int stale;
  final int critical;
  final int coordinating;
  final int fulfilled;

  static AdminStats from(List<AdminRequest> requests) => AdminStats(
    total: requests.length,
    open: requests.where((r) => r.isOpen).length,
    unmatched: requests.where((r) => r.isUnmatched).length,
    stale: requests.where((r) => r.isStale).length,
    critical: requests
        .where((r) => r.isOpen && r.urgency == Urgency.critical)
        .length,
    coordinating: requests
        .where((r) => r.status == RequestStatus.coordinating)
        .length,
    fulfilled: requests
        .where((r) => r.status == RequestStatus.fulfilled)
        .length,
  );
}

final adminStatsProvider = Provider<AdminStats>((ref) {
  final requests = ref.watch(adminRequestsProvider).valueOrNull ?? const [];
  return AdminStats.from(requests);
});

/// Requests that need a human to look at them, most urgent first: stale ones
/// before merely unmatched ones, critical before routine, oldest first inside
/// each band.
final adminAttentionQueueProvider = Provider<List<AdminRequest>>((ref) {
  final requests = ref.watch(adminRequestsProvider).valueOrNull ?? const [];
  final needing = requests.where((r) => r.isStale || r.isUnmatched).toList();
  needing.sort((a, b) {
    if (a.isStale != b.isStale) return a.isStale ? -1 : 1;
    final byUrgency = b.urgency.index.compareTo(a.urgency.index);
    if (byUrgency != 0) return byUrgency;
    return a.createdAt.compareTo(b.createdAt);
  });
  return needing;
});
