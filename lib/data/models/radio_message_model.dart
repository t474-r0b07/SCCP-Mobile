class RadioMessageModel {
  final String id;
  final String officialId;
  final String fromUser;
  final String toUser;
  final String message;
  final String type;
  final String status;
  final DateTime timestamp;

  const RadioMessageModel({
    required this.id,
    required this.officialId,
    required this.fromUser,
    required this.toUser,
    required this.message,
    required this.type,
    required this.status,
    required this.timestamp,
  });

  bool get isIncomingFromSupervisor =>
      toUser.toUpperCase() == officialId.toUpperCase() &&
      fromUser.toUpperCase() == 'SUPERVISOR';

  factory RadioMessageModel.fromJson(Map<String, dynamic> json) {
    final tsRaw = json['timestamp'] ?? json['created_at'];
    final parsed = tsRaw is String
        ? DateTime.tryParse(tsRaw)
        : tsRaw is DateTime
            ? tsRaw
            : null;

    return RadioMessageModel(
      id: (json['id_mensaje'] ?? json['id'] ?? '').toString(),
      officialId:
          (json['id_oficial'] ?? json['id_oficial_ref'] ?? '').toString(),
      fromUser: (json['de_usuario'] ?? json['from_user'] ?? '').toString(),
      toUser: (json['para_usuario'] ?? json['to_user'] ?? '').toString(),
      message: (json['mensaje'] ?? json['message'] ?? '').toString(),
      type: (json['tipo'] ?? 'RADIO').toString(),
      status: (json['estado'] ?? 'NUEVO').toString(),
      timestamp: parsed ?? DateTime.now(),
    );
  }
}
