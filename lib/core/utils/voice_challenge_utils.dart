import 'dart:math';

class VoiceChallengeUtils {
  static const double minSimilarity = 0.75;

  static const List<String> _actions = <String>[
    'OFICIAL ACTIVO',
    'CONTROL TACTICO',
    'CUSTODIA OPERATIVA',
    'VIGILANCIA DOMICILIARIA',
    'PATRULLA DE CONTROL',
    'SUPERVISION INMEDIATA',
  ];

  static const List<String> _contexts = <String>[
    'SIN NOVEDAD',
    'EN VERIFICACION',
    'MODO ALERTA',
    'RUTA ASIGNADA',
    'PUESTO CONFIRMADO',
    'REPORTE EN CURSO',
  ];

  static const List<String> _tokens = <String>[
    'ALFA',
    'BRAVO',
    'SIERRA',
    'NEXO',
    'ECO',
    'DELTA',
    'ZETA',
    'LIMA',
  ];

  static String generateChallengePhrase({
    required bool isParteSorpresa,
    required DateTime slot,
    String? idSorpresa,
    int? seed,
  }) {
    final fallbackSeed = DateTime.now().microsecondsSinceEpoch ^
        slot.millisecondsSinceEpoch ^
        (idSorpresa?.hashCode ?? 0) ^
        (isParteSorpresa ? 0x9E3779B9 : 0x7F4A7C15);
    final random = seed == null ? Random.secure() : Random(fallbackSeed ^ seed);

    final action = _actions[random.nextInt(_actions.length)];
    final context = _contexts[random.nextInt(_contexts.length)];
    final token = _tokens[random.nextInt(_tokens.length)];

    final slotCode =
        '${slot.hour.toString().padLeft(2, '0')}${slot.minute.toString().padLeft(2, '0')}';
    final mode = isParteSorpresa ? 'SORPRESA' : 'OBLIGATORIO';
    return '$action $mode $context CLAVE $token $slotCode';
  }
}
