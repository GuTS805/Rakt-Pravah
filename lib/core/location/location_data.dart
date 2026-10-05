/// Comprehensive location models and datasets for Rakt Pravah.
/// Supports global countries, states/provinces, and cities/districts with
/// accurate geographic coordinates for distance calculation, donor matching,
/// request routing, and live tracking.
library;

class CityLocation {
  const CityLocation({
    required this.name,
    required this.stateCode,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
    this.aliases = const [],
    this.isAdministrativeCenter = true,
  });

  final String name;
  final String stateCode;
  final String countryCode;
  final double latitude;
  final double longitude;
  final List<String> aliases;
  final bool isAdministrativeCenter;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q)) return true;
    for (final a in aliases) {
      if (a.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

class StateLocation {
  const StateLocation({
    required this.name,
    required this.code,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
    required this.cities,
    this.aliases = const [],
  });

  final String name;
  final String code;
  final String countryCode;
  final double latitude;
  final double longitude;
  final List<CityLocation> cities;
  final List<String> aliases;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q)) return true;
    if (code.toLowerCase() == q) return true;
    for (final a in aliases) {
      if (a.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

class CountryLocation {
  const CountryLocation({
    required this.name,
    required this.code,
    required this.dialCode,
    this.states = const [],
    this.flag = '',
  });

  final String name;
  final String code; // ISO 3166-1 alpha-2 (e.g. IN, US, GB)
  final String dialCode; // e.g. +91, +1, +44
  final List<StateLocation> states;
  final String flag;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q)) return true;
    if (code.toLowerCase() == q) return true;
    if (dialCode.toLowerCase().contains(q)) return true;
    return false;
  }
}

class SelectedLocation {
  const SelectedLocation({
    required this.country,
    required this.countryCode,
    required this.state,
    required this.stateCode,
    required this.city,
    this.latitude,
    this.longitude,
  });

  final String country;
  final String countryCode;
  final String state;
  final String stateCode;
  final String city;
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates => latitude != null && longitude != null;

  Map<String, dynamic> toMap() => {
        'country': country,
        'countryCode': countryCode,
        'state': state,
        'stateCode': stateCode,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        if (hasCoordinates) 'location': {'lat': latitude, 'lng': longitude},
      };

  @override
  String toString() => '$city, $state, $country ($latitude, $longitude)';
}

/// Centralized repository of location data used across User Profile,
/// Blood Request, Hospital Location, Donor Matching, and Live Map.
class LocationDataService {
  LocationDataService._();

  static List<CountryLocation> get countries => _allCountries;

  static CountryLocation? findCountry(String? countryNameOrCode) {
    if (countryNameOrCode == null || countryNameOrCode.trim().isEmpty) return null;
    final clean = countryNameOrCode.trim().toLowerCase();
    for (final c in _allCountries) {
      if (c.name.toLowerCase() == clean ||
          c.code.toLowerCase() == clean ||
          c.dialCode.toLowerCase() == clean) {
        return c;
      }
    }
    // Partial search fallback
    for (final c in _allCountries) {
      if (c.name.toLowerCase().contains(clean)) return c;
    }
    return null;
  }

  static List<StateLocation> getStates(String? countryNameOrCode) {
    final country = findCountry(countryNameOrCode);
    return country?.states ?? const [];
  }

  static StateLocation? findState(String? countryNameOrCode, String? stateNameOrCode) {
    if (stateNameOrCode == null || stateNameOrCode.trim().isEmpty) return null;
    final states = getStates(countryNameOrCode);
    final clean = stateNameOrCode.trim().toLowerCase();
    for (final s in states) {
      if (s.name.toLowerCase() == clean || s.code.toLowerCase() == clean) {
        return s;
      }
      for (final a in s.aliases) {
        if (a.toLowerCase() == clean) return s;
      }
    }
    for (final s in states) {
      if (s.name.toLowerCase().contains(clean)) return s;
    }
    return null;
  }

  static List<CityLocation> getCities(String? countryNameOrCode, String? stateNameOrCode) {
    final state = findState(countryNameOrCode, stateNameOrCode);
    return state?.cities ?? const [];
  }

  static CityLocation? findCity(
    String? countryNameOrCode,
    String? stateNameOrCode,
    String? cityName,
  ) {
    if (cityName == null || cityName.trim().isEmpty) return null;
    final cities = getCities(countryNameOrCode, stateNameOrCode);
    final clean = cityName.trim().toLowerCase();
    for (final c in cities) {
      if (c.name.toLowerCase() == clean) return c;
      for (final a in c.aliases) {
        if (a.toLowerCase() == clean) return c;
      }
    }
    for (final c in cities) {
      if (c.name.toLowerCase().contains(clean)) return c;
    }
    return null;
  }

  /// Resolves the full metadata for a given Country, State, and City combination.
  /// If an exact city is not found in the state, it attempts to find the nearest
  /// administrative district center within that state to provide valid coordinates.
  static SelectedLocation resolve({
    required String country,
    String? state,
    String? city,
  }) {
    final countryObj = findCountry(country) ??
        CountryLocation(
          name: country.trim(),
          code: country.trim().length == 2 ? country.trim().toUpperCase() : 'IN',
          dialCode: '+91',
          states: const [],
        );

    final stateObj = findState(countryObj.code, state);
    final stateName = stateObj?.name ?? (state ?? '').trim();
    final stateCode = stateObj?.code ??
        (stateName.length <= 3 ? stateName.toUpperCase() : '');

    final cityName = (city ?? '').trim();
    final cityObj = findCity(countryObj.code, stateName, cityName);

    double? lat = cityObj?.latitude;
    double? lng = cityObj?.longitude;

    // Fallback: If city not explicitly listed, use the state's center coordinate
    // or the state's primary administrative center.
    if ((lat == null || lng == null) && stateObj != null) {
      if (stateObj.cities.isNotEmpty) {
        final adminCenter = stateObj.cities.firstWhere(
          (c) => c.isAdministrativeCenter,
          orElse: () => stateObj.cities.first,
        );
        lat = adminCenter.latitude;
        lng = adminCenter.longitude;
      } else {
        lat = stateObj.latitude;
        lng = stateObj.longitude;
      }
    }

    return SelectedLocation(
      country: countryObj.name,
      countryCode: countryObj.code,
      state: stateName,
      stateCode: stateCode,
      city: cityName,
      latitude: lat,
      longitude: lng,
    );
  }

  /// Finds the nearest administrative center within a given state for any custom location.
  static CityLocation? findNearestAdministrativeLocation({
    required String country,
    required String state,
    required String customQuery,
  }) {
    final cities = getCities(country, state);
    if (cities.isEmpty) return null;
    final q = customQuery.trim().toLowerCase();
    for (final c in cities) {
      if (c.matches(q)) return c;
    }
    return cities.firstWhere((c) => c.isAdministrativeCenter, orElse: () => cities.first);
  }

  // --- Complete Datasets ---

  static final List<CountryLocation> _allCountries = [
    _india,
    _unitedStates,
    _unitedKingdom,
    _canada,
    _australia,
    _unitedArabEmirates,
    _saudiArabia,
    _germany,
    _france,
    _singapore,
    _nepal,
    _bangladesh,
    _pakistan,
    _japan,
    _brazil,
    _southAfrica,
    _newZealand,
    _italy,
    _spain,
    _netherlands,
    _switzerland,
    _sweden,
    _indonesia,
    _malaysia,
    _philippines,
    _thailand,
    _vietnam,
    _southKorea,
    _sriLanka,
    _mexico,
    _argentina,
    _chile,
    _egypt,
    _nigeria,
    _kenya,
    ..._globalCountries,
  ];

  // -------------------------------------------------------------
  // INDIA: All 36 States & UTs with comprehensive districts & coordinates
  // -------------------------------------------------------------
  static final CountryLocation _india = CountryLocation(
    name: 'India',
    code: 'IN',
    dialCode: '+91',
    flag: '🇮🇳',
    states: [
      StateLocation(
        name: 'Uttar Pradesh',
        code: 'UP',
        countryCode: 'IN',
        latitude: 26.8467,
        longitude: 80.9462,
        aliases: const ['UP', 'U.P.'],
        cities: const [
          CityLocation(name: 'Agra', stateCode: 'UP', countryCode: 'IN', latitude: 27.1767, longitude: 78.0081),
          CityLocation(name: 'Aligarh', stateCode: 'UP', countryCode: 'IN', latitude: 27.8974, longitude: 78.0880),
          CityLocation(name: 'Ambedkar Nagar', stateCode: 'UP', countryCode: 'IN', latitude: 26.4499, longitude: 82.6837),
          CityLocation(name: 'Amethi', stateCode: 'UP', countryCode: 'IN', latitude: 26.1557, longitude: 81.8152),
          CityLocation(name: 'Amroha', stateCode: 'UP', countryCode: 'IN', latitude: 28.9044, longitude: 78.4674),
          CityLocation(name: 'Auraiya', stateCode: 'UP', countryCode: 'IN', latitude: 26.4676, longitude: 79.5160),
          CityLocation(name: 'Ayodhya', stateCode: 'UP', countryCode: 'IN', latitude: 26.7922, longitude: 82.1998, aliases: ['Faizabad']),
          CityLocation(name: 'Azamgarh', stateCode: 'UP', countryCode: 'IN', latitude: 26.0683, longitude: 83.1837),
          CityLocation(name: 'Baghpat', stateCode: 'UP', countryCode: 'IN', latitude: 28.9442, longitude: 77.2227),
          CityLocation(name: 'Bahraich', stateCode: 'UP', countryCode: 'IN', latitude: 27.5752, longitude: 81.5947),
          CityLocation(name: 'Ballia', stateCode: 'UP', countryCode: 'IN', latitude: 25.7600, longitude: 84.1485),
          CityLocation(name: 'Balrampur', stateCode: 'UP', countryCode: 'IN', latitude: 27.4285, longitude: 82.1793),
          CityLocation(name: 'Banda', stateCode: 'UP', countryCode: 'IN', latitude: 25.4754, longitude: 80.3347),
          CityLocation(name: 'Barabanki', stateCode: 'UP', countryCode: 'IN', latitude: 26.9268, longitude: 81.1834),
          CityLocation(name: 'Bareilly', stateCode: 'UP', countryCode: 'IN', latitude: 28.3670, longitude: 79.4304),
          CityLocation(name: 'Basti', stateCode: 'UP', countryCode: 'IN', latitude: 26.7989, longitude: 82.7633),
          CityLocation(name: 'Bhadohi', stateCode: 'UP', countryCode: 'IN', latitude: 25.4190, longitude: 82.5700, aliases: ['Sant Ravidas Nagar']),
          CityLocation(name: 'Bijnor', stateCode: 'UP', countryCode: 'IN', latitude: 29.3732, longitude: 78.1352),
          CityLocation(name: 'Budaun', stateCode: 'UP', countryCode: 'IN', latitude: 28.0384, longitude: 79.1245),
          CityLocation(name: 'Bulandshahr', stateCode: 'UP', countryCode: 'IN', latitude: 28.4069, longitude: 77.8498),
          CityLocation(name: 'Chandauli', stateCode: 'UP', countryCode: 'IN', latitude: 25.2612, longitude: 83.2662),
          CityLocation(name: 'Chitrakoot', stateCode: 'UP', countryCode: 'IN', latitude: 25.2036, longitude: 80.8986),
          CityLocation(name: 'Deoria', stateCode: 'UP', countryCode: 'IN', latitude: 26.5023, longitude: 83.7791),
          CityLocation(name: 'Etah', stateCode: 'UP', countryCode: 'IN', latitude: 27.5574, longitude: 78.6653),
          CityLocation(name: 'Etawah', stateCode: 'UP', countryCode: 'IN', latitude: 26.7855, longitude: 79.0154),
          CityLocation(name: 'Farrukhabad', stateCode: 'UP', countryCode: 'IN', latitude: 27.3826, longitude: 79.5829),
          CityLocation(name: 'Fatehpur', stateCode: 'UP', countryCode: 'IN', latitude: 25.9286, longitude: 80.8130),
          CityLocation(name: 'Firozabad', stateCode: 'UP', countryCode: 'IN', latitude: 27.1592, longitude: 78.3957),
          CityLocation(name: 'Gautam Buddha Nagar', stateCode: 'UP', countryCode: 'IN', latitude: 28.5355, longitude: 77.3910, aliases: ['GB Nagar']),
          CityLocation(name: 'Ghaziabad', stateCode: 'UP', countryCode: 'IN', latitude: 28.6692, longitude: 77.4538),
          CityLocation(name: 'Ghazipur', stateCode: 'UP', countryCode: 'IN', latitude: 25.5840, longitude: 83.5770),
          CityLocation(name: 'Gonda', stateCode: 'UP', countryCode: 'IN', latitude: 27.1337, longitude: 81.9619),
          CityLocation(name: 'Gorakhpur', stateCode: 'UP', countryCode: 'IN', latitude: 26.7606, longitude: 83.3732),
          CityLocation(name: 'Greater Noida', stateCode: 'UP', countryCode: 'IN', latitude: 28.4744, longitude: 77.5040),
          CityLocation(name: 'Hamirpur', stateCode: 'UP', countryCode: 'IN', latitude: 25.9547, longitude: 80.1519),
          CityLocation(name: 'Hapur', stateCode: 'UP', countryCode: 'IN', latitude: 28.7306, longitude: 77.7759),
          CityLocation(name: 'Hardoi', stateCode: 'UP', countryCode: 'IN', latitude: 27.3958, longitude: 80.1313),
          CityLocation(name: 'Hathras', stateCode: 'UP', countryCode: 'IN', latitude: 27.5968, longitude: 78.0519),
          CityLocation(name: 'Jalaun', stateCode: 'UP', countryCode: 'IN', latitude: 26.1458, longitude: 79.3522),
          CityLocation(name: 'Jaunpur', stateCode: 'UP', countryCode: 'IN', latitude: 25.7464, longitude: 82.6837),
          CityLocation(name: 'Jhansi', stateCode: 'UP', countryCode: 'IN', latitude: 25.4484, longitude: 78.5685),
          CityLocation(name: 'Kannauj', stateCode: 'UP', countryCode: 'IN', latitude: 27.0543, longitude: 79.9149),
          CityLocation(name: 'Kanpur', stateCode: 'UP', countryCode: 'IN', latitude: 26.4499, longitude: 80.3319, aliases: ['Kanpur Nagar']),
          CityLocation(name: 'Kanpur Nagar', stateCode: 'UP', countryCode: 'IN', latitude: 26.4499, longitude: 80.3319, aliases: ['Kanpur']),
          CityLocation(name: 'Kanpur Dehat', stateCode: 'UP', countryCode: 'IN', latitude: 26.4697, longitude: 80.0076),
          CityLocation(name: 'Kasganj', stateCode: 'UP', countryCode: 'IN', latitude: 27.8083, longitude: 78.6479),
          CityLocation(name: 'Kaushambi', stateCode: 'UP', countryCode: 'IN', latitude: 25.5312, longitude: 81.4285),
          CityLocation(name: 'Kheri', stateCode: 'UP', countryCode: 'IN', latitude: 27.9150, longitude: 80.7770, aliases: ['Lakhimpur Kheri']),
          CityLocation(name: 'Lakhimpur Kheri', stateCode: 'UP', countryCode: 'IN', latitude: 27.9150, longitude: 80.7770, aliases: ['Kheri']),
          CityLocation(name: 'Kushinagar', stateCode: 'UP', countryCode: 'IN', latitude: 26.7404, longitude: 83.8890),
          CityLocation(name: 'Lalitpur', stateCode: 'UP', countryCode: 'IN', latitude: 24.6904, longitude: 78.4116),
          CityLocation(name: 'Lucknow', stateCode: 'UP', countryCode: 'IN', latitude: 26.8467, longitude: 80.9462),
          CityLocation(name: 'Maharajganj', stateCode: 'UP', countryCode: 'IN', latitude: 27.1444, longitude: 83.5614),
          CityLocation(name: 'Mahoba', stateCode: 'UP', countryCode: 'IN', latitude: 25.2917, longitude: 79.8722),
          CityLocation(name: 'Mainpuri', stateCode: 'UP', countryCode: 'IN', latitude: 27.2289, longitude: 79.0277),
          CityLocation(name: 'Mathura', stateCode: 'UP', countryCode: 'IN', latitude: 27.4924, longitude: 77.6737),
          CityLocation(name: 'Mau', stateCode: 'UP', countryCode: 'IN', latitude: 25.9417, longitude: 83.5611),
          CityLocation(name: 'Meerut', stateCode: 'UP', countryCode: 'IN', latitude: 28.9845, longitude: 77.7064),
          CityLocation(name: 'Mirzapur', stateCode: 'UP', countryCode: 'IN', latitude: 25.1337, longitude: 82.5644),
          CityLocation(name: 'Moradabad', stateCode: 'UP', countryCode: 'IN', latitude: 28.8386, longitude: 78.7733),
          CityLocation(name: 'Muzaffarnagar', stateCode: 'UP', countryCode: 'IN', latitude: 29.4727, longitude: 77.7085),
          CityLocation(name: 'Noida', stateCode: 'UP', countryCode: 'IN', latitude: 28.5355, longitude: 77.3910),
          CityLocation(name: 'Pilibhit', stateCode: 'UP', countryCode: 'IN', latitude: 28.6312, longitude: 79.8044),
          CityLocation(name: 'Pratapgarh', stateCode: 'UP', countryCode: 'IN', latitude: 25.9254, longitude: 81.9972),
          CityLocation(name: 'Prayagraj', stateCode: 'UP', countryCode: 'IN', latitude: 25.4358, longitude: 81.8463, aliases: ['Allahabad']),
          CityLocation(name: 'Raebareli', stateCode: 'UP', countryCode: 'IN', latitude: 26.2236, longitude: 81.2409),
          CityLocation(name: 'Rampur', stateCode: 'UP', countryCode: 'IN', latitude: 28.8154, longitude: 79.0257),
          CityLocation(name: 'Saharanpur', stateCode: 'UP', countryCode: 'IN', latitude: 29.9679, longitude: 77.5460),
          CityLocation(name: 'Sambhal', stateCode: 'UP', countryCode: 'IN', latitude: 28.5833, longitude: 78.5667),
          CityLocation(name: 'Sant Kabir Nagar', stateCode: 'UP', countryCode: 'IN', latitude: 26.7797, longitude: 83.0315),
          CityLocation(name: 'Shahjahanpur', stateCode: 'UP', countryCode: 'IN', latitude: 27.8805, longitude: 79.9120),
          CityLocation(name: 'Shamli', stateCode: 'UP', countryCode: 'IN', latitude: 29.4494, longitude: 77.3134),
          CityLocation(name: 'Shravasti', stateCode: 'UP', countryCode: 'IN', latitude: 27.5042, longitude: 82.0406),
          CityLocation(name: 'Siddharthnagar', stateCode: 'UP', countryCode: 'IN', latitude: 27.2947, longitude: 82.8137),
          CityLocation(name: 'Sitapur', stateCode: 'UP', countryCode: 'IN', latitude: 27.5684, longitude: 80.6829),
          CityLocation(name: 'Sonbhadra', stateCode: 'UP', countryCode: 'IN', latitude: 24.6850, longitude: 83.0650),
          CityLocation(name: 'Sultanpur', stateCode: 'UP', countryCode: 'IN', latitude: 26.2648, longitude: 82.0727),
          CityLocation(name: 'Unnao', stateCode: 'UP', countryCode: 'IN', latitude: 26.5393, longitude: 80.4878),
          CityLocation(name: 'Varanasi', stateCode: 'UP', countryCode: 'IN', latitude: 25.3176, longitude: 82.9739, aliases: ['Banaras', 'Kashi']),
        ],
      ),
      StateLocation(
        name: 'Maharashtra',
        code: 'MH',
        countryCode: 'IN',
        latitude: 19.7515,
        longitude: 75.7139,
        cities: const [
          CityLocation(name: 'Mumbai', stateCode: 'MH', countryCode: 'IN', latitude: 19.0760, longitude: 72.8777, aliases: ['Bombay']),
          CityLocation(name: 'Pune', stateCode: 'MH', countryCode: 'IN', latitude: 18.5204, longitude: 73.8567),
          CityLocation(name: 'Nagpur', stateCode: 'MH', countryCode: 'IN', latitude: 21.1458, longitude: 79.0882),
          CityLocation(name: 'Nashik', stateCode: 'MH', countryCode: 'IN', latitude: 19.9975, longitude: 73.7898),
          CityLocation(name: 'Thane', stateCode: 'MH', countryCode: 'IN', latitude: 19.2183, longitude: 72.9781),
          CityLocation(name: 'Chhatrapati Sambhajinagar', stateCode: 'MH', countryCode: 'IN', latitude: 19.8762, longitude: 75.3433, aliases: ['Aurangabad']),
          CityLocation(name: 'Solapur', stateCode: 'MH', countryCode: 'IN', latitude: 17.6599, longitude: 75.9064),
          CityLocation(name: 'Kolhapur', stateCode: 'MH', countryCode: 'IN', latitude: 16.7050, longitude: 74.2433),
          CityLocation(name: 'Navi Mumbai', stateCode: 'MH', countryCode: 'IN', latitude: 19.0330, longitude: 73.0297),
          CityLocation(name: 'Amravati', stateCode: 'MH', countryCode: 'IN', latitude: 20.9374, longitude: 77.7796),
          CityLocation(name: 'Nanded', stateCode: 'MH', countryCode: 'IN', latitude: 19.1383, longitude: 77.3210),
          CityLocation(name: 'Jalgaon', stateCode: 'MH', countryCode: 'IN', latitude: 21.0077, longitude: 75.5626),
          CityLocation(name: 'Akola', stateCode: 'MH', countryCode: 'IN', latitude: 20.7002, longitude: 77.0082),
          CityLocation(name: 'Latur', stateCode: 'MH', countryCode: 'IN', latitude: 18.4088, longitude: 76.5604),
          CityLocation(name: 'Dhule', stateCode: 'MH', countryCode: 'IN', latitude: 20.9042, longitude: 74.7749),
          CityLocation(name: 'Ahmednagar', stateCode: 'MH', countryCode: 'IN', latitude: 19.0952, longitude: 74.7496, aliases: ['Ahilyanagar']),
          CityLocation(name: 'Chandrapur', stateCode: 'MH', countryCode: 'IN', latitude: 19.9615, longitude: 79.2961),
          CityLocation(name: 'Parbhani', stateCode: 'MH', countryCode: 'IN', latitude: 19.2686, longitude: 76.7708),
          CityLocation(name: 'Jalna', stateCode: 'MH', countryCode: 'IN', latitude: 19.8410, longitude: 75.8864),
          CityLocation(name: 'Sangli', stateCode: 'MH', countryCode: 'IN', latitude: 16.8524, longitude: 74.5815),
          CityLocation(name: 'Satara', stateCode: 'MH', countryCode: 'IN', latitude: 17.6805, longitude: 73.9934),
        ],
      ),
      StateLocation(
        name: 'Delhi',
        code: 'DL',
        countryCode: 'IN',
        latitude: 28.7041,
        longitude: 77.1025,
        aliases: const ['NCT of Delhi', 'New Delhi'],
        cities: const [
          CityLocation(name: 'New Delhi', stateCode: 'DL', countryCode: 'IN', latitude: 28.6139, longitude: 77.2090),
          CityLocation(name: 'Central Delhi', stateCode: 'DL', countryCode: 'IN', latitude: 28.6508, longitude: 77.2346),
          CityLocation(name: 'North Delhi', stateCode: 'DL', countryCode: 'IN', latitude: 28.7186, longitude: 77.1627),
          CityLocation(name: 'South Delhi', stateCode: 'DL', countryCode: 'IN', latitude: 28.5355, longitude: 77.2410),
          CityLocation(name: 'East Delhi', stateCode: 'DL', countryCode: 'IN', latitude: 28.6273, longitude: 77.2784),
          CityLocation(name: 'West Delhi', stateCode: 'DL', countryCode: 'IN', latitude: 28.6473, longitude: 77.1124),
          CityLocation(name: 'North East Delhi', stateCode: 'DL', countryCode: 'IN', latitude: 28.7013, longitude: 77.2711),
          CityLocation(name: 'North West Delhi', stateCode: 'DL', countryCode: 'IN', latitude: 28.7303, longitude: 77.0864),
          CityLocation(name: 'South East Delhi', stateCode: 'DL', countryCode: 'IN', latitude: 28.5614, longitude: 77.2882),
          CityLocation(name: 'South West Delhi', stateCode: 'DL', countryCode: 'IN', latitude: 28.5921, longitude: 77.0460),
          CityLocation(name: 'Shahdara', stateCode: 'DL', countryCode: 'IN', latitude: 28.6734, longitude: 77.2888),
        ],
      ),
      StateLocation(
        name: 'Karnataka',
        code: 'KA',
        countryCode: 'IN',
        latitude: 15.3173,
        longitude: 75.7139,
        cities: const [
          CityLocation(name: 'Bengaluru', stateCode: 'KA', countryCode: 'IN', latitude: 12.9716, longitude: 77.5946, aliases: ['Bangalore']),
          CityLocation(name: 'Mysuru', stateCode: 'KA', countryCode: 'IN', latitude: 12.2958, longitude: 76.6394, aliases: ['Mysore']),
          CityLocation(name: 'Hubballi-Dharwad', stateCode: 'KA', countryCode: 'IN', latitude: 15.3647, longitude: 75.1240, aliases: ['Hubli']),
          CityLocation(name: 'Mangaluru', stateCode: 'KA', countryCode: 'IN', latitude: 12.9141, longitude: 74.8560, aliases: ['Mangalore']),
          CityLocation(name: 'Belagavi', stateCode: 'KA', countryCode: 'IN', latitude: 15.8497, longitude: 74.4977, aliases: ['Belgaum']),
          CityLocation(name: 'Kalaburagi', stateCode: 'KA', countryCode: 'IN', latitude: 17.3297, longitude: 76.8343, aliases: ['Gulbarga']),
          CityLocation(name: 'Davanagere', stateCode: 'KA', countryCode: 'IN', latitude: 14.4644, longitude: 75.9218),
          CityLocation(name: 'Ballari', stateCode: 'KA', countryCode: 'IN', latitude: 15.1394, longitude: 76.9214, aliases: ['Bellary']),
          CityLocation(name: 'Vijayapura', stateCode: 'KA', countryCode: 'IN', latitude: 16.8302, longitude: 75.7100, aliases: ['Bijapur']),
          CityLocation(name: 'Shivamogga', stateCode: 'KA', countryCode: 'IN', latitude: 13.9299, longitude: 75.5681, aliases: ['Shimoga']),
          CityLocation(name: 'Tumakuru', stateCode: 'KA', countryCode: 'IN', latitude: 13.3379, longitude: 77.1173),
          CityLocation(name: 'Udupi', stateCode: 'KA', countryCode: 'IN', latitude: 13.3409, longitude: 74.7421),
          CityLocation(name: 'Bidar', stateCode: 'KA', countryCode: 'IN', latitude: 17.9104, longitude: 77.5199),
          CityLocation(name: 'Hassan', stateCode: 'KA', countryCode: 'IN', latitude: 13.0072, longitude: 76.0962),
        ],
      ),
      StateLocation(
        name: 'Tamil Nadu',
        code: 'TN',
        countryCode: 'IN',
        latitude: 11.1271,
        longitude: 78.6569,
        cities: const [
          CityLocation(name: 'Chennai', stateCode: 'TN', countryCode: 'IN', latitude: 13.0827, longitude: 80.2707, aliases: ['Madras']),
          CityLocation(name: 'Coimbatore', stateCode: 'TN', countryCode: 'IN', latitude: 11.0168, longitude: 76.9558),
          CityLocation(name: 'Madurai', stateCode: 'TN', countryCode: 'IN', latitude: 9.9252, longitude: 78.1198),
          CityLocation(name: 'Tiruchirappalli', stateCode: 'TN', countryCode: 'IN', latitude: 10.7905, longitude: 78.7047, aliases: ['Trichy']),
          CityLocation(name: 'Salem', stateCode: 'TN', countryCode: 'IN', latitude: 11.6643, longitude: 78.1460),
          CityLocation(name: 'Tirunelveli', stateCode: 'TN', countryCode: 'IN', latitude: 8.7139, longitude: 77.7567),
          CityLocation(name: 'Tiruppur', stateCode: 'TN', countryCode: 'IN', latitude: 11.1085, longitude: 77.3411),
          CityLocation(name: 'Vellore', stateCode: 'TN', countryCode: 'IN', latitude: 12.9165, longitude: 79.1325),
          CityLocation(name: 'Erode', stateCode: 'TN', countryCode: 'IN', latitude: 11.3410, longitude: 77.7172),
          CityLocation(name: 'Thoothukudi', stateCode: 'TN', countryCode: 'IN', latitude: 8.7642, longitude: 78.1348, aliases: ['Tuticorin']),
          CityLocation(name: 'Dindigul', stateCode: 'TN', countryCode: 'IN', latitude: 10.3673, longitude: 77.9803),
          CityLocation(name: 'Thanjavur', stateCode: 'TN', countryCode: 'IN', latitude: 10.7870, longitude: 79.1378),
          CityLocation(name: 'Kanchipuram', stateCode: 'TN', countryCode: 'IN', latitude: 12.8342, longitude: 79.7036),
        ],
      ),
      StateLocation(
        name: 'West Bengal',
        code: 'WB',
        countryCode: 'IN',
        latitude: 22.9868,
        longitude: 87.8550,
        cities: const [
          CityLocation(name: 'Kolkata', stateCode: 'WB', countryCode: 'IN', latitude: 22.5726, longitude: 88.3639, aliases: ['Calcutta']),
          CityLocation(name: 'Howrah', stateCode: 'WB', countryCode: 'IN', latitude: 22.5958, longitude: 88.2636),
          CityLocation(name: 'Siliguri', stateCode: 'WB', countryCode: 'IN', latitude: 26.7271, longitude: 88.3953),
          CityLocation(name: 'Asansol', stateCode: 'WB', countryCode: 'IN', latitude: 23.6739, longitude: 86.9524),
          CityLocation(name: 'Durgapur', stateCode: 'WB', countryCode: 'IN', latitude: 23.5204, longitude: 87.3119),
          CityLocation(name: 'Bardhaman', stateCode: 'WB', countryCode: 'IN', latitude: 23.2324, longitude: 87.8615, aliases: ['Burdwan']),
          CityLocation(name: 'Malda', stateCode: 'WB', countryCode: 'IN', latitude: 25.0108, longitude: 88.1411),
          CityLocation(name: 'Kharagpur', stateCode: 'WB', countryCode: 'IN', latitude: 22.3460, longitude: 87.2320),
          CityLocation(name: 'Darjeeling', stateCode: 'WB', countryCode: 'IN', latitude: 27.0410, longitude: 88.2663),
        ],
      ),
      StateLocation(
        name: 'Gujarat',
        code: 'GJ',
        countryCode: 'IN',
        latitude: 22.2587,
        longitude: 71.1924,
        cities: const [
          CityLocation(name: 'Ahmedabad', stateCode: 'GJ', countryCode: 'IN', latitude: 23.0225, longitude: 72.5714),
          CityLocation(name: 'Surat', stateCode: 'GJ', countryCode: 'IN', latitude: 21.1702, longitude: 72.8311),
          CityLocation(name: 'Vadodara', stateCode: 'GJ', countryCode: 'IN', latitude: 22.3072, longitude: 73.1812, aliases: ['Baroda']),
          CityLocation(name: 'Rajkot', stateCode: 'GJ', countryCode: 'IN', latitude: 22.3039, longitude: 70.8022),
          CityLocation(name: 'Bhavnagar', stateCode: 'GJ', countryCode: 'IN', latitude: 21.7645, longitude: 72.1519),
          CityLocation(name: 'Jamnagar', stateCode: 'GJ', countryCode: 'IN', latitude: 22.4707, longitude: 70.0577),
          CityLocation(name: 'Gandhinagar', stateCode: 'GJ', countryCode: 'IN', latitude: 23.2156, longitude: 72.6369),
          CityLocation(name: 'Junagadh', stateCode: 'GJ', countryCode: 'IN', latitude: 21.5222, longitude: 70.4579),
          CityLocation(name: 'Anand', stateCode: 'GJ', countryCode: 'IN', latitude: 22.5645, longitude: 72.9289),
          CityLocation(name: 'Navsari', stateCode: 'GJ', countryCode: 'IN', latitude: 20.9500, longitude: 72.9300),
        ],
      ),
      StateLocation(
        name: 'Rajasthan',
        code: 'RJ',
        countryCode: 'IN',
        latitude: 27.0238,
        longitude: 74.2179,
        cities: const [
          CityLocation(name: 'Jaipur', stateCode: 'RJ', countryCode: 'IN', latitude: 26.9124, longitude: 75.7873),
          CityLocation(name: 'Jodhpur', stateCode: 'RJ', countryCode: 'IN', latitude: 26.2389, longitude: 73.0243),
          CityLocation(name: 'Udaipur', stateCode: 'RJ', countryCode: 'IN', latitude: 24.5854, longitude: 73.7125),
          CityLocation(name: 'Kota', stateCode: 'RJ', countryCode: 'IN', latitude: 25.2138, longitude: 75.8648),
          CityLocation(name: 'Bikaner', stateCode: 'RJ', countryCode: 'IN', latitude: 28.0229, longitude: 73.3119),
          CityLocation(name: 'Ajmer', stateCode: 'RJ', countryCode: 'IN', latitude: 26.4499, longitude: 74.6399),
          CityLocation(name: 'Bhilwara', stateCode: 'RJ', countryCode: 'IN', latitude: 25.3407, longitude: 74.6313),
          CityLocation(name: 'Alwar', stateCode: 'RJ', countryCode: 'IN', latitude: 27.5530, longitude: 76.6346),
          CityLocation(name: 'Sikar', stateCode: 'RJ', countryCode: 'IN', latitude: 27.6094, longitude: 75.1399),
          CityLocation(name: 'Sri Ganganagar', stateCode: 'RJ', countryCode: 'IN', latitude: 29.9094, longitude: 73.8799),
        ],
      ),
      StateLocation(
        name: 'Bihar',
        code: 'BR',
        countryCode: 'IN',
        latitude: 25.0961,
        longitude: 85.3131,
        cities: const [
          CityLocation(name: 'Patna', stateCode: 'BR', countryCode: 'IN', latitude: 25.5941, longitude: 85.1376),
          CityLocation(name: 'Gaya', stateCode: 'BR', countryCode: 'IN', latitude: 24.7914, longitude: 85.0002),
          CityLocation(name: 'Bhagalpur', stateCode: 'BR', countryCode: 'IN', latitude: 25.2425, longitude: 86.9842),
          CityLocation(name: 'Muzaffarpur', stateCode: 'BR', countryCode: 'IN', latitude: 26.1209, longitude: 85.3647),
          CityLocation(name: 'Purnia', stateCode: 'BR', countryCode: 'IN', latitude: 25.7771, longitude: 87.4753),
          CityLocation(name: 'Darbhanga', stateCode: 'BR', countryCode: 'IN', latitude: 26.1542, longitude: 85.8918),
          CityLocation(name: 'Bihar Sharif', stateCode: 'BR', countryCode: 'IN', latitude: 25.1982, longitude: 85.5149),
          CityLocation(name: 'Arrah', stateCode: 'BR', countryCode: 'IN', latitude: 25.5541, longitude: 84.6644),
          CityLocation(name: 'Begusarai', stateCode: 'BR', countryCode: 'IN', latitude: 25.4182, longitude: 86.1272),
          CityLocation(name: 'Katihar', stateCode: 'BR', countryCode: 'IN', latitude: 25.5541, longitude: 87.5684),
        ],
      ),
      StateLocation(
        name: 'Madhya Pradesh',
        code: 'MP',
        countryCode: 'IN',
        latitude: 22.9734,
        longitude: 78.6569,
        cities: const [
          CityLocation(name: 'Bhopal', stateCode: 'MP', countryCode: 'IN', latitude: 23.2599, longitude: 77.4126),
          CityLocation(name: 'Indore', stateCode: 'MP', countryCode: 'IN', latitude: 22.7196, longitude: 75.8577),
          CityLocation(name: 'Gwalior', stateCode: 'MP', countryCode: 'IN', latitude: 26.2183, longitude: 78.1828),
          CityLocation(name: 'Jabalpur', stateCode: 'MP', countryCode: 'IN', latitude: 23.1815, longitude: 79.9864),
          CityLocation(name: 'Ujjain', stateCode: 'MP', countryCode: 'IN', latitude: 23.1765, longitude: 75.7885),
          CityLocation(name: 'Sagar', stateCode: 'MP', countryCode: 'IN', latitude: 23.8388, longitude: 78.7378),
          CityLocation(name: 'Dewas', stateCode: 'MP', countryCode: 'IN', latitude: 22.9676, longitude: 76.0534),
          CityLocation(name: 'Satna', stateCode: 'MP', countryCode: 'IN', latitude: 24.6005, longitude: 80.8322),
          CityLocation(name: 'Ratlam', stateCode: 'MP', countryCode: 'IN', latitude: 23.3315, longitude: 75.0367),
          CityLocation(name: 'Rewa', stateCode: 'MP', countryCode: 'IN', latitude: 24.5362, longitude: 81.3037),
        ],
      ),
      StateLocation(
        name: 'Kerala',
        code: 'KL',
        countryCode: 'IN',
        latitude: 10.8505,
        longitude: 76.2711,
        cities: const [
          CityLocation(name: 'Thiruvananthapuram', stateCode: 'KL', countryCode: 'IN', latitude: 8.5241, longitude: 76.9366, aliases: ['Trivandrum']),
          CityLocation(name: 'Kochi', stateCode: 'KL', countryCode: 'IN', latitude: 9.9312, longitude: 76.2673, aliases: ['Cochin', 'Ernakulam']),
          CityLocation(name: 'Kozhikode', stateCode: 'KL', countryCode: 'IN', latitude: 11.2588, longitude: 75.7804, aliases: ['Calicut']),
          CityLocation(name: 'Thrissur', stateCode: 'KL', countryCode: 'IN', latitude: 10.5276, longitude: 76.2144),
          CityLocation(name: 'Kollam', stateCode: 'KL', countryCode: 'IN', latitude: 8.8932, longitude: 76.6141),
          CityLocation(name: 'Palakkad', stateCode: 'KL', countryCode: 'IN', latitude: 10.7867, longitude: 76.6548),
          CityLocation(name: 'Alappuzha', stateCode: 'KL', countryCode: 'IN', latitude: 9.4981, longitude: 76.3388, aliases: ['Alleppey']),
          CityLocation(name: 'Kannur', stateCode: 'KL', countryCode: 'IN', latitude: 11.8745, longitude: 75.3704),
          CityLocation(name: 'Kottayam', stateCode: 'KL', countryCode: 'IN', latitude: 9.5916, longitude: 76.5222),
          CityLocation(name: 'Malappuram', stateCode: 'KL', countryCode: 'IN', latitude: 11.0510, longitude: 76.0711),
        ],
      ),
      StateLocation(
        name: 'Telangana',
        code: 'TS',
        countryCode: 'IN',
        latitude: 18.1124,
        longitude: 79.0193,
        cities: const [
          CityLocation(name: 'Hyderabad', stateCode: 'TS', countryCode: 'IN', latitude: 17.3850, longitude: 78.4867),
          CityLocation(name: 'Warangal', stateCode: 'TS', countryCode: 'IN', latitude: 17.9689, longitude: 79.5941),
          CityLocation(name: 'Nizamabad', stateCode: 'TS', countryCode: 'IN', latitude: 18.6725, longitude: 78.0941),
          CityLocation(name: 'Karimnagar', stateCode: 'TS', countryCode: 'IN', latitude: 18.4386, longitude: 79.1288),
          CityLocation(name: 'Khammam', stateCode: 'TS', countryCode: 'IN', latitude: 17.2473, longitude: 80.1514),
          CityLocation(name: 'Ramagundam', stateCode: 'TS', countryCode: 'IN', latitude: 18.7551, longitude: 79.5141),
          CityLocation(name: 'Mahbubnagar', stateCode: 'TS', countryCode: 'IN', latitude: 16.7488, longitude: 77.9840),
          CityLocation(name: 'Nalgonda', stateCode: 'TS', countryCode: 'IN', latitude: 17.0577, longitude: 79.2684),
        ],
      ),
      StateLocation(
        name: 'Andhra Pradesh',
        code: 'AP',
        countryCode: 'IN',
        latitude: 15.9129,
        longitude: 79.7400,
        cities: const [
          CityLocation(name: 'Visakhapatnam', stateCode: 'AP', countryCode: 'IN', latitude: 17.6868, longitude: 83.2185, aliases: ['Vizag']),
          CityLocation(name: 'Vijayawada', stateCode: 'AP', countryCode: 'IN', latitude: 16.5062, longitude: 80.6480),
          CityLocation(name: 'Guntur', stateCode: 'AP', countryCode: 'IN', latitude: 16.3067, longitude: 80.4365),
          CityLocation(name: 'Nellore', stateCode: 'AP', countryCode: 'IN', latitude: 14.4426, longitude: 79.9865),
          CityLocation(name: 'Kurnool', stateCode: 'AP', countryCode: 'IN', latitude: 15.8281, longitude: 78.0373),
          CityLocation(name: 'Rajahmundry', stateCode: 'AP', countryCode: 'IN', latitude: 17.0005, longitude: 81.8040),
          CityLocation(name: 'Tirupati', stateCode: 'AP', countryCode: 'IN', latitude: 13.6288, longitude: 79.4192),
          CityLocation(name: 'Kakinada', stateCode: 'AP', countryCode: 'IN', latitude: 16.9891, longitude: 82.2475),
          CityLocation(name: 'Kadapa', stateCode: 'AP', countryCode: 'IN', latitude: 14.4673, longitude: 78.8242),
          CityLocation(name: 'Anantapur', stateCode: 'AP', countryCode: 'IN', latitude: 14.6819, longitude: 77.6006),
        ],
      ),
      StateLocation(
        name: 'Punjab',
        code: 'PB',
        countryCode: 'IN',
        latitude: 31.1471,
        longitude: 75.3412,
        cities: const [
          CityLocation(name: 'Ludhiana', stateCode: 'PB', countryCode: 'IN', latitude: 30.9010, longitude: 75.8573),
          CityLocation(name: 'Amritsar', stateCode: 'PB', countryCode: 'IN', latitude: 31.6340, longitude: 74.8723),
          CityLocation(name: 'Jalandhar', stateCode: 'PB', countryCode: 'IN', latitude: 31.3260, longitude: 75.5762),
          CityLocation(name: 'Patiala', stateCode: 'PB', countryCode: 'IN', latitude: 30.3398, longitude: 76.3869),
          CityLocation(name: 'Bathinda', stateCode: 'PB', countryCode: 'IN', latitude: 30.2110, longitude: 74.9455),
          CityLocation(name: 'Mohali', stateCode: 'PB', countryCode: 'IN', latitude: 30.7046, longitude: 76.7179, aliases: ['SAS Nagar']),
          CityLocation(name: 'Hoshiarpur', stateCode: 'PB', countryCode: 'IN', latitude: 31.5273, longitude: 75.9149),
          CityLocation(name: 'Pathankot', stateCode: 'PB', countryCode: 'IN', latitude: 32.2684, longitude: 75.6529),
        ],
      ),
      StateLocation(
        name: 'Haryana',
        code: 'HR',
        countryCode: 'IN',
        latitude: 29.0588,
        longitude: 76.0856,
        cities: const [
          CityLocation(name: 'Gurugram', stateCode: 'HR', countryCode: 'IN', latitude: 28.4595, longitude: 77.0266, aliases: ['Gurgaon']),
          CityLocation(name: 'Faridabad', stateCode: 'HR', countryCode: 'IN', latitude: 28.4089, longitude: 77.3178),
          CityLocation(name: 'Panipat', stateCode: 'HR', countryCode: 'IN', latitude: 29.3909, longitude: 76.9635),
          CityLocation(name: 'Ambala', stateCode: 'HR', countryCode: 'IN', latitude: 30.3782, longitude: 76.7767),
          CityLocation(name: 'Yamunanagar', stateCode: 'HR', countryCode: 'IN', latitude: 30.1290, longitude: 77.2674),
          CityLocation(name: 'Rohtak', stateCode: 'HR', countryCode: 'IN', latitude: 28.8955, longitude: 76.6066),
          CityLocation(name: 'Hisar', stateCode: 'HR', countryCode: 'IN', latitude: 29.1492, longitude: 75.7217),
          CityLocation(name: 'Karnal', stateCode: 'HR', countryCode: 'IN', latitude: 29.6857, longitude: 76.9905),
          CityLocation(name: 'Sonipat', stateCode: 'HR', countryCode: 'IN', latitude: 28.9931, longitude: 77.0151),
          CityLocation(name: 'Panchkula', stateCode: 'HR', countryCode: 'IN', latitude: 30.6942, longitude: 76.8606),
        ],
      ),
      StateLocation(
        name: 'Uttarakhand',
        code: 'UK',
        countryCode: 'IN',
        latitude: 30.0668,
        longitude: 79.0193,
        cities: const [
          CityLocation(name: 'Dehradun', stateCode: 'UK', countryCode: 'IN', latitude: 30.3165, longitude: 78.0322),
          CityLocation(name: 'Haridwar', stateCode: 'UK', countryCode: 'IN', latitude: 29.9457, longitude: 78.1642),
          CityLocation(name: 'Roorkee', stateCode: 'UK', countryCode: 'IN', latitude: 29.8543, longitude: 77.8880),
          CityLocation(name: 'Haldwani', stateCode: 'UK', countryCode: 'IN', latitude: 29.2183, longitude: 79.5130),
          CityLocation(name: 'Rudrapur', stateCode: 'UK', countryCode: 'IN', latitude: 28.9800, longitude: 79.4000),
          CityLocation(name: 'Rishikesh', stateCode: 'UK', countryCode: 'IN', latitude: 30.0869, longitude: 78.2676),
          CityLocation(name: 'Nainital', stateCode: 'UK', countryCode: 'IN', latitude: 29.3919, longitude: 79.4542),
        ],
      ),
      StateLocation(
        name: 'Assam',
        code: 'AS',
        countryCode: 'IN',
        latitude: 26.2006,
        longitude: 92.9376,
        cities: const [
          CityLocation(name: 'Guwahati', stateCode: 'AS', countryCode: 'IN', latitude: 26.1445, longitude: 91.7362),
          CityLocation(name: 'Silchar', stateCode: 'AS', countryCode: 'IN', latitude: 24.8170, longitude: 92.7970),
          CityLocation(name: 'Dibrugarh', stateCode: 'AS', countryCode: 'IN', latitude: 27.4728, longitude: 94.9120),
          CityLocation(name: 'Jorhat', stateCode: 'AS', countryCode: 'IN', latitude: 26.7509, longitude: 94.2037),
          CityLocation(name: 'Nagaon', stateCode: 'AS', countryCode: 'IN', latitude: 26.3470, longitude: 92.6837),
          CityLocation(name: 'Tezpur', stateCode: 'AS', countryCode: 'IN', latitude: 26.6528, longitude: 92.7926),
        ],
      ),
      StateLocation(
        name: 'Jharkhand',
        code: 'JH',
        countryCode: 'IN',
        latitude: 23.6102,
        longitude: 85.2799,
        cities: const [
          CityLocation(name: 'Ranchi', stateCode: 'JH', countryCode: 'IN', latitude: 23.3441, longitude: 85.3096),
          CityLocation(name: 'Jamshedpur', stateCode: 'JH', countryCode: 'IN', latitude: 22.8046, longitude: 86.2029),
          CityLocation(name: 'Dhanbad', stateCode: 'JH', countryCode: 'IN', latitude: 23.7957, longitude: 86.4304),
          CityLocation(name: 'Bokaro', stateCode: 'JH', countryCode: 'IN', latitude: 23.6693, longitude: 86.1511),
          CityLocation(name: 'Deoghar', stateCode: 'JH', countryCode: 'IN', latitude: 24.4826, longitude: 86.7001),
        ],
      ),
      StateLocation(
        name: 'Odisha',
        code: 'OD',
        countryCode: 'IN',
        latitude: 20.9517,
        longitude: 85.0985,
        cities: const [
          CityLocation(name: 'Bhubaneswar', stateCode: 'OD', countryCode: 'IN', latitude: 20.2961, longitude: 85.8245),
          CityLocation(name: 'Cuttack', stateCode: 'OD', countryCode: 'IN', latitude: 20.4625, longitude: 85.8828),
          CityLocation(name: 'Rourkela', stateCode: 'OD', countryCode: 'IN', latitude: 22.2604, longitude: 84.8536),
          CityLocation(name: 'Berhampur', stateCode: 'OD', countryCode: 'IN', latitude: 19.3150, longitude: 84.7941),
          CityLocation(name: 'Puri', stateCode: 'OD', countryCode: 'IN', latitude: 19.8135, longitude: 85.8312),
        ],
      ),
      StateLocation(
        name: 'Chhattisgarh',
        code: 'CG',
        countryCode: 'IN',
        latitude: 21.2787,
        longitude: 81.8661,
        cities: const [
          CityLocation(name: 'Raipur', stateCode: 'CG', countryCode: 'IN', latitude: 21.2514, longitude: 81.6296),
          CityLocation(name: 'Bhilai', stateCode: 'CG', countryCode: 'IN', latitude: 21.1938, longitude: 81.3509),
          CityLocation(name: 'Bilaspur', stateCode: 'CG', countryCode: 'IN', latitude: 22.0797, longitude: 82.1409),
          CityLocation(name: 'Korba', stateCode: 'CG', countryCode: 'IN', latitude: 22.3595, longitude: 82.7501),
        ],
      ),
      StateLocation(
        name: 'Himachal Pradesh',
        code: 'HP',
        countryCode: 'IN',
        latitude: 31.1048,
        longitude: 77.1734,
        cities: const [
          CityLocation(name: 'Shimla', stateCode: 'HP', countryCode: 'IN', latitude: 31.1048, longitude: 77.1734),
          CityLocation(name: 'Dharamshala', stateCode: 'HP', countryCode: 'IN', latitude: 32.2190, longitude: 76.3234),
          CityLocation(name: 'Solan', stateCode: 'HP', countryCode: 'IN', latitude: 30.9045, longitude: 77.0967),
          CityLocation(name: 'Mandi', stateCode: 'HP', countryCode: 'IN', latitude: 31.5892, longitude: 76.9182),
        ],
      ),
      StateLocation(
        name: 'Jammu and Kashmir',
        code: 'JK',
        countryCode: 'IN',
        latitude: 33.7782,
        longitude: 76.5762,
        cities: const [
          CityLocation(name: 'Srinagar', stateCode: 'JK', countryCode: 'IN', latitude: 34.0837, longitude: 74.7973),
          CityLocation(name: 'Jammu', stateCode: 'JK', countryCode: 'IN', latitude: 32.7266, longitude: 74.8570),
          CityLocation(name: 'Anantnag', stateCode: 'JK', countryCode: 'IN', latitude: 33.7311, longitude: 75.1487),
        ],
      ),
      StateLocation(
        name: 'Goa',
        code: 'GA',
        countryCode: 'IN',
        latitude: 15.2993,
        longitude: 74.1240,
        cities: const [
          CityLocation(name: 'Panaji', stateCode: 'GA', countryCode: 'IN', latitude: 15.4909, longitude: 73.8278, aliases: ['Panjim']),
          CityLocation(name: 'Margao', stateCode: 'GA', countryCode: 'IN', latitude: 15.2832, longitude: 73.9862),
          CityLocation(name: 'Vasco da Gama', stateCode: 'GA', countryCode: 'IN', latitude: 15.3982, longitude: 73.8113),
        ],
      ),
      StateLocation(
        name: 'Chandigarh',
        code: 'CH',
        countryCode: 'IN',
        latitude: 30.7333,
        longitude: 76.7794,
        cities: const [
          CityLocation(name: 'Chandigarh', stateCode: 'CH', countryCode: 'IN', latitude: 30.7333, longitude: 76.7794),
        ],
      ),
      StateLocation(
        name: 'Ladakh',
        code: 'LA',
        countryCode: 'IN',
        latitude: 34.1526,
        longitude: 77.5771,
        cities: const [
          CityLocation(name: 'Leh', stateCode: 'LA', countryCode: 'IN', latitude: 34.1526, longitude: 77.5771),
          CityLocation(name: 'Kargil', stateCode: 'LA', countryCode: 'IN', latitude: 34.5539, longitude: 76.1349),
        ],
      ),
      StateLocation(
        name: 'Puducherry',
        code: 'PY',
        countryCode: 'IN',
        latitude: 11.9416,
        longitude: 79.8083,
        cities: const [
          CityLocation(name: 'Pondicherry', stateCode: 'PY', countryCode: 'IN', latitude: 11.9416, longitude: 79.8083),
          CityLocation(name: 'Karaikal', stateCode: 'PY', countryCode: 'IN', latitude: 10.9254, longitude: 79.8380),
        ],
      ),
      StateLocation(
        name: 'Tripura',
        code: 'TR',
        countryCode: 'IN',
        latitude: 23.8315,
        longitude: 91.2868,
        cities: const [
          CityLocation(name: 'Agartala', stateCode: 'TR', countryCode: 'IN', latitude: 23.8315, longitude: 91.2868),
        ],
      ),
      StateLocation(
        name: 'Meghalaya',
        code: 'ML',
        countryCode: 'IN',
        latitude: 25.4670,
        longitude: 91.3662,
        cities: const [
          CityLocation(name: 'Shillong', stateCode: 'ML', countryCode: 'IN', latitude: 25.5788, longitude: 91.8933),
          CityLocation(name: 'Tura', stateCode: 'ML', countryCode: 'IN', latitude: 25.5141, longitude: 90.2032),
        ],
      ),
      StateLocation(
        name: 'Manipur',
        code: 'MN',
        countryCode: 'IN',
        latitude: 24.6637,
        longitude: 93.9063,
        cities: const [
          CityLocation(name: 'Imphal', stateCode: 'MN', countryCode: 'IN', latitude: 24.8170, longitude: 93.9368),
        ],
      ),
      StateLocation(
        name: 'Nagaland',
        code: 'NL',
        countryCode: 'IN',
        latitude: 26.1584,
        longitude: 94.5624,
        cities: const [
          CityLocation(name: 'Kohima', stateCode: 'NL', countryCode: 'IN', latitude: 25.6751, longitude: 94.1086),
          CityLocation(name: 'Dimapur', stateCode: 'NL', countryCode: 'IN', latitude: 25.9068, longitude: 93.7271),
        ],
      ),
      StateLocation(
        name: 'Mizoram',
        code: 'MZ',
        countryCode: 'IN',
        latitude: 23.1645,
        longitude: 92.9376,
        cities: const [
          CityLocation(name: 'Aizawl', stateCode: 'MZ', countryCode: 'IN', latitude: 23.7271, longitude: 92.7176),
        ],
      ),
      StateLocation(
        name: 'Arunachal Pradesh',
        code: 'AR',
        countryCode: 'IN',
        latitude: 28.2180,
        longitude: 94.7278,
        cities: const [
          CityLocation(name: 'Itanagar', stateCode: 'AR', countryCode: 'IN', latitude: 27.0844, longitude: 93.6053),
          CityLocation(name: 'Naharlagun', stateCode: 'AR', countryCode: 'IN', latitude: 27.1064, longitude: 93.6931),
          CityLocation(name: 'Pasighat', stateCode: 'AR', countryCode: 'IN', latitude: 28.0667, longitude: 95.3333),
        ],
      ),
      StateLocation(
        name: 'Sikkim',
        code: 'SK',
        countryCode: 'IN',
        latitude: 27.5330,
        longitude: 88.5122,
        cities: const [
          CityLocation(name: 'Gangtok', stateCode: 'SK', countryCode: 'IN', latitude: 27.3389, longitude: 88.6065),
        ],
      ),
      StateLocation(
        name: 'Andaman and Nicobar Islands',
        code: 'AN',
        countryCode: 'IN',
        latitude: 11.7401,
        longitude: 92.6586,
        cities: const [
          CityLocation(name: 'Port Blair', stateCode: 'AN', countryCode: 'IN', latitude: 11.6234, longitude: 92.7265),
        ],
      ),
      StateLocation(
        name: 'Dadra and Nagar Haveli and Daman and Diu',
        code: 'DN',
        countryCode: 'IN',
        latitude: 20.1809,
        longitude: 73.0169,
        cities: const [
          CityLocation(name: 'Daman', stateCode: 'DN', countryCode: 'IN', latitude: 20.3974, longitude: 72.8328),
          CityLocation(name: 'Silvassa', stateCode: 'DN', countryCode: 'IN', latitude: 20.2763, longitude: 73.0083),
          CityLocation(name: 'Diu', stateCode: 'DN', countryCode: 'IN', latitude: 20.7144, longitude: 70.9874),
        ],
      ),
      StateLocation(
        name: 'Lakshadweep',
        code: 'LD',
        countryCode: 'IN',
        latitude: 10.5669,
        longitude: 72.6420,
        cities: const [
          CityLocation(name: 'Kavaratti', stateCode: 'LD', countryCode: 'IN', latitude: 10.5669, longitude: 72.6420),
        ],
      ),
    ],
  );

  // -------------------------------------------------------------
  // UNITED STATES: Major states & cities with coordinates
  // -------------------------------------------------------------
  static final CountryLocation _unitedStates = CountryLocation(
    name: 'United States',
    code: 'US',
    dialCode: '+1',
    flag: '🇺🇸',
    states: [
      StateLocation(
        name: 'California',
        code: 'CA',
        countryCode: 'US',
        latitude: 36.7783,
        longitude: -119.4179,
        cities: const [
          CityLocation(name: 'Los Angeles', stateCode: 'CA', countryCode: 'US', latitude: 34.0522, longitude: -118.2437),
          CityLocation(name: 'San Francisco', stateCode: 'CA', countryCode: 'US', latitude: 37.7749, longitude: -122.4194),
          CityLocation(name: 'San Diego', stateCode: 'CA', countryCode: 'US', latitude: 32.7157, longitude: -117.1611),
          CityLocation(name: 'San Jose', stateCode: 'CA', countryCode: 'US', latitude: 37.3382, longitude: -121.8863),
          CityLocation(name: 'Sacramento', stateCode: 'CA', countryCode: 'US', latitude: 38.5816, longitude: -121.4944),
          CityLocation(name: 'Fresno', stateCode: 'CA', countryCode: 'US', latitude: 36.7468, longitude: -119.7726),
          CityLocation(name: 'Oakland', stateCode: 'CA', countryCode: 'US', latitude: 37.8044, longitude: -122.2712),
        ],
      ),
      StateLocation(
        name: 'New York',
        code: 'NY',
        countryCode: 'US',
        latitude: 40.7128,
        longitude: -74.0060,
        cities: const [
          CityLocation(name: 'New York City', stateCode: 'NY', countryCode: 'US', latitude: 40.7128, longitude: -74.0060, aliases: ['NYC', 'Manhattan', 'Brooklyn', 'Queens']),
          CityLocation(name: 'Buffalo', stateCode: 'NY', countryCode: 'US', latitude: 42.8864, longitude: -78.8784),
          CityLocation(name: 'Rochester', stateCode: 'NY', countryCode: 'US', latitude: 43.1566, longitude: -77.6088),
          CityLocation(name: 'Albany', stateCode: 'NY', countryCode: 'US', latitude: 42.6526, longitude: -73.7562),
          CityLocation(name: 'Syracuse', stateCode: 'NY', countryCode: 'US', latitude: 43.0481, longitude: -76.1474),
        ],
      ),
      StateLocation(
        name: 'Texas',
        code: 'TX',
        countryCode: 'US',
        latitude: 31.9686,
        longitude: -99.9018,
        cities: const [
          CityLocation(name: 'Houston', stateCode: 'TX', countryCode: 'US', latitude: 29.7604, longitude: -95.3698),
          CityLocation(name: 'Dallas', stateCode: 'TX', countryCode: 'US', latitude: 32.7767, longitude: -96.7970),
          CityLocation(name: 'Austin', stateCode: 'TX', countryCode: 'US', latitude: 30.2672, longitude: -97.7431),
          CityLocation(name: 'San Antonio', stateCode: 'TX', countryCode: 'US', latitude: 29.4241, longitude: -98.4936),
          CityLocation(name: 'Fort Worth', stateCode: 'TX', countryCode: 'US', latitude: 32.7555, longitude: -97.3308),
        ],
      ),
      StateLocation(
        name: 'Florida',
        code: 'FL',
        countryCode: 'US',
        latitude: 27.6648,
        longitude: -81.5158,
        cities: const [
          CityLocation(name: 'Miami', stateCode: 'FL', countryCode: 'US', latitude: 25.7617, longitude: -80.1918),
          CityLocation(name: 'Orlando', stateCode: 'FL', countryCode: 'US', latitude: 28.5383, longitude: -81.3792),
          CityLocation(name: 'Tampa', stateCode: 'FL', countryCode: 'US', latitude: 27.9506, longitude: -82.4572),
          CityLocation(name: 'Jacksonville', stateCode: 'FL', countryCode: 'US', latitude: 30.3322, longitude: -81.6557),
        ],
      ),
      StateLocation(
        name: 'Illinois',
        code: 'IL',
        countryCode: 'US',
        latitude: 40.6331,
        longitude: -89.3985,
        cities: const [
          CityLocation(name: 'Chicago', stateCode: 'IL', countryCode: 'US', latitude: 41.8781, longitude: -87.6298),
          CityLocation(name: 'Aurora', stateCode: 'IL', countryCode: 'US', latitude: 41.7606, longitude: -88.3201),
          CityLocation(name: 'Springfield', stateCode: 'IL', countryCode: 'US', latitude: 39.7817, longitude: -89.6501),
        ],
      ),
      StateLocation(
        name: 'Washington',
        code: 'WA',
        countryCode: 'US',
        latitude: 47.7511,
        longitude: -120.7401,
        cities: const [
          CityLocation(name: 'Seattle', stateCode: 'WA', countryCode: 'US', latitude: 47.6062, longitude: -122.3321),
          CityLocation(name: 'Spokane', stateCode: 'WA', countryCode: 'US', latitude: 47.6588, longitude: -117.4260),
          CityLocation(name: 'Tacoma', stateCode: 'WA', countryCode: 'US', latitude: 47.2529, longitude: -122.4443),
        ],
      ),
    ],
  );

  // -------------------------------------------------------------
  // UNITED KINGDOM
  // -------------------------------------------------------------
  static final CountryLocation _unitedKingdom = CountryLocation(
    name: 'United Kingdom',
    code: 'GB',
    dialCode: '+44',
    flag: '🇬🇧',
    states: [
      StateLocation(
        name: 'England',
        code: 'ENG',
        countryCode: 'GB',
        latitude: 52.3555,
        longitude: -1.1743,
        cities: const [
          CityLocation(name: 'London', stateCode: 'ENG', countryCode: 'GB', latitude: 51.5074, longitude: -0.1278),
          CityLocation(name: 'Birmingham', stateCode: 'ENG', countryCode: 'GB', latitude: 52.4862, longitude: -1.8904),
          CityLocation(name: 'Manchester', stateCode: 'ENG', countryCode: 'GB', latitude: 53.4808, longitude: -2.2426),
          CityLocation(name: 'Leeds', stateCode: 'ENG', countryCode: 'GB', latitude: 53.8008, longitude: -1.5491),
          CityLocation(name: 'Liverpool', stateCode: 'ENG', countryCode: 'GB', latitude: 53.4084, longitude: -2.9916),
          CityLocation(name: 'Bristol', stateCode: 'ENG', countryCode: 'GB', latitude: 51.4545, longitude: -2.5879),
        ],
      ),
      StateLocation(
        name: 'Scotland',
        code: 'SCT',
        countryCode: 'GB',
        latitude: 56.4907,
        longitude: -4.2026,
        cities: const [
          CityLocation(name: 'Edinburgh', stateCode: 'SCT', countryCode: 'GB', latitude: 55.9533, longitude: -3.1883),
          CityLocation(name: 'Glasgow', stateCode: 'SCT', countryCode: 'GB', latitude: 55.8642, longitude: -4.2518),
          CityLocation(name: 'Aberdeen', stateCode: 'SCT', countryCode: 'GB', latitude: 57.1497, longitude: -2.0943),
        ],
      ),
      StateLocation(
        name: 'Wales',
        code: 'WLS',
        countryCode: 'GB',
        latitude: 52.1307,
        longitude: -3.7837,
        cities: const [
          CityLocation(name: 'Cardiff', stateCode: 'WLS', countryCode: 'GB', latitude: 51.4816, longitude: -3.1791),
          CityLocation(name: 'Swansea', stateCode: 'WLS', countryCode: 'GB', latitude: 51.6214, longitude: -3.9436),
        ],
      ),
      StateLocation(
        name: 'Northern Ireland',
        code: 'NIR',
        countryCode: 'GB',
        latitude: 54.7877,
        longitude: -6.4923,
        cities: const [
          CityLocation(name: 'Belfast', stateCode: 'NIR', countryCode: 'GB', latitude: 54.5973, longitude: -5.9301),
          CityLocation(name: 'Derry', stateCode: 'NIR', countryCode: 'GB', latitude: 54.9966, longitude: -7.3086),
        ],
      ),
    ],
  );

  // -------------------------------------------------------------
  // UNITED ARAB EMIRATES
  // -------------------------------------------------------------
  static final CountryLocation _unitedArabEmirates = CountryLocation(
    name: 'United Arab Emirates',
    code: 'AE',
    dialCode: '+971',
    flag: '🇦🇪',
    states: [
      StateLocation(
        name: 'Dubai',
        code: 'DXB',
        countryCode: 'AE',
        latitude: 25.2048,
        longitude: 55.2708,
        cities: const [
          CityLocation(name: 'Dubai', stateCode: 'DXB', countryCode: 'AE', latitude: 25.2048, longitude: 55.2708),
          CityLocation(name: 'Deira', stateCode: 'DXB', countryCode: 'AE', latitude: 25.2697, longitude: 55.3094),
          CityLocation(name: 'Bur Dubai', stateCode: 'DXB', countryCode: 'AE', latitude: 25.2532, longitude: 55.2972),
          CityLocation(name: 'Jumeirah', stateCode: 'DXB', countryCode: 'AE', latitude: 25.1972, longitude: 55.2411),
        ],
      ),
      StateLocation(
        name: 'Abu Dhabi',
        code: 'AUH',
        countryCode: 'AE',
        latitude: 24.4539,
        longitude: 54.3773,
        cities: const [
          CityLocation(name: 'Abu Dhabi', stateCode: 'AUH', countryCode: 'AE', latitude: 24.4539, longitude: 54.3773),
          CityLocation(name: 'Al Ain', stateCode: 'AUH', countryCode: 'AE', latitude: 24.2075, longitude: 55.7447),
        ],
      ),
      StateLocation(
        name: 'Sharjah',
        code: 'SHJ',
        countryCode: 'AE',
        latitude: 25.3463,
        longitude: 55.4209,
        cities: const [
          CityLocation(name: 'Sharjah', stateCode: 'SHJ', countryCode: 'AE', latitude: 25.3463, longitude: 55.4209),
        ],
      ),
    ],
  );

  // -------------------------------------------------------------
  // CANADA
  // -------------------------------------------------------------
  static final CountryLocation _canada = CountryLocation(
    name: 'Canada',
    code: 'CA',
    dialCode: '+1',
    flag: '🇨🇦',
    states: [
      StateLocation(
        name: 'Ontario',
        code: 'ON',
        countryCode: 'CA',
        latitude: 51.2538,
        longitude: -85.3232,
        cities: const [
          CityLocation(name: 'Toronto', stateCode: 'ON', countryCode: 'CA', latitude: 43.6532, longitude: -79.3832),
          CityLocation(name: 'Ottawa', stateCode: 'ON', countryCode: 'CA', latitude: 45.4215, longitude: -75.6972),
          CityLocation(name: 'Mississauga', stateCode: 'ON', countryCode: 'CA', latitude: 43.5890, longitude: -79.6441),
          CityLocation(name: 'Brampton', stateCode: 'ON', countryCode: 'CA', latitude: 43.7315, longitude: -79.7624),
          CityLocation(name: 'Hamilton', stateCode: 'ON', countryCode: 'CA', latitude: 43.2557, longitude: -79.8711),
        ],
      ),
      StateLocation(
        name: 'British Columbia',
        code: 'BC',
        countryCode: 'CA',
        latitude: 53.7267,
        longitude: -127.6476,
        cities: const [
          CityLocation(name: 'Vancouver', stateCode: 'BC', countryCode: 'CA', latitude: 49.2827, longitude: -123.1207),
          CityLocation(name: 'Victoria', stateCode: 'BC', countryCode: 'CA', latitude: 48.4284, longitude: -123.3656),
          CityLocation(name: 'Surrey', stateCode: 'BC', countryCode: 'CA', latitude: 49.1913, longitude: -122.8490),
        ],
      ),
      StateLocation(
        name: 'Quebec',
        code: 'QC',
        countryCode: 'CA',
        latitude: 52.9399,
        longitude: -73.5491,
        cities: const [
          CityLocation(name: 'Montreal', stateCode: 'QC', countryCode: 'CA', latitude: 45.5017, longitude: -73.5673),
          CityLocation(name: 'Quebec City', stateCode: 'QC', countryCode: 'CA', latitude: 46.8139, longitude: -71.2080),
        ],
      ),
    ],
  );

  // -------------------------------------------------------------
  // AUSTRALIA
  // -------------------------------------------------------------
  static final CountryLocation _australia = CountryLocation(
    name: 'Australia',
    code: 'AU',
    dialCode: '+61',
    flag: '🇦🇺',
    states: [
      StateLocation(
        name: 'New South Wales',
        code: 'NSW',
        countryCode: 'AU',
        latitude: -31.8402,
        longitude: 145.6128,
        cities: const [
          CityLocation(name: 'Sydney', stateCode: 'NSW', countryCode: 'AU', latitude: -33.8688, longitude: 151.2093),
          CityLocation(name: 'Newcastle', stateCode: 'NSW', countryCode: 'AU', latitude: -32.9283, longitude: 151.7817),
          CityLocation(name: 'Wollongong', stateCode: 'NSW', countryCode: 'AU', latitude: -34.4278, longitude: 150.8931),
        ],
      ),
      StateLocation(
        name: 'Victoria',
        code: 'VIC',
        countryCode: 'AU',
        latitude: -37.4713,
        longitude: 144.7852,
        cities: const [
          CityLocation(name: 'Melbourne', stateCode: 'VIC', countryCode: 'AU', latitude: -37.8136, longitude: 144.9631),
          CityLocation(name: 'Geelong', stateCode: 'VIC', countryCode: 'AU', latitude: -38.1499, longitude: 144.3617),
        ],
      ),
      StateLocation(
        name: 'Queensland',
        code: 'QLD',
        countryCode: 'AU',
        latitude: -20.9176,
        longitude: 142.7028,
        cities: const [
          CityLocation(name: 'Brisbane', stateCode: 'QLD', countryCode: 'AU', latitude: -27.4698, longitude: 153.0251),
          CityLocation(name: 'Gold Coast', stateCode: 'QLD', countryCode: 'AU', latitude: -28.0167, longitude: 153.4000),
        ],
      ),
    ],
  );

  // -------------------------------------------------------------
  // SAUDI ARABIA
  // -------------------------------------------------------------
  static final CountryLocation _saudiArabia = CountryLocation(
    name: 'Saudi Arabia',
    code: 'SA',
    dialCode: '+966',
    flag: '🇸🇦',
    states: [
      StateLocation(
        name: 'Riyadh Province',
        code: 'RYD',
        countryCode: 'SA',
        latitude: 24.7136,
        longitude: 46.6753,
        cities: const [
          CityLocation(name: 'Riyadh', stateCode: 'RYD', countryCode: 'SA', latitude: 24.7136, longitude: 46.6753),
        ],
      ),
      StateLocation(
        name: 'Makkah Province',
        code: 'MKH',
        countryCode: 'SA',
        latitude: 21.4858,
        longitude: 39.1925,
        cities: const [
          CityLocation(name: 'Jeddah', stateCode: 'MKH', countryCode: 'SA', latitude: 21.4858, longitude: 39.1925),
          CityLocation(name: 'Mecca', stateCode: 'MKH', countryCode: 'SA', latitude: 21.3891, longitude: 39.8579),
        ],
      ),
    ],
  );

  // -------------------------------------------------------------
  // GERMANY
  // -------------------------------------------------------------
  static final CountryLocation _germany = CountryLocation(
    name: 'Germany',
    code: 'DE',
    dialCode: '+49',
    flag: '🇩🇪',
    states: [
      StateLocation(
        name: 'Berlin',
        code: 'BE',
        countryCode: 'DE',
        latitude: 52.5200,
        longitude: 13.4050,
        cities: const [
          CityLocation(name: 'Berlin', stateCode: 'BE', countryCode: 'DE', latitude: 52.5200, longitude: 13.4050),
        ],
      ),
      StateLocation(
        name: 'Bavaria',
        code: 'BY',
        countryCode: 'DE',
        latitude: 48.7904,
        longitude: 11.4979,
        cities: const [
          CityLocation(name: 'Munich', stateCode: 'BY', countryCode: 'DE', latitude: 48.1351, longitude: 11.5820),
          CityLocation(name: 'Nuremberg', stateCode: 'BY', countryCode: 'DE', latitude: 49.4521, longitude: 11.0767),
        ],
      ),
    ],
  );

  // -------------------------------------------------------------
  // FRANCE
  // -------------------------------------------------------------
  static final CountryLocation _france = CountryLocation(
    name: 'France',
    code: 'FR',
    dialCode: '+33',
    flag: '🇫🇷',
    states: [
      StateLocation(
        name: 'Île-de-France',
        code: 'IDF',
        countryCode: 'FR',
        latitude: 48.8499,
        longitude: 2.6370,
        cities: const [
          CityLocation(name: 'Paris', stateCode: 'IDF', countryCode: 'FR', latitude: 48.8566, longitude: 2.3522),
        ],
      ),
    ],
  );

  // -------------------------------------------------------------
  // SINGAPORE
  // -------------------------------------------------------------
  static final CountryLocation _singapore = CountryLocation(
    name: 'Singapore',
    code: 'SG',
    dialCode: '+65',
    flag: '🇸🇬',
    states: [
      StateLocation(
        name: 'Singapore',
        code: 'SG',
        countryCode: 'SG',
        latitude: 1.3521,
        longitude: 103.8198,
        cities: const [
          CityLocation(name: 'Singapore Central', stateCode: 'SG', countryCode: 'SG', latitude: 1.3521, longitude: 103.8198),
          CityLocation(name: 'Jurong', stateCode: 'SG', countryCode: 'SG', latitude: 1.3329, longitude: 103.7436),
          CityLocation(name: 'Tampines', stateCode: 'SG', countryCode: 'SG', latitude: 1.3526, longitude: 103.9447),
        ],
      ),
    ],
  );

  // -------------------------------------------------------------
  // NEPAL
  // -------------------------------------------------------------
  static final CountryLocation _nepal = CountryLocation(
    name: 'Nepal',
    code: 'NP',
    dialCode: '+977',
    flag: '🇳🇵',
    states: [
      StateLocation(
        name: 'Bagmati',
        code: 'BAG',
        countryCode: 'NP',
        latitude: 27.7172,
        longitude: 85.3240,
        cities: const [
          CityLocation(name: 'Kathmandu', stateCode: 'BAG', countryCode: 'NP', latitude: 27.7172, longitude: 85.3240),
          CityLocation(name: 'Lalitpur', stateCode: 'BAG', countryCode: 'NP', latitude: 27.6588, longitude: 85.3247),
          CityLocation(name: 'Bhaktapur', stateCode: 'BAG', countryCode: 'NP', latitude: 27.6710, longitude: 85.4298),
        ],
      ),
      StateLocation(
        name: 'Gandaki',
        code: 'GAN',
        countryCode: 'NP',
        latitude: 28.2096,
        longitude: 83.9856,
        cities: const [
          CityLocation(name: 'Pokhara', stateCode: 'GAN', countryCode: 'NP', latitude: 28.2096, longitude: 83.9856),
        ],
      ),
    ],
  );

  // -------------------------------------------------------------
  // BANGLADESH
  // -------------------------------------------------------------
  static final CountryLocation _bangladesh = CountryLocation(
    name: 'Bangladesh',
    code: 'BD',
    dialCode: '+880',
    flag: '🇧🇩',
    states: [
      StateLocation(
        name: 'Dhaka Division',
        code: 'DHA',
        countryCode: 'BD',
        latitude: 23.8103,
        longitude: 90.4125,
        cities: const [
          CityLocation(name: 'Dhaka', stateCode: 'DHA', countryCode: 'BD', latitude: 23.8103, longitude: 90.4125),
          CityLocation(name: 'Gazipur', stateCode: 'DHA', countryCode: 'BD', latitude: 23.9999, longitude: 90.4203),
          CityLocation(name: 'Narayanganj', stateCode: 'DHA', countryCode: 'BD', latitude: 23.6238, longitude: 90.5000),
        ],
      ),
      StateLocation(
        name: 'Chittagong Division',
        code: 'CTG',
        countryCode: 'BD',
        latitude: 22.3569,
        longitude: 91.7832,
        cities: const [
          CityLocation(name: 'Chittagong', stateCode: 'CTG', countryCode: 'BD', latitude: 22.3569, longitude: 91.7832),
          CityLocation(name: 'Cox\'s Bazar', stateCode: 'CTG', countryCode: 'BD', latitude: 21.4272, longitude: 92.0058),
        ],
      ),
    ],
  );

  // -------------------------------------------------------------
  // PAKISTAN
  // -------------------------------------------------------------
  static final CountryLocation _pakistan = CountryLocation(
    name: 'Pakistan',
    code: 'PK',
    dialCode: '+92',
    flag: '🇵🇰',
    states: [
      StateLocation(
        name: 'Punjab',
        code: 'PB',
        countryCode: 'PK',
        latitude: 31.1704,
        longitude: 72.7097,
        cities: const [
          CityLocation(name: 'Lahore', stateCode: 'PB', countryCode: 'PK', latitude: 31.5204, longitude: 74.3587),
          CityLocation(name: 'Faisalabad', stateCode: 'PB', countryCode: 'PK', latitude: 31.4504, longitude: 73.1350),
          CityLocation(name: 'Rawalpindi', stateCode: 'PB', countryCode: 'PK', latitude: 33.5651, longitude: 73.0169),
          CityLocation(name: 'Multan', stateCode: 'PB', countryCode: 'PK', latitude: 30.1575, longitude: 71.5249),
        ],
      ),
      StateLocation(
        name: 'Sindh',
        code: 'SD',
        countryCode: 'PK',
        latitude: 25.8943,
        longitude: 68.5247,
        cities: const [
          CityLocation(name: 'Karachi', stateCode: 'SD', countryCode: 'PK', latitude: 24.8607, longitude: 67.0011),
          CityLocation(name: 'Hyderabad', stateCode: 'SD', countryCode: 'PK', latitude: 25.3960, longitude: 68.3578),
        ],
      ),
      StateLocation(
        name: 'Islamabad Capital Territory',
        code: 'ICT',
        countryCode: 'PK',
        latitude: 33.6844,
        longitude: 73.0479,
        cities: const [
          CityLocation(name: 'Islamabad', stateCode: 'ICT', countryCode: 'PK', latitude: 33.6844, longitude: 73.0479),
        ],
      ),
    ],
  );

  // Additional major countries with default state and capital coordinates
  static final CountryLocation _japan = CountryLocation(
    name: 'Japan',
    code: 'JP',
    dialCode: '+81',
    flag: '🇯🇵',
    states: [
      StateLocation(
        name: 'Tokyo',
        code: '13',
        countryCode: 'JP',
        latitude: 35.6762,
        longitude: 139.6503,
        cities: const [
          CityLocation(name: 'Tokyo', stateCode: '13', countryCode: 'JP', latitude: 35.6762, longitude: 139.6503),
          CityLocation(name: 'Shinjuku', stateCode: '13', countryCode: 'JP', latitude: 35.6938, longitude: 139.7034),
        ],
      ),
      StateLocation(
        name: 'Osaka',
        code: '27',
        countryCode: 'JP',
        latitude: 34.6937,
        longitude: 135.5023,
        cities: const [
          CityLocation(name: 'Osaka', stateCode: '27', countryCode: 'JP', latitude: 34.6937, longitude: 135.5023),
        ],
      ),
    ],
  );

  static final CountryLocation _brazil = CountryLocation(
    name: 'Brazil',
    code: 'BR',
    dialCode: '+55',
    flag: '🇧🇷',
    states: [
      StateLocation(
        name: 'São Paulo',
        code: 'SP',
        countryCode: 'BR',
        latitude: -23.5505,
        longitude: -46.6333,
        cities: const [
          CityLocation(name: 'São Paulo', stateCode: 'SP', countryCode: 'BR', latitude: -23.5505, longitude: -46.6333),
          CityLocation(name: 'Campinas', stateCode: 'SP', countryCode: 'BR', latitude: -22.9099, longitude: -47.0626),
        ],
      ),
      StateLocation(
        name: 'Rio de Janeiro',
        code: 'RJ',
        countryCode: 'BR',
        latitude: -22.9068,
        longitude: -43.1729,
        cities: const [
          CityLocation(name: 'Rio de Janeiro', stateCode: 'RJ', countryCode: 'BR', latitude: -22.9068, longitude: -43.1729),
        ],
      ),
    ],
  );

  static final CountryLocation _southAfrica = CountryLocation(
    name: 'South Africa',
    code: 'ZA',
    dialCode: '+27',
    flag: '🇿🇦',
    states: [
      StateLocation(
        name: 'Gauteng',
        code: 'GP',
        countryCode: 'ZA',
        latitude: -26.2708,
        longitude: 28.1123,
        cities: const [
          CityLocation(name: 'Johannesburg', stateCode: 'GP', countryCode: 'ZA', latitude: -26.2041, longitude: 28.0473),
          CityLocation(name: 'Pretoria', stateCode: 'GP', countryCode: 'ZA', latitude: -25.7479, longitude: 28.2293),
        ],
      ),
      StateLocation(
        name: 'Western Cape',
        code: 'WC',
        countryCode: 'ZA',
        latitude: -33.2278,
        longitude: 21.8569,
        cities: const [
          CityLocation(name: 'Cape Town', stateCode: 'WC', countryCode: 'ZA', latitude: -33.9249, longitude: 18.4241),
        ],
      ),
    ],
  );

  static final CountryLocation _newZealand = CountryLocation(
    name: 'New Zealand',
    code: 'NZ',
    dialCode: '+64',
    flag: '🇳🇿',
    states: [
      StateLocation(
        name: 'Auckland',
        code: 'AUK',
        countryCode: 'NZ',
        latitude: -36.8485,
        longitude: 174.7633,
        cities: const [
          CityLocation(name: 'Auckland', stateCode: 'AUK', countryCode: 'NZ', latitude: -36.8485, longitude: 174.7633),
        ],
      ),
      StateLocation(
        name: 'Wellington',
        code: 'WGN',
        countryCode: 'NZ',
        latitude: -41.2865,
        longitude: 174.7762,
        cities: const [
          CityLocation(name: 'Wellington', stateCode: 'WGN', countryCode: 'NZ', latitude: -41.2865, longitude: 174.7762),
        ],
      ),
    ],
  );

  static final CountryLocation _italy = CountryLocation(
    name: 'Italy',
    code: 'IT',
    dialCode: '+39',
    flag: '🇮🇹',
    states: [
      StateLocation(
        name: 'Lazio',
        code: 'LAZ',
        countryCode: 'IT',
        latitude: 41.9028,
        longitude: 12.4964,
        cities: const [
          CityLocation(name: 'Rome', stateCode: 'LAZ', countryCode: 'IT', latitude: 41.9028, longitude: 12.4964),
        ],
      ),
      StateLocation(
        name: 'Lombardy',
        code: 'LOM',
        countryCode: 'IT',
        latitude: 45.4642,
        longitude: 9.1900,
        cities: const [
          CityLocation(name: 'Milan', stateCode: 'LOM', countryCode: 'IT', latitude: 45.4642, longitude: 9.1900),
        ],
      ),
    ],
  );

  static final CountryLocation _spain = CountryLocation(
    name: 'Spain',
    code: 'ES',
    dialCode: '+34',
    flag: '🇪🇸',
    states: [
      StateLocation(
        name: 'Madrid',
        code: 'MD',
        countryCode: 'ES',
        latitude: 40.4168,
        longitude: -3.7038,
        cities: const [
          CityLocation(name: 'Madrid', stateCode: 'MD', countryCode: 'ES', latitude: 40.4168, longitude: -3.7038),
        ],
      ),
      StateLocation(
        name: 'Catalonia',
        code: 'CT',
        countryCode: 'ES',
        latitude: 41.3879,
        longitude: 2.1699,
        cities: const [
          CityLocation(name: 'Barcelona', stateCode: 'CT', countryCode: 'ES', latitude: 41.3879, longitude: 2.1699),
        ],
      ),
    ],
  );

  static final CountryLocation _netherlands = CountryLocation(
    name: 'Netherlands',
    code: 'NL',
    dialCode: '+31',
    flag: '🇳🇱',
    states: [
      StateLocation(
        name: 'North Holland',
        code: 'NH',
        countryCode: 'NL',
        latitude: 52.3676,
        longitude: 4.9041,
        cities: const [
          CityLocation(name: 'Amsterdam', stateCode: 'NH', countryCode: 'NL', latitude: 52.3676, longitude: 4.9041),
        ],
      ),
    ],
  );

  static final CountryLocation _switzerland = CountryLocation(
    name: 'Switzerland',
    code: 'CH',
    dialCode: '+41',
    flag: '🇨🇭',
    states: [
      StateLocation(
        name: 'Zurich',
        code: 'ZH',
        countryCode: 'CH',
        latitude: 47.3769,
        longitude: 8.5417,
        cities: const [
          CityLocation(name: 'Zurich', stateCode: 'ZH', countryCode: 'CH', latitude: 47.3769, longitude: 8.5417),
        ],
      ),
      StateLocation(
        name: 'Geneva',
        code: 'GE',
        countryCode: 'CH',
        latitude: 46.2044,
        longitude: 6.1432,
        cities: const [
          CityLocation(name: 'Geneva', stateCode: 'GE', countryCode: 'CH', latitude: 46.2044, longitude: 6.1432),
        ],
      ),
    ],
  );

  static final CountryLocation _sweden = CountryLocation(
    name: 'Sweden',
    code: 'SE',
    dialCode: '+46',
    flag: '🇸🇪',
    states: [
      StateLocation(
        name: 'Stockholm County',
        code: 'AB',
        countryCode: 'SE',
        latitude: 59.3293,
        longitude: 18.0686,
        cities: const [
          CityLocation(name: 'Stockholm', stateCode: 'AB', countryCode: 'SE', latitude: 59.3293, longitude: 18.0686),
        ],
      ),
    ],
  );

  static final CountryLocation _indonesia = CountryLocation(
    name: 'Indonesia',
    code: 'ID',
    dialCode: '+62',
    flag: '🇮🇩',
    states: [
      StateLocation(
        name: 'Jakarta Special Capital Region',
        code: 'JK',
        countryCode: 'ID',
        latitude: -6.2088,
        longitude: 106.8456,
        cities: const [
          CityLocation(name: 'Jakarta', stateCode: 'JK', countryCode: 'ID', latitude: -6.2088, longitude: 106.8456),
        ],
      ),
    ],
  );

  static final CountryLocation _malaysia = CountryLocation(
    name: 'Malaysia',
    code: 'MY',
    dialCode: '+60',
    flag: '🇲🇾',
    states: [
      StateLocation(
        name: 'Federal Territory of Kuala Lumpur',
        code: 'KUL',
        countryCode: 'MY',
        latitude: 3.1390,
        longitude: 101.6869,
        cities: const [
          CityLocation(name: 'Kuala Lumpur', stateCode: 'KUL', countryCode: 'MY', latitude: 3.1390, longitude: 101.6869),
        ],
      ),
    ],
  );

  static final CountryLocation _philippines = CountryLocation(
    name: 'Philippines',
    code: 'PH',
    dialCode: '+63',
    flag: '🇵🇭',
    states: [
      StateLocation(
        name: 'Metro Manila',
        code: 'NCR',
        countryCode: 'PH',
        latitude: 14.5995,
        longitude: 120.9842,
        cities: const [
          CityLocation(name: 'Manila', stateCode: 'NCR', countryCode: 'PH', latitude: 14.5995, longitude: 120.9842),
          CityLocation(name: 'Quezon City', stateCode: 'NCR', countryCode: 'PH', latitude: 14.6760, longitude: 121.0437),
        ],
      ),
    ],
  );

  static final CountryLocation _thailand = CountryLocation(
    name: 'Thailand',
    code: 'TH',
    dialCode: '+66',
    flag: '🇹🇭',
    states: [
      StateLocation(
        name: 'Bangkok',
        code: 'BKK',
        countryCode: 'TH',
        latitude: 13.7563,
        longitude: 100.5018,
        cities: const [
          CityLocation(name: 'Bangkok', stateCode: 'BKK', countryCode: 'TH', latitude: 13.7563, longitude: 100.5018),
        ],
      ),
    ],
  );

  static final CountryLocation _vietnam = CountryLocation(
    name: 'Vietnam',
    code: 'VN',
    dialCode: '+84',
    flag: '🇻🇳',
    states: [
      StateLocation(
        name: 'Hanoi',
        code: 'HAN',
        countryCode: 'VN',
        latitude: 21.0285,
        longitude: 105.8542,
        cities: const [
          CityLocation(name: 'Hanoi', stateCode: 'HAN', countryCode: 'VN', latitude: 21.0285, longitude: 105.8542),
        ],
      ),
      StateLocation(
        name: 'Ho Chi Minh City',
        code: 'SGN',
        countryCode: 'VN',
        latitude: 10.8231,
        longitude: 106.6297,
        cities: const [
          CityLocation(name: 'Ho Chi Minh City', stateCode: 'SGN', countryCode: 'VN', latitude: 10.8231, longitude: 106.6297),
        ],
      ),
    ],
  );

  static final CountryLocation _southKorea = CountryLocation(
    name: 'South Korea',
    code: 'KR',
    dialCode: '+82',
    flag: '🇰🇷',
    states: [
      StateLocation(
        name: 'Seoul',
        code: '11',
        countryCode: 'KR',
        latitude: 37.5665,
        longitude: 126.9780,
        cities: const [
          CityLocation(name: 'Seoul', stateCode: '11', countryCode: 'KR', latitude: 37.5665, longitude: 126.9780),
        ],
      ),
      StateLocation(
        name: 'Busan',
        code: '26',
        countryCode: 'KR',
        latitude: 35.1796,
        longitude: 129.0756,
        cities: const [
          CityLocation(name: 'Busan', stateCode: '26', countryCode: 'KR', latitude: 35.1796, longitude: 129.0756),
        ],
      ),
    ],
  );

  static final CountryLocation _sriLanka = CountryLocation(
    name: 'Sri Lanka',
    code: 'LK',
    dialCode: '+94',
    flag: '🇱🇰',
    states: [
      StateLocation(
        name: 'Western Province',
        code: 'WP',
        countryCode: 'LK',
        latitude: 6.9271,
        longitude: 79.8612,
        cities: const [
          CityLocation(name: 'Colombo', stateCode: 'WP', countryCode: 'LK', latitude: 6.9271, longitude: 79.8612),
        ],
      ),
    ],
  );

  static final CountryLocation _mexico = CountryLocation(
    name: 'Mexico',
    code: 'MX',
    dialCode: '+52',
    flag: '🇲🇽',
    states: [
      StateLocation(
        name: 'Mexico City',
        code: 'CDMX',
        countryCode: 'MX',
        latitude: 19.4326,
        longitude: -99.1332,
        cities: const [
          CityLocation(name: 'Mexico City', stateCode: 'CDMX', countryCode: 'MX', latitude: 19.4326, longitude: -99.1332),
        ],
      ),
      StateLocation(
        name: 'Jalisco',
        code: 'JAL',
        countryCode: 'MX',
        latitude: 20.6597,
        longitude: -103.3496,
        cities: const [
          CityLocation(name: 'Guadalajara', stateCode: 'JAL', countryCode: 'MX', latitude: 20.6597, longitude: -103.3496),
        ],
      ),
    ],
  );

  static final CountryLocation _argentina = CountryLocation(
    name: 'Argentina',
    code: 'AR',
    dialCode: '+54',
    flag: '🇦🇷',
    states: [
      StateLocation(
        name: 'Buenos Aires',
        code: 'BA',
        countryCode: 'AR',
        latitude: -34.6037,
        longitude: -58.3816,
        cities: const [
          CityLocation(name: 'Buenos Aires', stateCode: 'BA', countryCode: 'AR', latitude: -34.6037, longitude: -58.3816),
        ],
      ),
    ],
  );

  static final CountryLocation _chile = CountryLocation(
    name: 'Chile',
    code: 'CL',
    dialCode: '+56',
    flag: '🇨🇱',
    states: [
      StateLocation(
        name: 'Santiago Metropolitan',
        code: 'RM',
        countryCode: 'CL',
        latitude: -33.4489,
        longitude: -70.6693,
        cities: const [
          CityLocation(name: 'Santiago', stateCode: 'RM', countryCode: 'CL', latitude: -33.4489, longitude: -70.6693),
        ],
      ),
    ],
  );

  static final CountryLocation _egypt = CountryLocation(
    name: 'Egypt',
    code: 'EG',
    dialCode: '+20',
    flag: '🇪🇬',
    states: [
      StateLocation(
        name: 'Cairo Governorate',
        code: 'CAI',
        countryCode: 'EG',
        latitude: 30.0444,
        longitude: 31.2357,
        cities: const [
          CityLocation(name: 'Cairo', stateCode: 'CAI', countryCode: 'EG', latitude: 30.0444, longitude: 31.2357),
          CityLocation(name: 'Giza', stateCode: 'CAI', countryCode: 'EG', latitude: 30.0131, longitude: 31.2089),
        ],
      ),
      StateLocation(
        name: 'Alexandria Governorate',
        code: 'ALX',
        countryCode: 'EG',
        latitude: 31.2001,
        longitude: 29.9187,
        cities: const [
          CityLocation(name: 'Alexandria', stateCode: 'ALX', countryCode: 'EG', latitude: 31.2001, longitude: 29.9187),
        ],
      ),
    ],
  );

  static final CountryLocation _nigeria = CountryLocation(
    name: 'Nigeria',
    code: 'NG',
    dialCode: '+234',
    flag: '🇳🇬',
    states: [
      StateLocation(
        name: 'Lagos State',
        code: 'LA',
        countryCode: 'NG',
        latitude: 6.5244,
        longitude: 3.3792,
        cities: const [
          CityLocation(name: 'Lagos', stateCode: 'LA', countryCode: 'NG', latitude: 6.5244, longitude: 3.3792),
          CityLocation(name: 'Ikeja', stateCode: 'LA', countryCode: 'NG', latitude: 6.6018, longitude: 3.3515),
        ],
      ),
      StateLocation(
        name: 'Federal Capital Territory',
        code: 'FC',
        countryCode: 'NG',
        latitude: 9.0765,
        longitude: 7.3986,
        cities: const [
          CityLocation(name: 'Abuja', stateCode: 'FC', countryCode: 'NG', latitude: 9.0765, longitude: 7.3986),
        ],
      ),
    ],
  );

  static final CountryLocation _kenya = CountryLocation(
    name: 'Kenya',
    code: 'KE',
    dialCode: '+254',
    flag: '🇰🇪',
    states: [
      StateLocation(
        name: 'Nairobi County',
        code: 'NBO',
        countryCode: 'KE',
        latitude: -1.2921,
        longitude: 36.8219,
        cities: const [
          CityLocation(name: 'Nairobi', stateCode: 'NBO', countryCode: 'KE', latitude: -1.2921, longitude: 36.8219),
        ],
      ),
      StateLocation(
        name: 'Mombasa County',
        code: 'MBA',
        countryCode: 'KE',
        latitude: -4.0435,
        longitude: 39.6682,
        cities: const [
          CityLocation(name: 'Mombasa', stateCode: 'MBA', countryCode: 'KE', latitude: -4.0435, longitude: 39.6682),
        ],
      ),
    ],
  );

  static final List<CountryLocation> _globalCountries = [
    CountryLocation(name: 'Afghanistan', code: 'AF', dialCode: '+93', flag: '🇦🇫', states: const [StateLocation(name: 'Kabul Province', code: 'KBL', countryCode: 'AF', latitude: 34.5553, longitude: 69.2075, cities: [CityLocation(name: 'Kabul', stateCode: 'KBL', countryCode: 'AF', latitude: 34.5553, longitude: 69.2075)])]),
    CountryLocation(name: 'Albania', code: 'AL', dialCode: '+355', flag: '🇦🇱', states: const [StateLocation(name: 'Tirana County', code: 'TR', countryCode: 'AL', latitude: 41.3275, longitude: 19.8187, cities: [CityLocation(name: 'Tirana', stateCode: 'TR', countryCode: 'AL', latitude: 41.3275, longitude: 19.8187)])]),
    CountryLocation(name: 'Algeria', code: 'DZ', dialCode: '+213', flag: '🇩🇿', states: const [StateLocation(name: 'Algiers Province', code: '16', countryCode: 'DZ', latitude: 36.7538, longitude: 3.0588, cities: [CityLocation(name: 'Algiers', stateCode: '16', countryCode: 'DZ', latitude: 36.7538, longitude: 3.0588)])]),
    CountryLocation(name: 'Andorra', code: 'AD', dialCode: '+376', flag: '🇦🇩', states: const [StateLocation(name: 'Andorra la Vella', code: '07', countryCode: 'AD', latitude: 42.5063, longitude: 1.5218, cities: [CityLocation(name: 'Andorra la Vella', stateCode: '07', countryCode: 'AD', latitude: 42.5063, longitude: 1.5218)])]),
    CountryLocation(name: 'Angola', code: 'AO', dialCode: '+244', flag: '🇦🇴', states: const [StateLocation(name: 'Luanda Province', code: 'LUA', countryCode: 'AO', latitude: -8.8390, longitude: 13.2894, cities: [CityLocation(name: 'Luanda', stateCode: 'LUA', countryCode: 'AO', latitude: -8.8390, longitude: 13.2894)])]),
    CountryLocation(name: 'Austria', code: 'AT', dialCode: '+43', flag: '🇦🇹', states: const [StateLocation(name: 'Vienna', code: '9', countryCode: 'AT', latitude: 48.2082, longitude: 16.3738, cities: [CityLocation(name: 'Vienna', stateCode: '9', countryCode: 'AT', latitude: 48.2082, longitude: 16.3738)])]),
    CountryLocation(name: 'Azerbaijan', code: 'AZ', dialCode: '+994', flag: '🇦🇿', states: const [StateLocation(name: 'Baku', code: 'BA', countryCode: 'AZ', latitude: 40.4093, longitude: 49.8671, cities: [CityLocation(name: 'Baku', stateCode: 'BA', countryCode: 'AZ', latitude: 40.4093, longitude: 49.8671)])]),
    CountryLocation(name: 'Bahamas', code: 'BS', dialCode: '+1242', flag: '🇧🇸'),
    CountryLocation(name: 'Bahrain', code: 'BH', dialCode: '+973', flag: '🇧🇭', states: const [StateLocation(name: 'Capital Governorate', code: '13', countryCode: 'BH', latitude: 26.2285, longitude: 50.5860, cities: [CityLocation(name: 'Manama', stateCode: '13', countryCode: 'BH', latitude: 26.2285, longitude: 50.5860)])]),
    CountryLocation(name: 'Belarus', code: 'BY', dialCode: '+375', flag: '🇧🇾', states: const [StateLocation(name: 'Minsk', code: 'HM', countryCode: 'BY', latitude: 53.9045, longitude: 27.5615, cities: [CityLocation(name: 'Minsk', stateCode: 'HM', countryCode: 'BY', latitude: 53.9045, longitude: 27.5615)])]),
    CountryLocation(name: 'Belgium', code: 'BE', dialCode: '+32', flag: '🇧🇪', states: const [StateLocation(name: 'Brussels Capital Region', code: 'BRU', countryCode: 'BE', latitude: 50.8503, longitude: 4.3517, cities: [CityLocation(name: 'Brussels', stateCode: 'BRU', countryCode: 'BE', latitude: 50.8503, longitude: 4.3517)])]),
    CountryLocation(name: 'Belize', code: 'BZ', dialCode: '+501', flag: '🇧🇿'),
    CountryLocation(name: 'Bhutan', code: 'BT', dialCode: '+975', flag: '🇧🇹', states: const [StateLocation(name: 'Thimphu District', code: '15', countryCode: 'BT', latitude: 27.4728, longitude: 89.6393, cities: [CityLocation(name: 'Thimphu', stateCode: '15', countryCode: 'BT', latitude: 27.4728, longitude: 89.6393)])]),
    CountryLocation(name: 'Bolivia', code: 'BO', dialCode: '+591', flag: '🇧🇴'),
    CountryLocation(name: 'Bosnia and Herzegovina', code: 'BA', dialCode: '+387', flag: '🇧🇦'),
    CountryLocation(name: 'Botswana', code: 'BW', dialCode: '+267', flag: '🇧🇼'),
    CountryLocation(name: 'Brunei', code: 'BN', dialCode: '+673', flag: '🇧🇳'),
    CountryLocation(name: 'Bulgaria', code: 'BG', dialCode: '+359', flag: '🇧🇬', states: const [StateLocation(name: 'Sofia City', code: '22', countryCode: 'BG', latitude: 42.6977, longitude: 23.3219, cities: [CityLocation(name: 'Sofia', stateCode: '22', countryCode: 'BG', latitude: 42.6977, longitude: 23.3219)])]),
    CountryLocation(name: 'Cambodia', code: 'KH', dialCode: '+855', flag: '🇰🇭', states: const [StateLocation(name: 'Phnom Penh', code: '12', countryCode: 'KH', latitude: 11.5564, longitude: 104.9282, cities: [CityLocation(name: 'Phnom Penh', stateCode: '12', countryCode: 'KH', latitude: 11.5564, longitude: 104.9282)])]),
    CountryLocation(name: 'Cameroon', code: 'CM', dialCode: '+237', flag: '🇨🇲'),
    CountryLocation(name: 'Colombia', code: 'CO', dialCode: '+57', flag: '🇨🇴', states: const [StateLocation(name: 'Bogota D.C.', code: 'DC', countryCode: 'CO', latitude: 4.7110, longitude: -74.0721, cities: [CityLocation(name: 'Bogota', stateCode: 'DC', countryCode: 'CO', latitude: 4.7110, longitude: -74.0721)])]),
    CountryLocation(name: 'Costa Rica', code: 'CR', dialCode: '+506', flag: '🇨🇷'),
    CountryLocation(name: 'Croatia', code: 'HR', dialCode: '+385', flag: '🇭🇷', states: const [StateLocation(name: 'Zagreb', code: '21', countryCode: 'HR', latitude: 45.8150, longitude: 15.9819, cities: [CityLocation(name: 'Zagreb', stateCode: '21', countryCode: 'HR', latitude: 45.8150, longitude: 15.9819)])]),
    CountryLocation(name: 'Cuba', code: 'CU', dialCode: '+53', flag: '🇨🇺'),
    CountryLocation(name: 'Cyprus', code: 'CY', dialCode: '+357', flag: '🇨🇾'),
    CountryLocation(name: 'Czech Republic', code: 'CZ', dialCode: '+420', flag: '🇨🇿', states: const [StateLocation(name: 'Prague', code: '10', countryCode: 'CZ', latitude: 50.0755, longitude: 14.4378, cities: [CityLocation(name: 'Prague', stateCode: '10', countryCode: 'CZ', latitude: 50.0755, longitude: 14.4378)])]),
    CountryLocation(name: 'Denmark', code: 'DK', dialCode: '+45', flag: '🇩🇰', states: const [StateLocation(name: 'Capital Region of Denmark', code: '84', countryCode: 'DK', latitude: 55.6761, longitude: 12.5683, cities: [CityLocation(name: 'Copenhagen', stateCode: '84', countryCode: 'DK', latitude: 55.6761, longitude: 12.5683)])]),
    CountryLocation(name: 'Dominican Republic', code: 'DO', dialCode: '+1809', flag: '🇩🇴'),
    CountryLocation(name: 'Ecuador', code: 'EC', dialCode: '+593', flag: '🇪🇨'),
    CountryLocation(name: 'Estonia', code: 'EE', dialCode: '+372', flag: '🇪🇪'),
    CountryLocation(name: 'Ethiopia', code: 'ET', dialCode: '+251', flag: '🇪🇹', states: const [StateLocation(name: 'Addis Ababa', code: 'AA', countryCode: 'ET', latitude: 9.0300, longitude: 38.7400, cities: [CityLocation(name: 'Addis Ababa', stateCode: 'AA', countryCode: 'ET', latitude: 9.0300, longitude: 38.7400)])]),
    CountryLocation(name: 'Fiji', code: 'FJ', dialCode: '+679', flag: '🇫🇯'),
    CountryLocation(name: 'Finland', code: 'FI', dialCode: '+358', flag: '🇫🇮', states: const [StateLocation(name: 'Uusimaa', code: '18', countryCode: 'FI', latitude: 60.1699, longitude: 24.9384, cities: [CityLocation(name: 'Helsinki', stateCode: '18', countryCode: 'FI', latitude: 60.1699, longitude: 24.9384)])]),
    CountryLocation(name: 'Georgia', code: 'GE', dialCode: '+995', flag: '🇬🇪'),
    CountryLocation(name: 'Ghana', code: 'GH', dialCode: '+233', flag: '🇬🇭', states: const [StateLocation(name: 'Greater Accra', code: 'AA', countryCode: 'GH', latitude: 5.6037, longitude: -0.1870, cities: [CityLocation(name: 'Accra', stateCode: 'AA', countryCode: 'GH', latitude: 5.6037, longitude: -0.1870)])]),
    CountryLocation(name: 'Greece', code: 'GR', dialCode: '+30', flag: '🇬🇷', states: const [StateLocation(name: 'Attica', code: 'I', countryCode: 'GR', latitude: 37.9838, longitude: 23.7275, cities: [CityLocation(name: 'Athens', stateCode: 'I', countryCode: 'GR', latitude: 37.9838, longitude: 23.7275)])]),
    CountryLocation(name: 'Guatemala', code: 'GT', dialCode: '+502', flag: '🇬🇹'),
    CountryLocation(name: 'Hong Kong', code: 'HK', dialCode: '+852', flag: '🇭🇰', states: const [StateLocation(name: 'Hong Kong Island', code: 'HK', countryCode: 'HK', latitude: 22.3193, longitude: 114.1694, cities: [CityLocation(name: 'Hong Kong', stateCode: 'HK', countryCode: 'HK', latitude: 22.3193, longitude: 114.1694)])]),
    CountryLocation(name: 'Hungary', code: 'HU', dialCode: '+36', flag: '🇭🇺', states: const [StateLocation(name: 'Budapest', code: 'BU', countryCode: 'HU', latitude: 47.4979, longitude: 19.0402, cities: [CityLocation(name: 'Budapest', stateCode: 'BU', countryCode: 'HU', latitude: 47.4979, longitude: 19.0402)])]),
    CountryLocation(name: 'Iceland', code: 'IS', dialCode: '+354', flag: '🇮🇸'),
    CountryLocation(name: 'Iran', code: 'IR', dialCode: '+98', flag: '🇮🇷', states: const [StateLocation(name: 'Tehran Province', code: '07', countryCode: 'IR', latitude: 35.6892, longitude: 51.3890, cities: [CityLocation(name: 'Tehran', stateCode: '07', countryCode: 'IR', latitude: 35.6892, longitude: 51.3890)])]),
    CountryLocation(name: 'Iraq', code: 'IQ', dialCode: '+964', flag: '🇮🇶', states: const [StateLocation(name: 'Baghdad Governorate', code: 'BG', countryCode: 'IQ', latitude: 33.3152, longitude: 44.3661, cities: [CityLocation(name: 'Baghdad', stateCode: 'BG', countryCode: 'IQ', latitude: 33.3152, longitude: 44.3661)])]),
    CountryLocation(name: 'Ireland', code: 'IE', dialCode: '+353', flag: '🇮🇪', states: const [StateLocation(name: 'Leinster', code: 'L', countryCode: 'IE', latitude: 53.3498, longitude: -6.2603, cities: [CityLocation(name: 'Dublin', stateCode: 'L', countryCode: 'IE', latitude: 53.3498, longitude: -6.2603)])]),
    CountryLocation(name: 'Israel', code: 'IL', dialCode: '+972', flag: '🇮🇱', states: const [StateLocation(name: 'Tel Aviv District', code: 'TA', countryCode: 'IL', latitude: 32.0853, longitude: 34.7818, cities: [CityLocation(name: 'Tel Aviv', stateCode: 'TA', countryCode: 'IL', latitude: 32.0853, longitude: 34.7818)])]),
    CountryLocation(name: 'Jamaica', code: 'JM', dialCode: '+1876', flag: '🇯🇲'),
    CountryLocation(name: 'Jordan', code: 'JO', dialCode: '+962', flag: '🇯🇴', states: const [StateLocation(name: 'Amman Governorate', code: 'AM', countryCode: 'JO', latitude: 31.9454, longitude: 35.9284, cities: [CityLocation(name: 'Amman', stateCode: 'AM', countryCode: 'JO', latitude: 31.9454, longitude: 35.9284)])]),
    CountryLocation(name: 'Kazakhstan', code: 'KZ', dialCode: '+7', flag: '🇰🇿', states: const [StateLocation(name: 'Astana', code: 'AST', countryCode: 'KZ', latitude: 51.1694, longitude: 71.4491, cities: [CityLocation(name: 'Astana', stateCode: 'AST', countryCode: 'KZ', latitude: 51.1694, longitude: 71.4491)])]),
    CountryLocation(name: 'Kuwait', code: 'KW', dialCode: '+965', flag: '🇰🇼', states: const [StateLocation(name: 'Capital Governorate', code: 'KU', countryCode: 'KW', latitude: 29.3759, longitude: 47.9774, cities: [CityLocation(name: 'Kuwait City', stateCode: 'KU', countryCode: 'KW', latitude: 29.3759, longitude: 47.9774)])]),
    CountryLocation(name: 'Latvia', code: 'LV', dialCode: '+371', flag: '🇱🇻'),
    CountryLocation(name: 'Lebanon', code: 'LB', dialCode: '+961', flag: '🇱🇧', states: const [StateLocation(name: 'Beirut Governorate', code: 'BA', countryCode: 'LB', latitude: 33.8938, longitude: 35.5018, cities: [CityLocation(name: 'Beirut', stateCode: 'BA', countryCode: 'LB', latitude: 33.8938, longitude: 35.5018)])]),
    CountryLocation(name: 'Lithuania', code: 'LT', dialCode: '+370', flag: '🇱🇹'),
    CountryLocation(name: 'Luxembourg', code: 'LU', dialCode: '+352', flag: '🇱🇺'),
    CountryLocation(name: 'Maldives', code: 'MV', dialCode: '+960', flag: '🇲🇻', states: const [StateLocation(name: 'Male', code: 'MLE', countryCode: 'MV', latitude: 4.1755, longitude: 73.5093, cities: [CityLocation(name: 'Male', stateCode: 'MLE', countryCode: 'MV', latitude: 4.1755, longitude: 73.5093)])]),
    CountryLocation(name: 'Malta', code: 'MT', dialCode: '+356', flag: '🇲🇹'),
    CountryLocation(name: 'Mauritius', code: 'MU', dialCode: '+230', flag: '🇲🇺'),
    CountryLocation(name: 'Morocco', code: 'MA', dialCode: '+212', flag: '🇲🇦', states: const [StateLocation(name: 'Casablanca-Settat', code: '06', countryCode: 'MA', latitude: 33.5731, longitude: -7.5898, cities: [CityLocation(name: 'Casablanca', stateCode: '06', countryCode: 'MA', latitude: 33.5731, longitude: -7.5898)])]),
    CountryLocation(name: 'Myanmar', code: 'MM', dialCode: '+95', flag: '🇲🇲'),
    CountryLocation(name: 'Norway', code: 'NO', dialCode: '+47', flag: '🇳🇴', states: const [StateLocation(name: 'Oslo', code: '03', countryCode: 'NO', latitude: 59.9139, longitude: 10.7522, cities: [CityLocation(name: 'Oslo', stateCode: '03', countryCode: 'NO', latitude: 59.9139, longitude: 10.7522)])]),
    CountryLocation(name: 'Oman', code: 'OM', dialCode: '+968', flag: '🇴🇲', states: const [StateLocation(name: 'Muscat Governorate', code: 'MA', countryCode: 'OM', latitude: 23.5880, longitude: 58.3829, cities: [CityLocation(name: 'Muscat', stateCode: 'MA', countryCode: 'OM', latitude: 23.5880, longitude: 58.3829)])]),
    CountryLocation(name: 'Panama', code: 'PA', dialCode: '+507', flag: '🇵🇦'),
    CountryLocation(name: 'Peru', code: 'PE', dialCode: '+51', flag: '🇵🇪', states: const [StateLocation(name: 'Lima Province', code: 'LIM', countryCode: 'PE', latitude: -12.0464, longitude: -77.0428, cities: [CityLocation(name: 'Lima', stateCode: 'LIM', countryCode: 'PE', latitude: -12.0464, longitude: -77.0428)])]),
    CountryLocation(name: 'Poland', code: 'PL', dialCode: '+48', flag: '🇵🇱', states: const [StateLocation(name: 'Masovian Voivodeship', code: '14', countryCode: 'PL', latitude: 52.2297, longitude: 21.0122, cities: [CityLocation(name: 'Warsaw', stateCode: '14', countryCode: 'PL', latitude: 52.2297, longitude: 21.0122)])]),
    CountryLocation(name: 'Portugal', code: 'PT', dialCode: '+351', flag: '🇵🇹', states: const [StateLocation(name: 'Lisbon District', code: '11', countryCode: 'PT', latitude: 38.7223, longitude: -9.1393, cities: [CityLocation(name: 'Lisbon', stateCode: '11', countryCode: 'PT', latitude: 38.7223, longitude: -9.1393)])]),
    CountryLocation(name: 'Qatar', code: 'QA', dialCode: '+974', flag: '🇶🇦', states: const [StateLocation(name: 'Doha', code: 'DA', countryCode: 'QA', latitude: 25.2854, longitude: 51.5310, cities: [CityLocation(name: 'Doha', stateCode: 'DA', countryCode: 'QA', latitude: 25.2854, longitude: 51.5310)])]),
    CountryLocation(name: 'Romania', code: 'RO', dialCode: '+40', flag: '🇷🇴', states: const [StateLocation(name: 'Bucharest', code: 'B', countryCode: 'RO', latitude: 44.4268, longitude: 26.1025, cities: [CityLocation(name: 'Bucharest', stateCode: 'B', countryCode: 'RO', latitude: 44.4268, longitude: 26.1025)])]),
    CountryLocation(name: 'Russia', code: 'RU', dialCode: '+7', flag: '🇷🇺', states: const [StateLocation(name: 'Moscow', code: 'MOW', countryCode: 'RU', latitude: 55.7558, longitude: 37.6173, cities: [CityLocation(name: 'Moscow', stateCode: 'MOW', countryCode: 'RU', latitude: 55.7558, longitude: 37.6173)])]),
    CountryLocation(name: 'Rwanda', code: 'RW', dialCode: '+250', flag: '🇷🇼'),
    CountryLocation(name: 'Serbia', code: 'RS', dialCode: '+381', flag: '🇷🇸'),
    CountryLocation(name: 'Slovakia', code: 'SK', dialCode: '+421', flag: '🇸🇰'),
    CountryLocation(name: 'Slovenia', code: 'SI', dialCode: '+386', flag: '🇸🇮'),
    CountryLocation(name: 'Tanzania', code: 'TZ', dialCode: '+255', flag: '🇹🇿'),
    CountryLocation(name: 'Tunisia', code: 'TN', dialCode: '+216', flag: '🇹🇳'),
    CountryLocation(name: 'Turkey', code: 'TR', dialCode: '+90', flag: '🇹🇷', states: const [StateLocation(name: 'Istanbul Province', code: '34', countryCode: 'TR', latitude: 41.0082, longitude: 28.9784, cities: [CityLocation(name: 'Istanbul', stateCode: '34', countryCode: 'TR', latitude: 41.0082, longitude: 28.9784)])]),
    CountryLocation(name: 'Uganda', code: 'UG', dialCode: '+256', flag: '🇺🇬'),
    CountryLocation(name: 'Ukraine', code: 'UA', dialCode: '+380', flag: '🇺🇦', states: const [StateLocation(name: 'Kyiv', code: '30', countryCode: 'UA', latitude: 50.4501, longitude: 30.5234, cities: [CityLocation(name: 'Kyiv', stateCode: '30', countryCode: 'UA', latitude: 50.4501, longitude: 30.5234)])]),
    CountryLocation(name: 'Uruguay', code: 'UY', dialCode: '+598', flag: '🇺🇾'),
    CountryLocation(name: 'Uzbekistan', code: 'UZ', dialCode: '+998', flag: '🇺🇿'),
    CountryLocation(name: 'Venezuela', code: 'VE', dialCode: '+58', flag: '🇻🇪'),
    CountryLocation(name: 'Zimbabwe', code: 'ZW', dialCode: '+263', flag: '🇿🇼'),
  ];
}
