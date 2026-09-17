import 'donor_eligibility.dart';
import 'enums.dart';

export 'blood_compatibility.dart';
export 'donor_eligibility.dart';
export 'enums.dart';

/// Immutable domain entities for BloodLink. These are plain value objects; the
/// repository layer is the source of truth and hands these to the UI. When the
/// real FastAPI backend lands, only the repositories change — screens keep
/// consuming these same models.

class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.bloodGroup,
    required this.phone,
    this.email,
    this.dateOfBirth,
    this.gender,
    this.country,
    this.state,
    this.city,
    this.lastDonation,
    this.isAdmin = false,
  });

  final String id;
  final String name;
  final BloodGroup bloodGroup;
  final String phone;
  final String? email;

  /// Collected at registration. Nullable only because accounts created before
  /// these fields existed don't have them — donor actions send those users to
  /// their profile to fill them in first.
  final DateTime? dateOfBirth;
  final Gender? gender;

  /// The user's saved home location. Deliberately separate from the device's
  /// live GPS position, which is only read at the moment it's needed.
  final String? country;
  final String? state;
  final String? city;
  final DateTime? lastDonation;
  final bool isAdmin;

  /// Whole years old on [on] (today by default), or null without a birth date.
  int? ageOn([DateTime? on]) =>
      dateOfBirth == null ? null : ageFrom(dateOfBirth!, on);

  /// "City, State" from whatever parts of the saved location are filled in.
  String? get placeLabel {
    final parts = [
      city,
      state,
    ].whereType<String>().where((p) => p.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// Donor Mode state — a capability attached to the user (spec §15).
class DonorProfile {
  const DonorProfile({
    required this.availability,
    required this.bloodGroup,
    this.notifyPush = true,
    this.notifyCritical = false,
    this.locationGranted = false,
    this.maxDistanceKm = 15,
    this.pausedUntil,
    this.totalDonations = 0,
    this.lastDonation,
  });

  final DonorAvailability availability;
  final BloodGroup bloodGroup;
  final bool notifyPush;
  final bool notifyCritical;
  final bool locationGranted;
  final double maxDistanceKm;
  final DateTime? pausedUntil;
  final int totalDonations;
  final DateTime? lastDonation;

  bool get isOn => availability != DonorAvailability.off;

  /// Standard medical gap between whole-blood donations. Enforced here so
  /// donors don't accidentally donate too soon, not just as a UI suggestion.
  static const cooldownDuration = Duration(days: 90);

  DateTime? get cooldownEndsAt => lastDonation?.add(cooldownDuration);

  bool get isInCooldown {
    final ends = cooldownEndsAt;
    return ends != null && DateTime.now().isBefore(ends);
  }

  Duration get cooldownRemaining {
    final ends = cooldownEndsAt;
    if (ends == null) return Duration.zero;
    final remaining = ends.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  DonorProfile copyWith({
    DonorAvailability? availability,
    BloodGroup? bloodGroup,
    bool? notifyPush,
    bool? notifyCritical,
    bool? locationGranted,
    double? maxDistanceKm,
    DateTime? pausedUntil,
    int? totalDonations,
    DateTime? lastDonation,
  }) {
    return DonorProfile(
      availability: availability ?? this.availability,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      notifyPush: notifyPush ?? this.notifyPush,
      notifyCritical: notifyCritical ?? this.notifyCritical,
      locationGranted: locationGranted ?? this.locationGranted,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      pausedUntil: pausedUntil ?? this.pausedUntil,
      totalDonations: totalDonations ?? this.totalDonations,
      lastDonation: lastDonation ?? this.lastDonation,
    );
  }
}

/// A destination (hospital / blood bank) — metadata on a request, never an
/// account or managed entity (spec §3).
class Destination {
  const Destination({
    required this.name,
    required this.address,
    this.wardOrContact,
    this.location,
  });

  final String name;
  final String address;
  final String? wardOrContact;
  final GeoPoint? location;
}

/// A single status transition, used to render the tracking timeline.
class StatusEvent {
  const StatusEvent({required this.status, required this.at, this.note});

  final RequestStatus status;
  final DateTime at;
  final String? note;
}

/// A donor who has committed to one unit of a request. A request needing
/// three units needs three of these — one donor can only give one unit.
class AcceptedDonor {
  const AcceptedDonor({
    required this.id,
    required this.name,
    required this.acceptedAt,
  });

  final String id;
  final String name;
  final DateTime acceptedAt;
}

/// The last position a donor shared while heading to the hospital.
class DonorPing {
  const DonorPing({required this.point, required this.at});
  final GeoPoint point;
  final DateTime at;
}

class BloodRequest {
  const BloodRequest({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    required this.bloodGroups,
    required this.units,
    required this.urgency,
    required this.status,
    required this.createdAt,
    required this.destination,
    required this.requestLocationLabel,
    this.patientName,
    this.patientBloodGroup,
    this.requestLocation,
    this.donorsContacted = 0,
    this.currentWave = 0,
    this.searchRadiusKm = 5,
    this.acceptedDonors = const [],
    this.expiresAt,
    this.timeline = const [],
    this.donorLiveLocations = const {},
  });

  final String id;
  final String requesterId;
  final String requesterName;

  /// Every blood group this request is open to — a patient can usually be
  /// helped by more than one compatible donor type, not just an exact match.
  final List<BloodGroup> bloodGroups;
  final int units;
  final Urgency urgency;
  final RequestStatus status;
  final DateTime createdAt;
  final Destination destination;
  final String requestLocationLabel;

  /// Who the blood is for. The requester is often a relative, so the
  /// patient's name and blood group are asked for separately rather than
  /// assumed from the requester's own profile. Null on requests created
  /// before these fields existed.
  final String? patientName;
  final BloodGroup? patientBloodGroup;
  final GeoPoint? requestLocation;

  // Matching progress (surfaced to the requester without leaking internals).
  final int donorsContacted;
  final int currentWave;
  final double searchRadiusKm;

  /// Everyone who has committed a unit so far, oldest first.
  final List<AcceptedDonor> acceptedDonors;
  final DateTime? expiresAt;
  final List<StatusEvent> timeline;

  /// Positions of donors who have chosen to share live location (spec §19),
  /// keyed by donor id — empty whenever nobody is sharing. Lets the
  /// requester's coordination map track donors heading their way.
  final Map<String, DonorPing> donorLiveLocations;

  List<String> get acceptedDonorIds => [for (final d in acceptedDonors) d.id];

  bool get hasAcceptedDonor => acceptedDonors.isNotEmpty;

  /// The first donor's name, for the many places that only have room for one.
  String? get acceptedDonorName =>
      acceptedDonors.isEmpty ? null : acceptedDonors.first.name;

  int get unitsPledged => acceptedDonors.length;

  int get unitsRemaining => units - unitsPledged < 0 ? 0 : units - unitsPledged;

  /// True once every unit has a donor. Until then the request keeps looking,
  /// however many donors have already said yes.
  bool get isFullyMatched => unitsRemaining == 0;

  /// Past its deadline with nobody committed. A request that already has a
  /// donor is never expired out from under them.
  bool hasExpiredBy([DateTime? now]) =>
      status.isActive &&
      !hasAcceptedDonor &&
      expiresAt != null &&
      expiresAt!.isBefore(now ?? DateTime.now());

  BloodRequest copyWith({
    List<BloodGroup>? bloodGroups,
    int? units,
    Urgency? urgency,
    RequestStatus? status,
    Destination? destination,
    String? requestLocationLabel,
    GeoPoint? requestLocation,
    int? donorsContacted,
    int? currentWave,
    double? searchRadiusKm,
    List<AcceptedDonor>? acceptedDonors,
    DateTime? expiresAt,
    List<StatusEvent>? timeline,
  }) {
    return BloodRequest(
      id: id,
      requesterId: requesterId,
      requesterName: requesterName,
      createdAt: createdAt,
      bloodGroups: bloodGroups ?? this.bloodGroups,
      units: units ?? this.units,
      urgency: urgency ?? this.urgency,
      status: status ?? this.status,
      destination: destination ?? this.destination,
      requestLocationLabel: requestLocationLabel ?? this.requestLocationLabel,
      patientName: patientName,
      patientBloodGroup: patientBloodGroup,
      requestLocation: requestLocation ?? this.requestLocation,
      donorsContacted: donorsContacted ?? this.donorsContacted,
      currentWave: currentWave ?? this.currentWave,
      searchRadiusKm: searchRadiusKm ?? this.searchRadiusKm,
      acceptedDonors: acceptedDonors ?? this.acceptedDonors,
      expiresAt: expiresAt ?? this.expiresAt,
      timeline: timeline ?? this.timeline,
      donorLiveLocations: donorLiveLocations,
    );
  }
}

/// A donor opportunity shown to a donor (the requester-facing request seen from
/// the donor side). Private requester data is withheld until acceptance.
class Invitation {
  const Invitation({
    required this.id,
    required this.requestId,
    required this.bloodGroups,
    required this.units,
    required this.urgency,
    required this.distanceKm,
    required this.status,
    required this.destinationName,
    required this.destinationArea,
    required this.createdAt,
    this.expiresAt,
    this.patientBloodGroup,
    this.requestStatus = RequestStatus.searching,
    this.unitsRemaining,
  });

  final String id;
  final String requestId;
  final List<BloodGroup> bloodGroups;
  final int units;
  final Urgency urgency;

  /// Null when either side's position is unknown — shown as unknown rather
  /// than as a misleading 0 km.
  final double? distanceKm;
  final InvitationStatus status;
  final String destinationName;
  final String destinationArea;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final BloodGroup? patientBloodGroup;

  /// Where the underlying request is now. An accepted invitation stays
  /// accepted forever, but only counts as an ongoing donation while the
  /// request itself is still active.
  final RequestStatus requestStatus;

  /// Units still without a donor. A request for three units keeps looking
  /// after the first donor accepts.
  final int? unitsRemaining;

  bool get isExpired =>
      status == InvitationStatus.expired ||
      (expiresAt != null && expiresAt!.isBefore(DateTime.now()));

  Invitation copyWith({InvitationStatus? status}) => Invitation(
    id: id,
    requestId: requestId,
    bloodGroups: bloodGroups,
    units: units,
    urgency: urgency,
    distanceKm: distanceKm,
    status: status ?? this.status,
    destinationName: destinationName,
    destinationArea: destinationArea,
    createdAt: createdAt,
    expiresAt: expiresAt,
    patientBloodGroup: patientBloodGroup,
    requestStatus: requestStatus,
    unitsRemaining: unitsRemaining,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.requestId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt,
    this.pending = false,
    this.failed = false,
  });

  final String id;
  final String requestId;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime sentAt;
  final bool pending;
  final bool failed;

  ChatMessage copyWith({bool? pending, bool? failed}) => ChatMessage(
    id: id,
    requestId: requestId,
    senderId: senderId,
    senderName: senderName,
    text: text,
    sentAt: sentAt,
    pending: pending ?? this.pending,
    failed: failed ?? this.failed,
  );
}
