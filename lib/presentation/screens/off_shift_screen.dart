import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/huc_background.dart';
import '../widgets/hud_screen_entry.dart';

class OffShiftScreen extends StatelessWidget {
  const OffShiftScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HucBackground(
        child: SafeArea(
          child: HudScreenEntry(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: GlassPanel(
                    borderRadius: BorderRadius.circular(24),
                    child: Consumer<AuthProvider>(
                      builder: (context, auth, _) {
                        final official = auth.oficial;
                        final groupLabel =
                            official?.grupo.toUpperCase() ?? '--';
                        final shift = official?.turno?.trim().isNotEmpty == true
                            ? official!.turno!
                            : 'Sin turno configurado';
                        final remaining = auth.timeToNextShift;
                        final countdown = remaining == null
                            ? '--'
                            : _formatDuration(remaining);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'FUERA DE TURNO',
                              style: TextStyle(
                                fontFamily: 'Orbitron',
                                color: AppTheme.warning,
                                fontSize: 20,
                                letterSpacing: 1.0,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Grupo $groupLabel en descanso. Monitoreo desactivado hasta el inicio de turno.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _infoRow('Oficial', official?.nombre ?? '--'),
                            _infoRow('ID', official?.id ?? '--'),
                            _infoRow('Grupo', groupLabel),
                            _infoRow('Turno', shift),
                            _infoRow('Inicio estimado', countdown),
                            const SizedBox(height: 14),
                            Text(
                              'La sesión queda controlada por sistema hasta el próximo turno.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.68),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final totalMinutes = duration.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m';
  }
}
