import 'enums.dart';

/// Who may donate, decided by fixed rules rather than guesswork. The age band
/// and the questions below follow India's National Blood Transfusion Council
/// donor-selection criteria. They are a pre-check so nobody travels to a
/// hospital only to be turned away. The blood bank still does its own
/// screening before any donation.
class DonorEligibility {
  DonorEligibility._();

  static const minAge = 18;
  static const maxAge = 65;

  static bool ageAllowed(int age) => age >= minAge && age <= maxAge;
}

/// Whole years between [dateOfBirth] and [on] (today by default).
int ageFrom(DateTime dateOfBirth, [DateTime? on]) {
  final now = on ?? DateTime.now();
  var years = now.year - dateOfBirth.year;
  if (now.month < dateOfBirth.month ||
      (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
    years -= 1;
  }
  return years;
}

/// One yes/no question asked right before a donor accepts a request. Any
/// "yes" means they shouldn't donate this time. Answers are never stored:
/// they're health data, and the only thing the app needs is the outcome.
enum HealthQuestion {
  recentDonation(
    'Have you donated blood in the last 3 months?',
    'Wait at least 3 months between donations so your body can recover.',
  ),
  unwell(
    'Do you have a fever, cold or infection, or are you taking antibiotics?',
    'Donate once you have fully recovered and finished any antibiotics.',
  ),
  lowWeight(
    'Do you weigh less than 45 kg?',
    'Donors need to weigh at least 45 kg.',
  ),
  seriousInfection(
    'Have you ever tested positive for HIV, hepatitis B or hepatitis C?',
    'People who have had HIV, hepatitis B or hepatitis C cannot donate blood.',
  ),
  insulin(
    'Do you have diabetes (sugar) that is treated with insulin?',
    'Diabetes treated with insulin rules out donation. Diabetes controlled '
        'with tablets or diet alone usually does not.',
  ),
  rabies(
    'Have you had a rabies injection after an animal bite in the last 12 months?',
    'Wait 12 months after a rabies injection given for an animal bite.',
  ),
  tattooOrSurgery(
    'Have you had a tattoo, piercing or surgery in the last 12 months?',
    'Wait 12 months after a tattoo, piercing or surgery.',
  ),
  pregnancy(
    'Are you pregnant or breastfeeding, or have you given birth in the last 12 months?',
    'Wait until 12 months after delivery, and until you have stopped '
        'breastfeeding.',
    askMale: false,
  );

  const HealthQuestion(this.question, this.deferral, {this.askMale = true});

  final String question;

  /// What to tell someone who answered "yes".
  final String deferral;
  final bool askMale;

  /// The questions that apply to a donor of [gender].
  static List<HealthQuestion> forGender(Gender? gender) => [
    for (final q in values)
      if (q.askMale || gender != Gender.male) q,
  ];
}
