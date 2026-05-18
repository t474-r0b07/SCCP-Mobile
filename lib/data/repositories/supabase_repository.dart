import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:sccp_shared/sccp_shared.dart';
import '../../core/utils/parte_schedule_utils.dart';
import '../../core/utils/utc_time_utils.dart';
import '../models/oficial_model.dart';
import '../models/radio_message_model.dart';
import '../models/reo_model.dart';

class SupabaseRepository {
  final _supabase = Supabase.instance.client;
  static const String _voiceProfileReadRpc = 'fn_get_voice_profile_secure';
  static const String _voiceProfileUpsertRpc = 'fn_upsert_voice_profile_secure';
  static const String _voiceCodePrefix = 'VOICE_CODE:';
  static const String _voiceEmbeddingPrefix = 'VOICE_EMB64:';

  Future<OficialModel?> getOficialById(String idOficial) async {
    try {
      final response = await _supabase
          .from('oficiales')
          .select()
          .eq('id_oficial', idOficial)
          .eq('activo', true)
          .maybeSingle();

      if (response == null) return null;
      return OficialModel.fromJson(response);
    } catch (_) {
      return null;
    }
  }

  Future<OficialModel?> getOficialByDeviceId(String deviceId) async {
    try {
      final response = await _supabase
          .from('oficiales')
          .select()
          .eq('imei', deviceId)
          .eq('activo', true)
          .maybeSingle();

      if (response == null) return null;
      return OficialModel.fromJson(response);
    } catch (_) {
      return null;
    }
  }

  Future<void> registerDeviceToOficial({
    required String idOficial,
    required String deviceId,
  }) async {
    try {
      await _supabase.from('oficiales').update({
        'imei': deviceId,
        'updated_at': UtcTimeUtils.nowIso(),
      }).eq('id_oficial', idOficial);
    } catch (_) {
      // Silencioso
    }
  }

  Future<String?> getVoiceProfileCode(String idOficial) async {
    final profile = await getVoiceProfileData(idOficial);
    return profile.voiceCode;
  }

  Future<({String? voiceCode, List<double>? biometricEmbedding})>
      getVoiceProfileData(String idOficial) async {
    final secureProfile = await _fetchSecureVoiceProfile(idOficial);
    if (secureProfile != null) {
      return secureProfile;
    }
    return _fetchLegacyVoiceProfile(idOficial);
  }

  Future<bool> saveVoiceProfileCode({
    required String idOficial,
    required String voiceCode,
    List<double>? biometricEmbedding,
    bool allowOverwrite = false,
  }) async {
    final normalizedVoiceCode = voiceCode.trim();
    if (normalizedVoiceCode.isEmpty) return false;

    try {
      final existing = await getVoiceProfileCode(idOficial);
      if (!allowOverwrite &&
          existing != null &&
          existing.isNotEmpty &&
          existing != normalizedVoiceCode) {
        debugPrint(
          'saveVoiceProfileCode blocked: existing profile for $idOficial',
        );
        return false;
      }

      final rpcResponse = await _supabase.rpc(
        _voiceProfileUpsertRpc,
        params: {
          'p_id_oficial': idOficial,
          'p_voice_code': normalizedVoiceCode,
          'p_biometric_embedding':
              biometricEmbedding != null && biometricEmbedding.isNotEmpty
                  ? biometricEmbedding
                  : null,
          'p_allow_overwrite': allowOverwrite,
        },
      );
      if (rpcResponse is bool) {
        return rpcResponse;
      }
      if (rpcResponse is Map<String, dynamic>) {
        if (rpcResponse['ok'] is bool) {
          return rpcResponse['ok'] as bool;
        }
        if (rpcResponse['updated'] is bool) {
          return rpcResponse['updated'] as bool;
        }
      }
      debugPrint(
        'saveVoiceProfileCode blocked: invalid RPC response $_voiceProfileUpsertRpc',
      );
      return false;
    } catch (e) {
      debugPrint(
        'saveVoiceProfileCode blocked: secure RPC $_voiceProfileUpsertRpc unavailable ($e)',
      );
      return false;
    }
  }

  Future<({String? voiceCode, List<double>? biometricEmbedding})?>
      _fetchSecureVoiceProfile(String idOficial) async {
    try {
      final raw = await _supabase.rpc(
        _voiceProfileReadRpc,
        params: {'p_id_oficial': idOficial},
      );
      if (raw == null || raw is! Map) {
        return null;
      }
      final row = Map<String, dynamic>.from(raw);
      final voiceCode = (row['voice_code'] ??
              row['codigo_voz'] ??
              row['expected_phrase'] ??
              row['phrase'])
          ?.toString()
          .trim();
      final embedding = _parseVoiceEmbeddingDynamic(
        row['biometric_embedding'] ??
            row['voice_embedding'] ??
            row['embedding'],
      );
      final hasVoiceCode = voiceCode != null && voiceCode.isNotEmpty;
      final hasEmbedding = embedding != null && embedding.isNotEmpty;
      if (!hasVoiceCode && !hasEmbedding) {
        return null;
      }
      return (
        voiceCode: hasVoiceCode ? voiceCode : null,
        biometricEmbedding: hasEmbedding ? embedding : null,
      );
    } catch (e) {
      debugPrint(
        'Voice secure profile RPC unavailable ($_voiceProfileReadRpc): $e',
      );
      return null;
    }
  }

  Future<({String? voiceCode, List<double>? biometricEmbedding})>
      _fetchLegacyVoiceProfile(String idOficial) async {
    try {
      final response = await _supabase
          .from('partes_oficiales')
          .select('novedad,ruta_audio')
          .eq('id_reporte', 'VOZ_$idOficial')
          .maybeSingle();
      if (response == null) {
        return (voiceCode: null, biometricEmbedding: null);
      }
      final row = Map<String, dynamic>.from(response);
      return (
        voiceCode: _extractVoiceCode(row['novedad']?.toString()),
        biometricEmbedding:
            _extractVoiceEmbedding(row['ruta_audio']?.toString()),
      );
    } catch (_) {
      return (voiceCode: null, biometricEmbedding: null);
    }
  }

  String? _extractVoiceCode(String? raw) {
    if (raw == null) return null;
    final note = raw.trim();
    if (note.isEmpty) return null;

    final idx = note.indexOf(_voiceCodePrefix);
    if (idx < 0) return null;
    final value = note
        .substring(idx + _voiceCodePrefix.length)
        .split(RegExp(r'[\r\n|]'))
        .first
        .trim();
    return value.isEmpty ? null : value;
  }

  List<double>? _extractVoiceEmbedding(String? raw) {
    if (raw == null) return null;
    final source = raw.trim();
    if (!source.startsWith(_voiceEmbeddingPrefix)) return null;
    final encoded = source.substring(_voiceEmbeddingPrefix.length).trim();
    if (encoded.isEmpty) return null;
    try {
      final decoded = utf8.decode(base64Decode(encoded));
      final parsed = jsonDecode(decoded);
      if (parsed is! List) return null;
      final values = <double>[];
      for (final item in parsed) {
        if (item is num) {
          values.add(item.toDouble());
        }
      }
      return values.isEmpty ? null : values;
    } catch (_) {
      return null;
    }
  }

  List<double>? _parseVoiceEmbeddingDynamic(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) {
      final values = <double>[];
      for (final item in raw) {
        if (item is num) {
          values.add(item.toDouble());
        }
      }
      return values.isEmpty ? null : values;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      try {
        final decoded = jsonDecode(trimmed);
        return _parseVoiceEmbeddingDynamic(decoded);
      } catch (_) {
        return _extractVoiceEmbedding(trimmed);
      }
    }
    return null;
  }

  Future<ReoModel?> getReoBycodigo(String codigo) async {
    try {
      final response = await _supabase
          .from('reos')
          .select()
          .eq('codigo_reo', codigo)
          .maybeSingle();

      if (response == null) return null;
      return ReoModel.fromJson(response);
    } catch (_) {
      return null;
    }
  }

  Future<bool> upsertMonitoreo(Map<String, dynamic> data) async {
    try {
      await _supabase.from('monitoreo_reportes').upsert(data);
      return true;
    } catch (_) {
      debugPrint('Supabase upsertMonitoreo failed');
      return false;
    }
  }

  Future<bool> insertInconsistencia(Map<String, dynamic> data) async {
    try {
      await _supabase.from('inconsistencias').insert(data);
      return true;
    } catch (_) {
      debugPrint('Supabase insertInconsistencia failed');
      return false;
    }
  }

  Future<bool> upsertParteOficial({
    required String idOficial,
    required DateTime slotTime,
    required String resultadoVoz,
    required String estado,
    String? novedad,
    double? latitud,
    double? longitud,
    String? rutaAudio,
  }) async {
    try {
      final slotKey = ParteScheduleUtils.slotKey(slotTime);
      final idReporte = 'PARTE_${idOficial}_$slotKey';
      await _supabase.from('partes_oficiales').upsert({
        'id_reporte': idReporte,
        'id_oficial': idOficial,
        'latitud': latitud,
        'longitud': longitud,
        'resultado_voz': resultadoVoz,
        'ruta_audio': rutaAudio,
        'novedad': novedad,
        'estado': estado,
        'verificado': resultadoVoz == 'APROBADO',
      });
      return true;
    } catch (_) {
      debugPrint('Supabase upsertParteOficial failed');
      return false;
    }
  }

  Future<({bool ok, double? score, String? message})> verifyVoiceBiometric({
    required String idOficial,
    required String expectedPhrase,
    required String recognizedText,
    String? audioRef,
  }) async {
    try {
      final raw = await _supabase.rpc(
        'fn_voice_biometric_verify',
        params: {
          'p_id_oficial': idOficial,
          'p_expected_phrase': expectedPhrase,
          'p_recognized_text': recognizedText,
          'p_audio_ref': (audioRef ?? '').trim(),
        },
      );

      if (raw is Map<String, dynamic>) {
        return (
          ok: raw['ok'] == true || raw['approved'] == true,
          score: (raw['score'] as num?)?.toDouble(),
          message: raw['message']?.toString(),
        );
      }

      if (raw is bool) {
        return (
          ok: raw,
          score: null,
          message: raw ? 'Biometría validada' : 'Biometría rechazada',
        );
      }

      return (
        ok: false,
        score: null,
        message: 'Respuesta biométrica inválida',
      );
    } catch (e) {
      return (
        ok: false,
        score: null,
        message: 'Motor biométrico no disponible (fn_voice_biometric_verify).',
      );
    }
  }

  Future<bool> hasParteOficialForSlot({
    required String idOficial,
    required DateTime slotTime,
  }) async {
    try {
      final slotKey = ParteScheduleUtils.slotKey(slotTime);
      final idReporte = 'PARTE_${idOficial}_$slotKey';
      final row = await _supabase
          .from('partes_oficiales')
          .select('id_reporte')
          .eq('id_reporte', idReporte)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  Stream<List<Map<String, dynamic>>> watchPartesSorpresa(String idOficial) {
    final official = idOficial.trim().toUpperCase();
    return _supabase
        .from('partes_sorpresa')
        .stream(primaryKey: ['id_sorpresa']).map(
      (rows) => rows.where(
        (row) {
          final rowOfficial = (row['id_oficial'] ?? row['id_oficial_ref'] ?? '')
              .toString()
              .trim()
              .toUpperCase();
          final estado = (row['estado'] ?? '').toString().trim().toUpperCase();
          final isPending =
              estado.isEmpty || estado == 'NUEVO' || estado == 'NUEVA';
          return rowOfficial == official && isPending;
        },
      ).toList(),
    );
  }

  Future<void> markParteLeido(String idSorpresa) async {
    try {
      await _supabase.from('partes_sorpresa').update({
        'estado': 'LEIDO',
        'fecha_lectura': UtcTimeUtils.nowIso(),
      }).eq('id_sorpresa', idSorpresa);
    } catch (_) {
      // Silencioso
    }
  }

  Future<List<Map<String, dynamic>>> getPendingPartesSorpresaByOficial({
    required String idOficial,
    int limit = 20,
  }) async {
    try {
      final safeId = idOficial.replaceAll(',', '').trim();
      final rows = await _supabase
          .from('partes_sorpresa')
          .select()
          .or('id_oficial.eq.$safeId,id_oficial_ref.eq.$safeId')
          .order('timestamp', ascending: false)
          .limit(limit);

      final data = (rows as List).cast<Map<String, dynamic>>();
      return data.where((row) {
        final estado = (row['estado'] ?? '').toString().trim().toUpperCase();
        return estado.isEmpty ||
            estado == 'NUEVO' ||
            estado == 'NUEVA' ||
            estado == 'LEIDO';
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> completarParteSorpresa({
    required String idSorpresa,
    required String respuestaOficial,
    double? latitud,
    double? longitud,
  }) async {
    try {
      final updates = <String, dynamic>{
        'estado': 'COMPLETADO',
        'fecha_completado': UtcTimeUtils.nowIso(),
        'respuesta_oficial': respuestaOficial,
      };
      if (latitud != null) updates['latitud_respuesta'] = latitud;
      if (longitud != null) updates['longitud_respuesta'] = longitud;

      await _supabase
          .from('partes_sorpresa')
          .update(updates)
          .eq('id_sorpresa', idSorpresa);
      return true;
    } catch (_) {
      return false;
    }
  }

  Stream<List<RadioMessageModel>> watchRadioMessages(String idOficial) {
    final official = idOficial.trim();
    final base = _supabase
        .from(SharedDb.tableRadioMensajes)
        .stream(primaryKey: ['id_mensaje']);
    final filtered = official.isEmpty ? base : base.eq('id_oficial', official);

    return filtered.order('timestamp').limit(200).map((rows) {
      final items = rows.map(RadioMessageModel.fromJson).toList();
      items.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return items;
    });
  }

  Future<bool> sendRadioMessage({
    required String idOficial,
    required String fromUser,
    required String toUser,
    required String message,
    required String type,
  }) async {
    final rawType = type.trim().toUpperCase();
    final cleanMessage = message.trim();
    try {
      final id = 'RADIO_${idOficial}_${DateTime.now().millisecondsSinceEpoch}';
      await _supabase.from(SharedDb.tableRadioMensajes).insert({
        'id_mensaje': id,
        'id_oficial': idOficial,
        'de_usuario': fromUser,
        'para_usuario': toUser,
        'mensaje': cleanMessage,
        'tipo': rawType,
        'estado': 'NUEVO',
        'timestamp': UtcTimeUtils.nowIso(),
      });
      return true;
    } catch (e) {
      final isTipoConstraintError = e is PostgrestException &&
          (e.code == '23514' || e.message.contains('radio_mensajes_tipo_chk'));
      if (isTipoConstraintError && rawType != 'RADIO') {
        try {
          final fallbackId =
              'RADIO_${idOficial}_${DateTime.now().millisecondsSinceEpoch}_FB';
          await _supabase.from(SharedDb.tableRadioMensajes).insert({
            'id_mensaje': fallbackId,
            'id_oficial': idOficial,
            'de_usuario': fromUser,
            'para_usuario': toUser,
            'mensaje': '[$rawType] $cleanMessage',
            'tipo': 'RADIO',
            'estado': 'NUEVO',
            'timestamp': UtcTimeUtils.nowIso(),
          });
          debugPrint(
            'Supabase sendRadioMessage fallback applied: $rawType -> RADIO',
          );
          return true;
        } catch (fallbackError) {
          debugPrint(
            'Supabase sendRadioMessage fallback failed for $rawType: $fallbackError',
          );
        }
      }
      debugPrint('Supabase sendRadioMessage failed: $e');
      return false;
    }
  }

  Future<void> markRadioMessageRead(String idMensaje) async {
    try {
      await _supabase.from(SharedDb.tableRadioMensajes).update({
        'estado': 'LEIDO',
      }).eq('id_mensaje', idMensaje);
    } catch (_) {
      // Silencioso
    }
  }

  Future<List<RadioMessageModel>> getUnreadIncomingRadioMessages({
    required String idOficial,
    int limit = 20,
  }) async {
    try {
      final rows = await _supabase
          .from(SharedDb.tableRadioMensajes)
          .select()
          .eq('id_oficial', idOficial)
          .eq('para_usuario', idOficial)
          .order('timestamp', ascending: false)
          .limit(limit);

      return (rows as List)
          .map((json) => RadioMessageModel.fromJson(json))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getActiveOperationalSession(
    String idOficial,
  ) async {
    try {
      final rows = await _supabase
          .from('oficial_sesiones')
          .select()
          .eq('id_oficial', idOficial)
          .or('estado.eq.ACTIVA,estado.eq.active')
          .order('last_heartbeat', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        return (rows.first as Map).cast<String, dynamic>();
      }
      return null;
    } catch (e) {
      try {
        final rows = await _supabase
            .from('oficial_sesiones')
            .select()
            .eq('id_oficial', idOficial)
            .order('last_heartbeat', ascending: false)
            .limit(1);
        if (rows.isNotEmpty) {
          return (rows.first as Map).cast<String, dynamic>();
        }
      } catch (_) {}
      debugPrint('getActiveOperationalSession failed: $e');
      return null;
    }
  }

  String _normalizeLoginLogStatus(String status) {
    final raw = status.trim().toLowerCase();
    switch (raw) {
      case 'active':
      case 'login':
      case 'signed_in':
        return 'active';
      case 'logout':
      case 'signed_out':
        return 'logout';
      case 'expired':
      case 'off_shift':
      case 'shift_end':
        return 'expired';
      case 'forced':
      case 'permissions_missing':
      case 'session_replaced':
      case 'device_mismatch':
        return 'forced';
      default:
        return raw.isEmpty ? 'active' : 'forced';
    }
  }

  Future<bool> _tryInsertLoginLog({
    required String adminEmail,
    required String adminNombre,
    required String status,
    String? actorTipo,
    String? sessionId,
    String? deviceId,
    Map<String, dynamic>? metadata,
  }) async {
    final rawStatus = status.trim().toLowerCase();
    final normalizedStatus = _normalizeLoginLogStatus(rawStatus);
    final normalizedEmail = adminEmail.trim();
    if (normalizedEmail.isEmpty || normalizedStatus.isEmpty) return false;
    final nowIso = UtcTimeUtils.nowIso();
    final enrichedMetadata = <String, dynamic>{
      if (metadata != null) ...metadata,
      if (rawStatus.isNotEmpty && rawStatus != normalizedStatus)
        'raw_status': rawStatus,
    };

    try {
      await _supabase.from('login_logs').insert({
        'admin_email': normalizedEmail,
        'admin_nombre': adminNombre.trim().isEmpty ? null : adminNombre.trim(),
        'status': normalizedStatus,
        'timestamp': nowIso,
        if (actorTipo != null && actorTipo.trim().isNotEmpty)
          'actor_tipo': actorTipo.trim().toUpperCase(),
        if (sessionId != null && sessionId.trim().isNotEmpty)
          'session_id': sessionId.trim(),
        if (deviceId != null && deviceId.trim().isNotEmpty)
          'device_id': deviceId.trim().toUpperCase(),
        if (enrichedMetadata.isNotEmpty) 'metadata': enrichedMetadata,
      });
      return true;
    } catch (e) {
      debugPrint('login_logs insert full failed ($normalizedStatus): $e');
      try {
        // Compatibilidad con esquemas legacy sin columnas extendidas.
        await _supabase.from('login_logs').insert({
          'admin_email': normalizedEmail,
          'admin_nombre':
              adminNombre.trim().isEmpty ? null : adminNombre.trim(),
          'status': normalizedStatus,
          'timestamp': nowIso,
        });
        return true;
      } catch (inner) {
        debugPrint(
            'login_logs insert legacy failed ($normalizedStatus): $inner');
        return false;
      }
    }
  }

  Future<bool> registerOfficialLoginAudit({
    required String idOficial,
    required String nombreOficial,
    required String deviceId,
    String source = 'auth_login',
  }) async {
    return _tryInsertLoginLog(
      adminEmail: idOficial,
      adminNombre: nombreOficial,
      status: 'active',
      actorTipo: 'OFICIAL',
      deviceId: deviceId,
      metadata: {'source': source},
    );
  }

  Future<String?> openOperationalSession({
    required String idOficial,
    required String nombreOficial,
    required String deviceId,
    bool recordLoginLog = false,
  }) async {
    try {
      final normalizedDevice = deviceId.trim().toUpperCase();
      final nowIso = UtcTimeUtils.nowIso();
      final active = await getActiveOperationalSession(idOficial);

      final activeDevice =
          active?['device_id']?.toString().trim().toUpperCase();
      if (active != null &&
          activeDevice != null &&
          activeDevice == normalizedDevice) {
        final sessionId = active['id_sesion']?.toString();
        if (sessionId != null && sessionId.isNotEmpty) {
          try {
            await _supabase.from('oficial_sesiones').update({
              'last_heartbeat': nowIso,
              'estado': 'ACTIVA',
              'logout_at': null,
            }).eq('id_sesion', sessionId);
          } catch (_) {
            await _supabase.from('oficial_sesiones').update({
              'last_heartbeat': nowIso,
              'logout_at': null,
            }).eq('id_sesion', sessionId);
          }
          if (recordLoginLog) {
            await _tryInsertLoginLog(
              adminEmail: idOficial,
              adminNombre: nombreOficial,
              status: 'active',
              actorTipo: 'OFICIAL',
              sessionId: sessionId,
              deviceId: normalizedDevice,
              metadata: {'source': 'openOperationalSession:update_active'},
            );
          }
          return sessionId;
        }
      }

      final sameDeviceRows = await _supabase
          .from('oficial_sesiones')
          .select('id_sesion')
          .eq('id_oficial', idOficial)
          .eq('device_id', normalizedDevice)
          .order('last_heartbeat', ascending: false)
          .limit(1);
      if (sameDeviceRows.isNotEmpty) {
        final sessionId =
            (sameDeviceRows.first as Map)['id_sesion']?.toString();
        if (sessionId != null && sessionId.isNotEmpty) {
          try {
            await _supabase.from('oficial_sesiones').update({
              'estado': 'ACTIVA',
              'login_at': nowIso,
              'last_heartbeat': nowIso,
              'logout_at': null,
            }).eq('id_sesion', sessionId);
          } catch (_) {
            await _supabase.from('oficial_sesiones').update({
              'login_at': nowIso,
              'last_heartbeat': nowIso,
              'logout_at': null,
            }).eq('id_sesion', sessionId);
          }
          if (recordLoginLog) {
            await _tryInsertLoginLog(
              adminEmail: idOficial,
              adminNombre: nombreOficial,
              status: 'active',
              actorTipo: 'OFICIAL',
              sessionId: sessionId,
              deviceId: normalizedDevice,
              metadata: {'source': 'openOperationalSession:reuse_device'},
            );
          }
          return sessionId;
        }
      }

      Map<String, dynamic>? inserted;
      try {
        inserted = await _supabase
            .from('oficial_sesiones')
            .insert({
              'id_oficial': idOficial,
              'device_id': normalizedDevice,
              'estado': 'ACTIVA',
              'login_at': nowIso,
              'last_heartbeat': nowIso,
              'logout_at': null,
            })
            .select('id_sesion')
            .maybeSingle();
      } catch (_) {
        try {
          inserted = await _supabase
              .from('oficial_sesiones')
              .insert({
                'id_oficial': idOficial,
                'device_id': normalizedDevice,
                'login_at': nowIso,
                'last_heartbeat': nowIso,
                'logout_at': null,
              })
              .select('id_sesion')
              .maybeSingle();
        } catch (_) {
          final existingRows = await _supabase
              .from('oficial_sesiones')
              .select('id_sesion')
              .eq('id_oficial', idOficial)
              .order('last_heartbeat', ascending: false)
              .limit(1);
          if (existingRows.isNotEmpty) {
            final existingId =
                (existingRows.first as Map)['id_sesion']?.toString();
            if (existingId != null && existingId.isNotEmpty) {
              await _supabase.from('oficial_sesiones').update({
                'device_id': normalizedDevice,
                'login_at': nowIso,
                'last_heartbeat': nowIso,
                'logout_at': null,
              }).eq('id_sesion', existingId);
              inserted = {'id_sesion': existingId};
            }
          }
        }
      }
      final sessionId = inserted?['id_sesion']?.toString();

      if (recordLoginLog) {
        await _tryInsertLoginLog(
          adminEmail: idOficial,
          adminNombre: nombreOficial,
          status: 'active',
          actorTipo: 'OFICIAL',
          sessionId: sessionId,
          deviceId: normalizedDevice,
          metadata: {'source': 'openOperationalSession:insert_new'},
        );
      }

      return sessionId;
    } catch (e) {
      debugPrint('openOperationalSession failed: $e');
      try {
        final normalizedDevice = deviceId.trim().toUpperCase();
        final nowIso = UtcTimeUtils.nowIso();
        Map<String, dynamic>? fallback;
        try {
          fallback = await _supabase
              .from('oficial_sesiones')
              .insert({
                'id_oficial': idOficial,
                'device_id': normalizedDevice,
                'estado': 'active',
                'login_at': nowIso,
                'last_heartbeat': nowIso,
                'logout_at': null,
              })
              .select('id_sesion')
              .maybeSingle();
        } catch (_) {
          final existingRows = await _supabase
              .from('oficial_sesiones')
              .select('id_sesion')
              .eq('id_oficial', idOficial)
              .order('last_heartbeat', ascending: false)
              .limit(1);
          if (existingRows.isNotEmpty) {
            final existingId =
                (existingRows.first as Map)['id_sesion']?.toString();
            if (existingId != null && existingId.isNotEmpty) {
              await _supabase.from('oficial_sesiones').update({
                'device_id': normalizedDevice,
                'login_at': nowIso,
                'last_heartbeat': nowIso,
                'logout_at': null,
              }).eq('id_sesion', existingId);
              fallback = {'id_sesion': existingId};
            }
          }
        }
        final fallbackId = fallback?['id_sesion']?.toString();
        if (recordLoginLog) {
          await _tryInsertLoginLog(
            adminEmail: idOficial,
            adminNombre: nombreOficial,
            status: 'active',
            actorTipo: 'OFICIAL',
            sessionId: fallbackId,
            deviceId: normalizedDevice,
            metadata: {'source': 'openOperationalSession:fallback_insert'},
          );
        }
        return fallbackId;
      } catch (inner) {
        debugPrint('openOperationalSession fallback failed: $inner');
        return null;
      }
    }
  }

  Future<void> heartbeatOperationalSession({
    required String idOficial,
    required String deviceId,
  }) async {
    try {
      final normalizedDevice = deviceId.trim().toUpperCase();
      List<dynamic> updated = const [];
      try {
        updated = await _supabase
            .from('oficial_sesiones')
            .update({
              'last_heartbeat': UtcTimeUtils.nowIso(),
              'estado': 'ACTIVA',
            })
            .eq('id_oficial', idOficial)
            .eq('device_id', normalizedDevice)
            .or('estado.eq.ACTIVA,estado.eq.active')
            .select('id_sesion');
      } catch (_) {
        updated = await _supabase
            .from('oficial_sesiones')
            .update({
              'last_heartbeat': UtcTimeUtils.nowIso(),
            })
            .eq('id_oficial', idOficial)
            .eq('device_id', normalizedDevice)
            .select('id_sesion');
      }
      if (updated.isNotEmpty) {
        return;
      }
      await openOperationalSession(
        idOficial: idOficial,
        nombreOficial: idOficial,
        deviceId: normalizedDevice,
      );
    } catch (e) {
      debugPrint('heartbeatOperationalSession failed: $e');
    }
  }

  Future<void> closeOperationalSession({
    required String idOficial,
    required String deviceId,
    required String status,
    required int durationMinutes,
  }) async {
    try {
      final normalizedDevice = deviceId.trim().toUpperCase();
      try {
        await _supabase
            .from('oficial_sesiones')
            .update({
              'estado': status == 'logout' ? 'CERRADA' : 'EXPIRADA',
              'logout_at': UtcTimeUtils.nowIso(),
              'last_heartbeat': UtcTimeUtils.nowIso(),
            })
            .eq('id_oficial', idOficial)
            .eq('device_id', normalizedDevice);
      } catch (_) {
        await _supabase
            .from('oficial_sesiones')
            .update({
              'logout_at': UtcTimeUtils.nowIso(),
              'last_heartbeat': UtcTimeUtils.nowIso(),
            })
            .eq('id_oficial', idOficial)
            .eq('device_id', normalizedDevice);
      }
    } catch (e) {
      debugPrint('closeOperationalSession failed: $e');
    }

    try {
      await _tryInsertLoginLog(
        adminEmail: idOficial,
        adminNombre: 'Oficial',
        status: status,
        actorTipo: 'OFICIAL',
        deviceId: deviceId,
        metadata: {'duracion_minutos': durationMinutes},
      );
    } catch (_) {
      // Silencioso
    }
  }

  Future<Map<String, dynamic>> getMonitoringTrendSnapshot({
    required String idOficial,
    DateTime? now,
    Duration lookback = const Duration(hours: 3),
    int reportLimit = 90,
  }) async {
    final current = now ?? DateTime.now();
    final start = current.subtract(lookback);

    List<Map<String, dynamic>> reportes = const [];
    int inconsistencias = 0;
    int partes = 0;

    try {
      final rows = await _supabase
          .from('monitoreo_reportes')
          .select(
              'fecha_hora,distancia_metros,nivel_bateria,gps_real,estado_alerta,latitud,longitud')
          .eq('id_oficial_ref', idOficial)
          .gte('fecha_hora', UtcTimeUtils.iso(start))
          .lt('fecha_hora', UtcTimeUtils.iso(current))
          .order('fecha_hora', ascending: false)
          .limit(reportLimit);
      reportes = (rows as List).cast<Map<String, dynamic>>();
    } catch (_) {
      reportes = const [];
    }

    try {
      final rows = await _supabase
          .from('inconsistencias')
          .select('id_inconsistencia')
          .eq('id_oficial', idOficial)
          .gte('fecha_deteccion', UtcTimeUtils.iso(start))
          .lt('fecha_deteccion', UtcTimeUtils.iso(current));
      inconsistencias = (rows as List).length;
    } catch (_) {
      inconsistencias = 0;
    }

    try {
      final rows = await _supabase
          .from('partes_oficiales')
          .select('id_reporte')
          .eq('id_oficial', idOficial)
          .not('id_reporte', 'like', 'VOZ_%')
          .gte('timestamp', UtcTimeUtils.iso(start))
          .lt('timestamp', UtcTimeUtils.iso(current));
      partes = (rows as List).length;
    } catch (_) {
      partes = 0;
    }

    return {
      'reportes': reportes,
      'inconsistencias': inconsistencias,
      'partes': partes,
    };
  }

  Future<Map<String, int>> getTodayOperationalSummary({
    required String idOficial,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final dayAnchor = ParteScheduleUtils.operationalDayAnchor(current);
    final start = DateTime(
      dayAnchor.year,
      dayAnchor.month,
      dayAnchor.day,
      ParteScheduleUtils.firstSlotHour,
    );
    final end = start.add(const Duration(days: 1));

    int reportes = 0;
    int alertas = 0;
    int inconsistencias = 0;
    int partes = 0;

    try {
      final rows = await _supabase
          .from('monitoreo_reportes')
          .select('estado_alerta')
          .eq('id_oficial_ref', idOficial)
          .gte('fecha_hora', UtcTimeUtils.iso(start))
          .lt('fecha_hora', UtcTimeUtils.iso(end));

      final parsed = (rows as List).cast<Map<String, dynamic>>();
      reportes = parsed.length;
      alertas = parsed
          .where(
              (r) => (r['estado_alerta']?.toString() ?? 'NORMAL') != 'NORMAL')
          .length;
    } catch (_) {
      // Silencioso
    }

    try {
      final rows = await _supabase
          .from('inconsistencias')
          .select('id_inconsistencia')
          .eq('id_oficial', idOficial)
          .gte('fecha_deteccion', UtcTimeUtils.iso(start))
          .lt('fecha_deteccion', UtcTimeUtils.iso(end));
      inconsistencias = (rows as List).length;
    } catch (_) {
      // Silencioso
    }

    try {
      final rows = await _supabase
          .from('partes_oficiales')
          .select('id_reporte')
          .eq('id_oficial', idOficial)
          .not('id_reporte', 'like', 'VOZ_%')
          .gte('timestamp', UtcTimeUtils.iso(start))
          .lt('timestamp', UtcTimeUtils.iso(end));
      partes = (rows as List).length;
    } catch (_) {
      // Silencioso
    }

    return {
      'reportes': reportes,
      'alertas': alertas,
      'inconsistencias': inconsistencias,
      'partes': partes,
    };
  }
}
