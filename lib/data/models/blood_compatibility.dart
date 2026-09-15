import 'enums.dart';

/// Deterministic ABO/Rh donor compatibility (spec §23: "Do not implement
/// medical compatibility logic using an LLM. Use deterministic backend
/// rules."). Used to decide which open requests a donor's blood group is
/// shown for.
final Map<BloodGroup, List<BloodGroup>> _donorCanGiveTo = {
  BloodGroup.oNeg: BloodGroup.values, // universal donor
  BloodGroup.oPos: [
    BloodGroup.oPos,
    BloodGroup.aPos,
    BloodGroup.bPos,
    BloodGroup.abPos,
  ],
  BloodGroup.aNeg: [
    BloodGroup.aNeg,
    BloodGroup.aPos,
    BloodGroup.abNeg,
    BloodGroup.abPos,
  ],
  BloodGroup.aPos: [BloodGroup.aPos, BloodGroup.abPos],
  BloodGroup.bNeg: [
    BloodGroup.bNeg,
    BloodGroup.bPos,
    BloodGroup.abNeg,
    BloodGroup.abPos,
  ],
  BloodGroup.bPos: [BloodGroup.bPos, BloodGroup.abPos],
  BloodGroup.abNeg: [BloodGroup.abNeg, BloodGroup.abPos],
  BloodGroup.abPos: [
    BloodGroup.abPos,
  ], // universal recipient only, gives to itself
};

/// The recipient blood groups a donor with [donor]'s blood group can give to.
List<BloodGroup> recipientsFor(BloodGroup donor) =>
    _donorCanGiveTo[donor] ?? [donor];

/// The donor blood groups a patient with [recipient]'s blood group can
/// receive from — the inverse of [recipientsFor]. Used to suggest which
/// groups to accept when creating a request, so a requester who doesn't know
/// ABO/Rh compatibility off-hand isn't guessing.
List<BloodGroup> donorsCompatibleWith(BloodGroup recipient) => [
  for (final donor in BloodGroup.values)
    if (recipientsFor(donor).contains(recipient)) donor,
];
