import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/models/radio_message_model.dart';
import '../../data/repositories/supabase_repository.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/radio_rtc_engine.dart';
import '../../data/services/radio_rtc_signaling.dart';

class RadioProvider with ChangeNotifier {
  final SupabaseRepository _repository = SupabaseRepository();

  StreamSubscription<List<RadioMessageModel>>? _messagesSub;
  Timer? _reconnectTimer;
  List<RadioMessageModel> _messages = const [];
  String? _activeOfficialId;
  String? _errorMessage;
  bool _isConnected = false;
  String? _lastNotifiedMessageId;
  final Set<String> _processedRtcMessageIds = <String>{};

  RadioRtcEngine? _rtcEngine;
  String? _rtcCallId;
  String? _rtcPeerUser;
  String? _rtcStatus;
  RadioRtcSignal? _pendingOffer;
  bool _rtcIncomingRinging = false;
  bool _rtcConnected = false;
  bool _rtcTerminating = false;
  bool _rtcAcceptingIncoming = false;

  List<RadioMessageModel> get messages => _messages;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _isConnected;
  bool get incomingCallActive => _rtcIncomingRinging;
  DateTime? get incomingCallStartedAt => null;
  bool get rtcCallActive => _rtcCallId != null;
  bool get rtcCallConnected => _rtcConnected;
  String? get rtcStatus => _rtcStatus;

  int get unreadCount => _messages
      .where((m) => m.isIncomingFromSupervisor && m.status == 'NUEVO')
      .where((m) => !RadioRtcSignal.isRtcPayload(m.message))
      .length;

  void start(String idOficial, {bool forceReconnect = false}) {
    final normalizedId = idOficial.trim();
    if (normalizedId.isEmpty) return;

    final sameOfficial = _activeOfficialId == normalizedId;
    final alreadyConnected =
        sameOfficial && _messagesSub != null && _isConnected;
    if (!forceReconnect && alreadyConnected) return;

    _activeOfficialId = normalizedId;
    _connectCurrentOfficial(resetMessages: !sameOfficial);
  }

  void _connectCurrentOfficial({bool resetMessages = false}) {
    final officialId = _activeOfficialId;
    if (officialId == null || officialId.isEmpty) return;

    _reconnectTimer?.cancel();
    _messagesSub?.cancel();
    _messagesSub = null;

    if (resetMessages) {
      _messages = const [];
    }
    _isConnected = false;
    _errorMessage = null;
    notifyListeners();

    _messagesSub = _repository.watchRadioMessages(officialId).listen(
      (rows) {
        _messages = rows;
        unawaited(_processRtcSignals(rows));
        unawaited(_notifyIncomingRadioIfNeeded(rows));
        _isConnected = true;
        _errorMessage = null;
        _reconnectTimer?.cancel();
        notifyListeners();
      },
      onError: (error, _) {
        _messagesSub?.cancel();
        _messagesSub = null;
        _isConnected = false;
        _errorMessage = 'Radio no disponible (${_compactError(error)})';
        _scheduleReconnect();
        notifyListeners();
      },
      onDone: () {
        _messagesSub = null;
        if (_activeOfficialId == null) return;
        _isConnected = false;
        _errorMessage = 'Radio reconectando...';
        _scheduleReconnect();
        notifyListeners();
      },
    );
  }

  void _scheduleReconnect() {
    if (_activeOfficialId == null) return;
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_activeOfficialId == null) {
        timer.cancel();
        return;
      }
      if (_messagesSub != null && _isConnected) {
        timer.cancel();
        return;
      }
      _connectCurrentOfficial();
    });
  }

  String _compactError(Object error) {
    final text = error.toString().replaceAll('\n', ' ').trim();
    if (text.isEmpty) return 'sin detalle';
    return text.length <= 70 ? text : '${text.substring(0, 70)}...';
  }

  Future<void> sendToSupervisor(
    String message, {
    String type = 'CONSULTA',
  }) async {
    final id = _activeOfficialId;
    if (id == null || message.trim().isEmpty) return;

    final ok = await _repository.sendRadioMessage(
      idOficial: id,
      fromUser: id,
      toUser: 'SUPERVISOR',
      message: message.trim(),
      type: type,
    );
    if (!ok) {
      _errorMessage =
          'No se pudo enviar radio a base de datos. Revisa politicas RLS/permisos.';
      notifyListeners();
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> sendEmergencyPing() async {
    await sendToSupervisor(
      'Solicitud inmediata por canal de radio',
      type: 'EMERGENCIA',
    );
  }

  Future<void> sendVoiceToSupervisor(String transcript) async {
    final text = transcript.trim();
    if (text.isEmpty) return;
    await sendToSupervisor(
      'VOZ: $text',
      type: 'RADIO',
    );
  }

  Future<void> markIncomingRead() async {
    final pending = _messages
        .where((m) => m.isIncomingFromSupervisor && m.status == 'NUEVO')
        .where((m) => !RadioRtcSignal.isRtcPayload(m.message))
        .toList();
    for (final msg in pending) {
      await _repository.markRadioMessageRead(msg.id);
    }
  }

  Future<void> acceptIncomingRtcCall() async {
    final signal = _pendingOffer;
    if (signal == null || _rtcAcceptingIncoming) return;
    _rtcAcceptingIncoming = true;

    try {
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final requested = await Permission.microphone.request();
        if (!requested.isGranted) {
          _rtcStatus = 'Micrófono denegado';
          _errorMessage =
              'No se puede iniciar llamada sin permiso de micrófono.';
          notifyListeners();
          return;
        }
      }

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final btStatus = await Permission.bluetoothConnect.status;
        if (!btStatus.isGranted) {
          final btRequested = await Permission.bluetoothConnect.request();
          if (!btRequested.isGranted) {
            _rtcStatus = 'Bluetooth denegado';
            _errorMessage =
                'Activa permiso Bluetooth para estabilizar audio de llamada.';
            notifyListeners();
            return;
          }
        }
      }

      await _ensureRtcEngine(
        callId: signal.callId,
        peerUser: signal.fromUser,
        resetExisting: true,
      );
      await _rtcEngine!.applyRemoteOffer(signal.data);
      final answer = await _rtcEngine!.createAnswer();
      await _sendRtcSignal(
        RadioRtcSignal(
          action: RadioRtcSignal.answer,
          callId: signal.callId,
          fromUser: _activeOfficialId ?? '',
          toUser: signal.fromUser,
          data: answer,
        ),
      );

      _pendingOffer = null;
      _rtcIncomingRinging = false;
      _rtcStatus = 'Conectando audio...';
      notifyListeners();
    } catch (e) {
      _rtcStatus = 'Error al aceptar llamada';
      _errorMessage = 'Llamada RTC fallida: ${_compactError(e)}';
      notifyListeners();
      await endRtcCall(notifyRemote: false);
    } finally {
      _rtcAcceptingIncoming = false;
    }
  }

  Future<void> rejectIncomingRtcCall() async {
    final signal = _pendingOffer;
    if (signal != null) {
      await _sendRtcSignal(
        RadioRtcSignal(
          action: RadioRtcSignal.reject,
          callId: signal.callId,
          fromUser: _activeOfficialId ?? '',
          toUser: signal.fromUser,
          data: const <String, dynamic>{'reason': 'RECHAZADA'},
        ),
      );
    }
    _pendingOffer = null;
    _rtcIncomingRinging = false;
    _rtcStatus = 'Llamada rechazada';
    _rtcCallId = null;
    _rtcPeerUser = null;
    notifyListeners();
  }

  Future<void> endRtcCall({bool notifyRemote = true}) async {
    if (_rtcTerminating) return;
    _rtcTerminating = true;
    final callId = _rtcCallId;
    final peer = _rtcPeerUser;
    try {
      if (notifyRemote && callId != null && peer != null && peer.isNotEmpty) {
        await _sendRtcSignal(
          RadioRtcSignal(
            action: RadioRtcSignal.hangup,
            callId: callId,
            fromUser: _activeOfficialId ?? '',
            toUser: peer,
          ),
        );
      }

      await _rtcEngine?.close();
      _rtcEngine = null;
      _rtcCallId = null;
      _rtcPeerUser = null;
      _rtcConnected = false;
      _rtcIncomingRinging = false;
      _pendingOffer = null;
      _rtcStatus = null;
      notifyListeners();
    } finally {
      _rtcTerminating = false;
    }
  }

  Future<void> _ensureRtcEngine({
    required String callId,
    required String peerUser,
    bool resetExisting = false,
  }) async {
    if (resetExisting && _rtcEngine != null) {
      try {
        await _rtcEngine?.close();
      } catch (_) {}
      _rtcEngine = null;
    }
    _rtcCallId = callId;
    _rtcPeerUser = peerUser;
    _rtcStatus = 'Inicializando audio...';
    _rtcConnected = false;

    _rtcEngine ??= RadioRtcEngine(
      onLocalIceCandidate: (candidate) {
        final id = _rtcCallId;
        final peer = _rtcPeerUser;
        final me = _activeOfficialId;
        if (id == null || peer == null || me == null) return;
        unawaited(
          _sendRtcSignal(
            RadioRtcSignal(
              action: RadioRtcSignal.ice,
              callId: id,
              fromUser: me,
              toUser: peer,
              data: RadioRtcEngine.serializeIceCandidate(candidate),
            ),
          ),
        );
      },
      onConnectionState: (state) {
        if (_rtcTerminating) return;
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _rtcConnected = true;
            _rtcStatus = 'Llamada conectada';
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
            _rtcStatus = 'Conectando audio...';
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            _rtcConnected = false;
            _rtcStatus = 'Error de conexión';
            unawaited(_terminateRtcFromState());
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            _rtcConnected = false;
            _rtcStatus = 'Llamada finalizada';
            unawaited(_terminateRtcFromState());
            break;
          default:
            break;
        }
        notifyListeners();
      },
    );

    await _rtcEngine!.initialize();
  }

  Future<void> _terminateRtcFromState() async {
    if (_rtcTerminating) return;
    await endRtcCall(notifyRemote: false);
  }

  Future<void> _processRtcSignals(List<RadioMessageModel> rows) async {
    final officialId = _activeOfficialId;
    if (officialId == null || officialId.isEmpty) return;

    final ordered = rows.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    for (final msg in ordered) {
      if (_processedRtcMessageIds.contains(msg.id)) continue;
      final signal = RadioRtcSignal.tryParse(msg.message);
      if (signal == null) continue;
      _processedRtcMessageIds.add(msg.id);

      final target = signal.toUser.trim().toUpperCase();
      if (target != officialId.toUpperCase()) continue;

      await _handleRtcSignal(signal);
    }
  }

  Future<void> _handleRtcSignal(RadioRtcSignal signal) async {
    switch (signal.action) {
      case RadioRtcSignal.offer:
        _pendingOffer = signal;
        _rtcIncomingRinging = true;
        _rtcCallId = signal.callId;
        _rtcPeerUser = signal.fromUser;
        _rtcStatus = 'Llamada entrante';
        notifyListeners();
        await NotificationService.showRadioMessageAlert(
          fromUser: signal.fromUser,
          message: 'Llamada de radio entrante',
          type: 'CALL_START',
        );
        break;

      case RadioRtcSignal.answer:
        await _rtcEngine?.applyRemoteAnswer(signal.data);
        _rtcStatus = 'Conectando audio...';
        notifyListeners();
        break;

      case RadioRtcSignal.ice:
        if (_rtcCallId != signal.callId) return;
        await _rtcEngine?.addRemoteIceCandidate(signal.data);
        break;

      case RadioRtcSignal.hangup:
      case RadioRtcSignal.reject:
        if (_rtcCallId == signal.callId ||
            _pendingOffer?.callId == signal.callId) {
          _rtcStatus = signal.action == RadioRtcSignal.reject
              ? 'Llamada rechazada por supervisor'
              : 'Supervisor finalizó llamada';
          notifyListeners();
          await endRtcCall(notifyRemote: false);
        }
        break;
    }
  }

  Future<bool> _sendRtcSignal(RadioRtcSignal signal) async {
    final officialId = _activeOfficialId;
    if (officialId == null || officialId.isEmpty) return false;
    return _repository.sendRadioMessage(
      idOficial: officialId,
      fromUser: signal.fromUser,
      toUser: signal.toUser,
      message: signal.encode(),
      type: 'RADIO',
    );
  }

  void stop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _messagesSub?.cancel();
    _messagesSub = null;
    _messages = const [];
    _activeOfficialId = null;
    _lastNotifiedMessageId = null;
    _isConnected = false;
    _errorMessage = null;
    _processedRtcMessageIds.clear();
    unawaited(endRtcCall(notifyRemote: false));
    notifyListeners();
  }

  Future<void> _notifyIncomingRadioIfNeeded(
    List<RadioMessageModel> rows,
  ) async {
    if (rows.isEmpty) return;
    final incomingUnread = rows
        .where((m) => m.isIncomingFromSupervisor && m.status == 'NUEVO')
        .where((m) => !RadioRtcSignal.isRtcPayload(m.message))
        .toList();
    if (incomingUnread.isEmpty) return;

    final latest = incomingUnread.last;
    if (_lastNotifiedMessageId == latest.id) return;
    _lastNotifiedMessageId = latest.id;

    await NotificationService.showRadioMessageAlert(
      fromUser: latest.fromUser,
      message: latest.message,
      type: latest.type,
    );
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _messagesSub?.cancel();
    unawaited(endRtcCall(notifyRemote: false));
    super.dispose();
  }
}
