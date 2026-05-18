class GradoAssets {
  static const String defaultGrade = 'SARGENTO';

  static const List<String> catalog = <String>[
    'SARGENTO',
    'SARGENTO SEGUNDO',
    'SARGENTO PRIMERO',
    'SARGENTO MAYOR',
    'SUBOFICIAL SEGUNDO',
    'SUBOFICIAL PRIMERO',
    'SUBOFICIAL MAYOR',
    'SUBOFICIAL SUPERIOR',
    'SUBTENIENTE',
    'TENIENTE',
    'CAPITAN',
    'MAYOR',
    'TENIENTE CORONEL',
    'CORONEL',
  ];

  static const Map<String, String> _numericToGrade = <String, String>{
    '1': 'SARGENTO',
    '2': 'SARGENTO SEGUNDO',
    '3': 'SARGENTO PRIMERO',
    '4': 'SARGENTO MAYOR',
    '5': 'SUBOFICIAL SEGUNDO',
    '6': 'SUBOFICIAL PRIMERO',
    '7': 'SUBOFICIAL MAYOR',
    '8': 'SUBOFICIAL SUPERIOR',
    '9': 'SUBTENIENTE',
    '10': 'TENIENTE',
    '11': 'CAPITAN',
    '12': 'MAYOR',
    '13': 'TENIENTE CORONEL',
    '14': 'CORONEL',
  };

  static const Map<String, String> _gradeToIcon = <String, String>{
    'SARGENTO': 'sgto.png',
    'SARGENTO SEGUNDO': 'sgtoseg.png',
    'SARGENTO PRIMERO': 'sgtopri.png',
    'SARGENTO MAYOR': 'sgtomy.png',
    'SUBOFICIAL SEGUNDO': 'sofseg.png',
    'SUBOFICIAL PRIMERO': 'sofpri.png',
    'SUBOFICIAL MAYOR': 'sofmy.png',
    'SUBOFICIAL SUPERIOR': 'sofsup.png',
    'SUBTENIENTE': 'subtte.png',
    'TENIENTE': 'tte.png',
    'CAPITAN': 'cap.png',
    'MAYOR': 'my.png',
    'TENIENTE CORONEL': 'ttecnl.png',
    'CORONEL': 'cnl.png',
  };

  static String displayName(String? rawGrade) {
    final normalized = _normalize(rawGrade);
    if (normalized.isEmpty) return defaultGrade;

    final asNumber = _numericToGrade[normalized];
    if (asNumber != null) return asNumber;

    if (catalog.contains(normalized)) return normalized;

    if (normalized == 'SGTO') return 'SARGENTO';
    if (normalized == 'SGTO SEGUNDO' || normalized == 'SARGENTO 2DO') {
      return 'SARGENTO SEGUNDO';
    }
    if (normalized == 'SGTO PRIMERO' || normalized == 'SARGENTO 1RO') {
      return 'SARGENTO PRIMERO';
    }
    if (normalized == 'SGTO MAYOR') return 'SARGENTO MAYOR';
    if (normalized == 'SOF SEGUNDO') return 'SUBOFICIAL SEGUNDO';
    if (normalized == 'SOF PRIMERO') return 'SUBOFICIAL PRIMERO';
    if (normalized == 'SOF MAYOR') return 'SUBOFICIAL MAYOR';
    if (normalized == 'SOF SUPERIOR') return 'SUBOFICIAL SUPERIOR';
    if (normalized == 'SUB TTE') return 'SUBTENIENTE';
    if (normalized == 'TTE') return 'TENIENTE';
    if (normalized == 'CAPITAN' || normalized == 'CAP') return 'CAPITAN';
    if (normalized == 'MY') return 'MAYOR';
    if (normalized == 'TTE CNL') return 'TENIENTE CORONEL';
    if (normalized == 'CNL') return 'CORONEL';

    return normalized;
  }

  static int hierarchyLevel(String? rawGrade) {
    final grade = displayName(rawGrade);
    final idx = catalog.indexOf(grade);
    return idx >= 0 ? idx + 1 : 1;
  }

  static String iconAsset(String? rawGrade) {
    final grade = displayName(rawGrade);
    final fileName = _gradeToIcon[grade] ?? 'sgto.png';
    return 'assets/icons/$fileName';
  }

  static String _normalize(String? rawGrade) {
    final value = (rawGrade ?? '').trim().toUpperCase();
    return value
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^A-Z0-9 ]'), '');
  }
}
