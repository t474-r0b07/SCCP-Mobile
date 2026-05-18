import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/radio_message_model.dart';
import '../../data/services/radio_rtc_signaling.dart';
import '../providers/auth_provider.dart';
import '../providers/radio_provider.dart';
import '../widgets/huc_background.dart';
import '../widgets/hud_screen_entry.dart';

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final _inputController = TextEditingController();
  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  bool _isListening = false;
  bool _isSendingVoice = false;
  String _voiceDraft = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      final radio = context.read<RadioProvider>();
      final officialId = auth.oficial?.id;
      if (officialId != null && officialId.isNotEmpty) {
        radio.start(officialId);
        await radio.markIncomingRead();
      }
      await _initSpeech();
    });
  }

  @override
  void dispose() {
    _speech.stop();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final officialName = auth.oficial?.nombre ?? 'Oficial';

    return Scaffold(
      appBar: AppBar(
        title: const Text('RADIO OPERATIVA'),
      ),
      body: HucBackground(
        child: SafeArea(
          child: HudScreenEntry(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: _buildTopPanel(officialName),
                ),
                Expanded(
                  child: Consumer<RadioProvider>(
                    builder: (context, radio, _) {
                      final visibleMessages = radio.messages
                          .where((m) => !RadioRtcSignal.isRtcPayload(m.message))
                          .toList();
                      if (visibleMessages.isEmpty) {
                        return Center(
                          child: Text(
                            'Sin tráfico de radio',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        itemCount: visibleMessages.length,
                        itemBuilder: (context, i) {
                          final msg = visibleMessages[i];
                          return _buildMessageBubble(msg, officialName);
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: _buildComposer(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopPanel(String officialName) {
    return Consumer<RadioProvider>(
      builder: (context, radio, _) {
        return GlassPanel(
          borderRadius: BorderRadius.circular(14),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.settings_input_antenna,
                    color:
                        radio.isConnected ? AppTheme.success : AppTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      radio.isConnected
                          ? 'Canal supervisor disponible'
                          : 'Conectando canal supervisor...',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (radio.unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: AppTheme.error.withValues(alpha: 0.9),
                      ),
                      child: Text(
                        '${radio.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              if (radio.errorMessage != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppTheme.error, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        radio.errorMessage!,
                        style: const TextStyle(
                          color: AppTheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (radio.incomingCallActive) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.error.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    'LLAMADA DE RADIO ENTRANTE',
                    style: const TextStyle(
                      color: AppTheme.error,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      fontFamily: 'Orbitron',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => context
                            .read<RadioProvider>()
                            .acceptIncomingRtcCall(),
                        icon: const Icon(Icons.call, size: 16),
                        label: const Text('ACEPTAR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => context
                            .read<RadioProvider>()
                            .rejectIncomingRtcCall(),
                        icon: const Icon(Icons.call_end, size: 16),
                        label: const Text('RECHAZAR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.error,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (radio.rtcCallActive) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.success.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    radio.rtcStatus ?? 'LLAMADA EN CURSO',
                    style: const TextStyle(
                      color: AppTheme.success,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      fontFamily: 'Orbitron',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => context.read<RadioProvider>().endRtcCall(),
                    icon: const Icon(Icons.call_end, size: 16),
                    label: const Text('FINALIZAR LLAMADA'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.read<RadioProvider>().sendToSupervisor(
                                'Consulta operativa desde $officialName',
                                type: 'CONSULTA',
                              ),
                      icon: const Icon(Icons.support_agent, size: 18),
                      label: const Text('CONSULTA'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          context.read<RadioProvider>().sendEmergencyPing(),
                      icon: const Icon(Icons.warning_amber, size: 18),
                      label: const Text('EMERGENCIA'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.error,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageBubble(RadioMessageModel msg, String officialName) {
    final outgoing = msg.fromUser.toUpperCase() != 'SUPERVISOR';
    final isVoice = msg.message.trimLeft().toUpperCase().startsWith('VOZ:');
    final type = msg.type.trim().toUpperCase();
    final isCallEvent = type == 'CALL_START' || type == 'CALL_END';
    final bubbleColor = outgoing
        ? AppTheme.primary.withValues(alpha: 0.2)
        : isCallEvent
            ? AppTheme.error.withValues(alpha: 0.2)
            : const Color(0x33FFAA00);

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: outgoing
                ? AppTheme.primary.withValues(alpha: 0.38)
                : AppTheme.warning.withValues(alpha: 0.38),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              outgoing ? officialName : 'SUPERVISOR',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCallEvent) ...[
                  Icon(
                    type == 'CALL_START'
                        ? Icons.record_voice_over_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 14,
                    color: type == 'CALL_START'
                        ? AppTheme.error
                        : AppTheme.warning,
                  ),
                  const SizedBox(width: 4),
                ] else if (isVoice) ...[
                  const Icon(Icons.mic, size: 14, color: AppTheme.warning),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    msg.message,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(msg.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return GlassPanel(
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        children: [
          if (_isListening || _voiceDraft.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _isListening
                      ? 'Capturando voz... ${_voiceDraft.isEmpty ? "" : _voiceDraft}'
                      : 'Borrador voz: $_voiceDraft',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _isListening
                        ? AppTheme.warning
                        : Colors.white.withValues(alpha: 0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  decoration: const InputDecoration(
                    hintText: 'Mensaje breve por radio...',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: _isListening ? 'Detener voz' : 'Radio voz',
                onPressed: (!_speechReady || _isSendingVoice)
                    ? null
                    : _toggleVoiceCapture,
                icon: Icon(
                  _isListening ? Icons.stop_circle : Icons.mic,
                  color: _isListening ? AppTheme.error : AppTheme.warning,
                ),
              ),
              IconButton(
                onPressed: _sendMessage,
                icon: const Icon(Icons.send, color: AppTheme.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    await context.read<RadioProvider>().sendToSupervisor(text, type: 'RADIO');
  }

  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (status) {
          final listening = status == 'listening';
          if (!mounted) return;
          if (status.toLowerCase() == 'notlistening' &&
              _voiceDraft.trim().isNotEmpty &&
              !_isSendingVoice) {
            unawaited(_sendVoiceMessage());
          }
          if (_isListening != listening) {
            setState(() => _isListening = listening);
          }
        },
      );
      if (!mounted) return;
      setState(() => _speechReady = ok);
    } catch (_) {
      if (!mounted) return;
      setState(() => _speechReady = false);
    }
  }

  Future<void> _toggleVoiceCapture() async {
    if (_isListening) {
      await _stopVoiceCapture();
      return;
    }
    await _startVoiceCapture();
  }

  Future<void> _startVoiceCapture() async {
    if (!_speechReady || _isSendingVoice) return;
    setState(() {
      _voiceDraft = '';
      _isListening = true;
    });

    try {
      await _speech.listen(
        listenFor: const Duration(seconds: 16),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(partialResults: true),
        localeId: 'es_ES',
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _voiceDraft = result.recognizedWords.trim();
          });
        },
      );
    } catch (_) {
      try {
        await _speech.listen(
          listenFor: const Duration(seconds: 16),
          pauseFor: const Duration(seconds: 4),
          listenOptions: SpeechListenOptions(partialResults: true),
          onResult: (result) {
            if (!mounted) return;
            setState(() {
              _voiceDraft = result.recognizedWords.trim();
            });
          },
        );
      } catch (_) {
        if (!mounted) return;
        setState(() => _isListening = false);
      }
    }
  }

  Future<void> _stopVoiceCapture() async {
    if (!_isListening) return;
    await _speech.stop();
    if (!mounted) return;
    setState(() => _isListening = false);
    await _sendVoiceMessage();
  }

  Future<void> _sendVoiceMessage() async {
    final transcript = _voiceDraft.trim();
    if (transcript.isEmpty || _isSendingVoice) return;
    setState(() => _isSendingVoice = true);
    await context.read<RadioProvider>().sendVoiceToSupervisor(transcript);
    if (!mounted) return;
    setState(() {
      _isSendingVoice = false;
      _voiceDraft = '';
    });
  }

  String _formatTime(DateTime ts) {
    final local = ts.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
