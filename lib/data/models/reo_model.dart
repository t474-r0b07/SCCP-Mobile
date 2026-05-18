class ReoModel {
  final String codigo;
  final String nombre;
  final String? coordenadasCasa;
  final String? telefono;
  final double? latitudCasa;
  final double? longitudCasa;

  const ReoModel({
    required this.codigo,
    required this.nombre,
    this.coordenadasCasa,
    this.telefono,
    this.latitudCasa,
    this.longitudCasa,
  });

  factory ReoModel.fromJson(Map<String, dynamic> json) {
    return ReoModel(
      codigo: json['codigo_reo'] as String? ?? json['Codigo_Reo'] as String,
      nombre: json['nombre_completo'] as String? ??
          json['Nombre_Completo'] as String? ??
          'Sin nombre',
      coordenadasCasa: json['coordenadas_casa'] as String? ??
          json['Coordenadas_Casa'] as String?,
      telefono: json['telefono'] as String? ?? json['Telefono'] as String?,
      latitudCasa: (json['latitud_casa'] as num?)?.toDouble() ??
          (json['latitud'] as num?)?.toDouble(),
      longitudCasa: (json['longitud_casa'] as num?)?.toDouble() ??
          (json['longitud'] as num?)?.toDouble(),
    );
  }

  List<double>? get coordenadas {
    final fromText = _parseCoordinateText(coordenadasCasa);
    if (fromText != null) return fromText;

    if (latitudCasa != null &&
        longitudCasa != null &&
        latitudCasa!.abs() <= 90 &&
        longitudCasa!.abs() <= 180) {
      return [latitudCasa!, longitudCasa!];
    }
    return null;
  }

  List<double>? _parseCoordinateText(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final matches = RegExp(r'-?\d+(?:\.\d+)?').allMatches(raw);
    if (matches.length < 2) return null;

    final first = double.tryParse(matches.elementAt(0).group(0)!);
    final second = double.tryParse(matches.elementAt(1).group(0)!);
    if (first == null || second == null) return null;

    if (first.abs() <= 90 && second.abs() <= 180) {
      return [first, second];
    }
    if (second.abs() <= 90 && first.abs() <= 180) {
      // Corrige textos tipo "POINT(lng lat)" intercambiando orden.
      return [second, first];
    }
    return null;
  }
}
