import 'enums.dart';

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
    this.city,
    this.lastDonation,
    this.isAdmin = false,
  });

  final String id;
  final String name;
  final BloodGroup bloodGroup;
  final String phone;
  final String? email;
  final String? city;
  final DateTime? lastDonation;
  final bool isAdmin;

  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
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
    this.notifyCritical = true,
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
  const StatusEvent({
    required this.status,
    required this.at,
    this.note,
  });

  final RequestStatus status;
  final DateTime at;
  final String? note;
}

class BloodRequest {
  const BloodRequest({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    required this.bloodGroup,
    required this.units,
    required this.urgency,
    required this.status,
    required this.createdAt,
    required this.destination,
    required this.requestLocationLabel,
    this.requestLocation,
    this.donorsContacted = 0,
    this.currentWave = 0,
    this.searchRadiusKm = 5,
    this.acceptedDonorName,
    this.acceptedDonorId,
    this.expiresAt,
    this.timeline = const [],
  });

  final String id;
  final String requesterId;
  final String requesterName;
  final BloodGroup bloodGroup;
  final int units;
  final Urgency urgency;
  final RequestStatus status;
  final DateTime createdAt;
  final Destination destination;
  final String requestLocationLabel;
  final GeoPoint? requestLocation;

  // Matching progress (surfaced to the requester without leaking internals).
  final int donorsContacted;
  final int currentWave;
  final double searchRadiusKm;

  final String? acceptedDonorName;
  final String? acceptedDonorId;
  final DateTime? expiresAt;
  final List<StatusEvent> timeline;

  bool get hasAcceptedDonor => acceptedDonorId != null;

  BloodRequest copyWith({
    BloodGroup? bloodGroup,
    int? units,
    Urgency? urgency,
    RequestStatus? status,
    Destination? destination,
    String? requestLocationLabel,
    GeoPoint? requestLocation,
    int? donorsContacted,
    int? currentWave,
    double? searchRadiusKm,
    String? acceptedDonorName,
    String? acceptedDonorId,
    DateTime? expiresAt,
    List<StatusEvent>? timeline,
  }) {
    return BloodRequest(
      id: id,
      requesterId: requesterId,
      requesterName: requesterName,
      createdAt: createdAt,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      units: units ?? this.units,
      urgency: urgency ?? this.urgency,
      status: status ?? this.status,
      destination: destination ?? this.destination,
      requestLocationLabel: requestLocationLabel ?? this.requestLocationLabel,
      requestLocation: requestLocation ?? this.requestLocation,
      donorsContacted: donorsContacted ?? this.donorsContacted,
      currentWave: currentWave ?? this.currentWave,
      searchRadiusKm: searchRadiusKm ?? this.searchRadiusKm,
      acceptedDonorName: acceptedDonorName ?? this.acceptedDonorName,
      acceptedDonorId: acceptedDonorId ?? this.acceptedDonorId,
      expiresAt: expiresAt ?? this.expiresAt,
      timeline: timeline ?? this.timeline,
    );
  }
}

/// A donor opportunity shown to a donor (the requester-facing request seen from
/// the donor side). Private requester data is withheld until acceptance.
class Invitation {
  const Invitation({
    required this.id,
    required this.requestId,
    required this.bloodGroup,
    required this.units,
    required this.urgency,
    required this.distanceKm,
    required this.status,
    required this.destinationName,
    required this.destinationArea,
    required this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String requestId;
  final BloodGroup bloodGroup;
  final int units;
  final Urgency urgency;
  final double distanceKm;
  final InvitationStatus status;
  final String destinationName;
  final String destinationArea;
  final DateTime createdAt;
  final DateTime? expiresAt;

  Invitation copyWith({InvitationStatus? status}) => Invitation(
        id: id,
        requestId: requestId,
        bloodGroup: bloodGroup,
        units: units,
        urgency: urgency,
        distanceKm: distanceKm,
        status: status ?? this.status,
        destinationName: destinationName,
        destinationArea: destinationArea,
        createdAt: createdAt,
        expiresAt: expiresAt,
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
