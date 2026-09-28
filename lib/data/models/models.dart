import 'donor_eligibility.dart';
import 'enums.dart';

export 'blood_compatibility.dart';
export 'donor_eligibility.dart';
export 'enums.dart';

/// Immutable domain entities for Rakt Pravah. These are plain value objects; the
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

  /// Standard medical gap between whole-blood donations: 3 months (90 days).
  /// Enforced here so donors don't accidentally donate too soon.
  static const cooldownDuration = Duration(days: 90);

  /// The next eligible donation date (3 months / 90 days after last donation).
  DateTime? get nextEligibleDonationDate =>
      lastDonation?.add(cooldownDuration);

  DateTime? get cooldownEndsAt => nextEligibleDonationDate;

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
    bool clearLastDonation = false,
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
      lastDonation: clearLastDonation ? null : (lastDonation ?? this.lastDonation),
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

/// State of a donor's interaction with a blood request notification.
enum DonorRequestInteractionStatus {
  notified('Notified'),
  viewed('Viewed'),
  accepted('Accepted'),
  declined('Declined'),
  expired('Expired');

  const DonorRequestInteractionStatus(this.label);
  final String label;
}

/// An eligible nearby donor candidate matched to a blood request.
class MatchedDonor {
  const MatchedDonor({
    required this.id,
    required this.name,
    required this.bloodGroup,
    required this.distanceKm,
    required this.status,
    this.phone,
    this.location,
    this.notifiedAt,
    this.isEligible = true,
    this.isDonorModeOn = true,
  });

  final String id;
  final String name;
  final BloodGroup bloodGroup;
  final double distanceKm;
  final DonorRequestInteractionStatus status;
  final String? phone;
  final GeoPoint? location;
  final DateTime? notifiedAt;
  final bool isEligible;
  final bool isDonorModeOn;

  /// Approximate travel time in minutes based on distance (~30 km/h urban speed).
  int get estimatedTravelMinutes =>
      (distanceKm / 0.5).round().clamp(2, 180);
}

/// A donor who has committed to one unit of a request. A request needing
/// three units needs three of these — one donor can only give one unit.
class AcceptedDonor {
  const AcceptedDonor({
    required this.id,
    required this.name,
    required this.acceptedAt,
    this.bloodGroup,
    this.bloodType = 'Blood',
    this.photoUrl,
    this.phone,
    this.distanceKm,
    this.location,
    this.status = 'Accepted',
    this.transitStatus = DonorTransitStatus.accepted,
    this.isVerified = true,
    this.isDonorModeOn = true,
  });

  final String id;
  final String name;
  final DateTime acceptedAt;
  final BloodGroup? bloodGroup;
  final String bloodType;
  final String? photoUrl;
  final String? phone;
  final double? distanceKm;
  final GeoPoint? location;
  final String status;
  final DonorTransitStatus transitStatus;
  final bool isVerified;
  final bool isDonorModeOn;

  /// Approximate travel time in minutes based on distance (~30 km/h urban speed).
  int? get estimatedTravelMinutes =>
      distanceKm == null ? null : (distanceKm! / 0.5).round().clamp(2, 180);

  AcceptedDonor copyWith({
    String? id,
    String? name,
    DateTime? acceptedAt,
    BloodGroup? bloodGroup,
    String? bloodType,
    String? photoUrl,
    String? phone,
    double? distanceKm,
    GeoPoint? location,
    String? status,
    DonorTransitStatus? transitStatus,
    bool? isVerified,
    bool? isDonorModeOn,
  }) {
    return AcceptedDonor(
      id: id ?? this.id,
      name: name ?? this.name,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      bloodType: bloodType ?? this.bloodType,
      photoUrl: photoUrl ?? this.photoUrl,
      phone: phone ?? this.phone,
      distanceKm: distanceKm ?? this.distanceKm,
      location: location ?? this.location,
      status: status ?? this.status,
      transitStatus: transitStatus ?? this.transitStatus,
      isVerified: isVerified ?? this.isVerified,
      isDonorModeOn: isDonorModeOn ?? this.isDonorModeOn,
    );
  }
}

enum DonorTransitStatus {
  accepted,
  onTheWay,
  nearHospital,
  reached,
  donationCompleted;

  String get label => switch (this) {
    accepted => 'Accepted',
    onTheWay => 'On the Way',
    nearHospital => 'Near Hospital',
    reached => 'Reached',
    donationCompleted => 'Donation Completed',
  };

  int get stepIndex => switch (this) {
    accepted => 0,
    onTheWay => 1,
    nearHospital => 2,
    reached => 3,
    donationCompleted => 4,
  };
}

/// The last position a donor shared while heading to the hospital.
class DonorPing {
  const DonorPing({
    required this.point,
    required this.at,
    this.transitStatus = DonorTransitStatus.onTheWay,
    this.headingDegrees,
  });

  final GeoPoint point;
  final DateTime at;
  final DonorTransitStatus transitStatus;
  final double? headingDegrees;
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
    this.bloodType = 'Blood',
    this.phone,
    this.requiredDate,
    this.notes,
    this.donorsContacted = 0,
    this.currentWave = 0,
    this.searchRadiusKm = 25,
    this.acceptedDonors = const [],
    this.declinedByDonorIds = const [],
    this.viewedByDonorIds = const [],
    this.expiresAt,
    this.timeline = const [],
    this.donorLiveLocations = const {},
    this.requesterLiveLocation,
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
  final String bloodType;
  final String? phone;
  final DateTime? requiredDate;
  final String? notes;

  // Matching progress (surfaced to the requester without leaking internals).
  final int donorsContacted;
  final int currentWave;
  final double searchRadiusKm;

  /// Everyone who has committed a unit so far, sorted by distance.
  final List<AcceptedDonor> acceptedDonors;
  final List<String> declinedByDonorIds;
  final List<String> viewedByDonorIds;
  final DateTime? expiresAt;
  final List<StatusEvent> timeline;

  /// Positions of donors who have chosen to share live location (spec §19),
  /// keyed by donor id — empty whenever nobody is sharing. Lets the
  /// requester's coordination map track donors heading their way.
  final Map<String, DonorPing> donorLiveLocations;

  /// Optional live position of the requester/hospital coordinator for two-way tracking.
  final DonorPing? requesterLiveLocation;

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
    String? patientName,
    BloodGroup? patientBloodGroup,
    GeoPoint? requestLocation,
    String? bloodType,
    String? phone,
    DateTime? requiredDate,
    String? notes,
    int? donorsContacted,
    int? currentWave,
    double? searchRadiusKm,
    List<AcceptedDonor>? acceptedDonors,
    List<String>? declinedByDonorIds,
    List<String>? viewedByDonorIds,
    DateTime? expiresAt,
    List<StatusEvent>? timeline,
    Map<String, DonorPing>? donorLiveLocations,
    DonorPing? requesterLiveLocation,
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
      patientName: patientName ?? this.patientName,
      patientBloodGroup: patientBloodGroup ?? this.patientBloodGroup,
      requestLocation: requestLocation ?? this.requestLocation,
      bloodType: bloodType ?? this.bloodType,
      phone: phone ?? this.phone,
      requiredDate: requiredDate ?? this.requiredDate,
      notes: notes ?? this.notes,
      donorsContacted: donorsContacted ?? this.donorsContacted,
      currentWave: currentWave ?? this.currentWave,
      searchRadiusKm: searchRadiusKm ?? this.searchRadiusKm,
      acceptedDonors: acceptedDonors ?? this.acceptedDonors,
      declinedByDonorIds: declinedByDonorIds ?? this.declinedByDonorIds,
      viewedByDonorIds: viewedByDonorIds ?? this.viewedByDonorIds,
      expiresAt: expiresAt ?? this.expiresAt,
      timeline: timeline ?? this.timeline,
      donorLiveLocations: donorLiveLocations ?? this.donorLiveLocations,
      requesterLiveLocation:
          requesterLiveLocation ?? this.requesterLiveLocation,
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
