/// Core domain enums for BloodLink. These mirror the backend contract and the
/// request state machine (spec §25). Never invent alternative states casually.
library;

/// The eight ABO/Rh blood groups.
enum BloodGroup {
  aPos('A+'),
  aNeg('A-'),
  bPos('B+'),
  bNeg('B-'),
  abPos('AB+'),
  abNeg('AB-'),
  oPos('O+'),
  oNeg('O-');

  const BloodGroup(this.label);

  /// Human + data label, e.g. "O-". Shown in monospace as an instrument value.
  final String label;

  static BloodGroup fromLabel(String value) =>
      BloodGroup.values.firstWhere((g) => g.label == value);
}

/// Urgency ladder. Doubles as the semantic color ladder:
/// routine -> info, urgent -> warning, critical -> danger.
enum Urgency {
  routine('Routine'),
  urgent('Urgent'),
  critical('Critical');

  const Urgency(this.label);
  final String label;
}

/// Request lifecycle (spec §25). Terminal states cannot transition further.
enum RequestStatus {
  created('Created'),
  searching('Searching'),
  donorAccepted('Donor accepted'),
  coordinating('Coordinating'),
  fulfilled('Fulfilled'),
  cancelled('Cancelled'),
  expired('Expired'),
  removedByAdmin('Removed by admin');

  const RequestStatus(this.label);
  final String label;

  bool get isTerminal =>
      this == fulfilled ||
      this == cancelled ||
      this == expired ||
      this == removedByAdmin;

  bool get isActive => !isTerminal;

  /// Ordered lifecycle used to render the tracking timeline.
  static const lifecycle = [
    RequestStatus.created,
    RequestStatus.searching,
    RequestStatus.donorAccepted,
    RequestStatus.coordinating,
    RequestStatus.fulfilled,
  ];
}

/// Donor Mode availability — a capability on the user's profile, not a
/// separate account (spec §15).
enum DonorAvailability {
  available('Available'),
  paused('Paused'),
  off('Off');

  const DonorAvailability(this.label);
  final String label;
}

/// State of a donor's response to an invitation.
enum InvitationStatus {
  pending('Pending'),
  accepted('Accepted'),
  declined('Declined'),
  expired('Expired'),
  withdrawn('No longer available');

  const InvitationStatus(this.label);
  final String label;
}
