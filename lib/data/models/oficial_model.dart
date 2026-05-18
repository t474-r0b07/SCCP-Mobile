import '../../core/utils/grado_assets.dart';

class OficialModel {
  final String id;
  final String nombre;
  final String grado;
  final String grupo;
  final String? turno;
  final bool activo;
  final String? reoAsignado;
  final String? imei;
  final String? jurisdiccion;

  const OficialModel({
    required this.id,
    required this.nombre,
    required this.grado,
    required this.grupo,
    this.turno,
    this.activo = true,
    this.reoAsignado,
    this.imei,
    this.jurisdiccion,
  });

  factory OficialModel.fromJson(Map<String, dynamic> json) {
    return OficialModel(
      id: json['id_oficial'] as String? ?? json['ID Oficial'] as String,
      nombre:
          json['nombre_oficial'] as String? ?? json['Nombre Oficial'] as String,
      grado: json['grado'] as String? ?? json['grade'] as String? ?? 'Oficial',
      grupo:
          json['grupo'] as String? ?? json['Grupo/Turno'] as String? ?? 'alfa',
      turno: json['turno'] as String? ?? json['Turno'] as String?,
      activo: json['activo'] as bool? ?? true,
      reoAsignado:
          json['reo_asignado'] as String? ?? json['Reo Asignado'] as String?,
      imei: json['imei'] as String? ?? json['IMEI'] as String?,
      jurisdiccion:
          json['jurisdiccion'] as String? ?? json['Jurisdiccion'] as String?,
    );
  }

  OficialModel copyWith({
    String? id,
    String? nombre,
    String? grado,
    String? grupo,
    String? turno,
    bool? activo,
    String? reoAsignado,
    String? imei,
    String? jurisdiccion,
  }) {
    return OficialModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      grado: grado ?? this.grado,
      grupo: grupo ?? this.grupo,
      turno: turno ?? this.turno,
      activo: activo ?? this.activo,
      reoAsignado: reoAsignado ?? this.reoAsignado,
      imei: imei ?? this.imei,
      jurisdiccion: jurisdiccion ?? this.jurisdiccion,
    );
  }

  String get gradoDisplay => GradoAssets.displayName(grado);
}
