package com.sccp.mobile

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.AlarmManager
import android.app.PendingIntent
import android.os.Build
import androidx.core.content.ContextCompat

class ServiceRestarterReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (!supportedActions.contains(action)) return

        val appContext = context.applicationContext
        val now = System.currentTimeMillis()
        recordNativeDiag(
            context = appContext,
            updates = mapOf(
                KEY_LAST_RX_AT to now.toString(),
                KEY_LAST_ACTION to action,
            ),
            incrementCounter = true
        )
        // No arrancar el servicio foreground directo desde receiver:
        val alreadyRunning = isBackgroundServiceRunning(appContext)
        val dartLastTickMs = readLongPref(appContext, KEY_DART_LAST_TICK_MS)
        val dartTickAgeMs = if (dartLastTickMs == null || dartLastTickMs <= 0L) {
            Long.MAX_VALUE
        } else {
            now - dartLastTickMs
        }
        val dartStale = dartTickAgeMs > DART_STALE_THRESHOLD_MS
        val fromFallback = action == ACTION_RESTART_BG_SERVICE_FALLBACK

        val (startStatus, startError) = when {
            !alreadyRunning -> ensureBackgroundServiceRunning(appContext, forceRestart = false)
            dartStale -> ensureBackgroundServiceRunning(appContext, forceRestart = true)
            fromFallback -> Pair("FALLBACK_HEALTHY", "")
            else -> Pair("ALREADY_RUNNING", "")
        }

        recordNativeDiag(
            context = appContext,
            updates = mapOf(
                KEY_LAST_START_STATUS to startStatus,
                KEY_LAST_START_ERROR to startError,
            )
        )

        // Reprograma chequeo cada vez que dispara el receiver para mantener
        // watchdog encadenado incluso en bloqueo/idle profundo.
        scheduleNextHealthCheck(appContext, NEXT_CHECK_DELAY_MS)
        scheduleFallbackRepeating(appContext)
    }

    companion object {
        const val ACTION_RESTART_BG_SERVICE = "com.sccp.mobile.action.RESTART_BG_SERVICE"
        private const val ACTION_RESTART_BG_SERVICE_FALLBACK = "com.sccp.mobile.action.RESTART_BG_SERVICE_FALLBACK"
        private const val PERIODIC_REQUEST_CODE = 990062
        private const val FALLBACK_REQUEST_CODE = 990063
        private const val INITIAL_CHECK_DELAY_MS = 15_000L
        private const val NEXT_CHECK_DELAY_MS = 60 * 1000L
        private const val FALLBACK_REPEAT_INTERVAL_MS = 60 * 1000L
        private const val PREFS_FILE = "FlutterSharedPreferences"
        private const val KEY_LAST_RX_AT = "flutter.bg_native_last_rx_at"
        private const val KEY_LAST_ACTION = "flutter.bg_native_last_action"
        private const val KEY_RX_COUNT = "flutter.bg_native_rx_count"
        private const val KEY_LAST_START_STATUS = "flutter.bg_native_last_start_status"
        private const val KEY_LAST_START_ERROR = "flutter.bg_native_last_start_error"
        private const val KEY_NEXT_CHECK_AT = "flutter.bg_native_next_check_at"
        private const val KEY_SCHEDULE_MODE = "flutter.bg_native_schedule_mode"
        private const val KEY_DART_LAST_TICK_MS = "flutter.bg_diag_updated_at_ms"
        private const val DART_STALE_THRESHOLD_MS = 3 * 60 * 1000L

        private val supportedActions = setOf(
            ACTION_RESTART_BG_SERVICE,
            ACTION_RESTART_BG_SERVICE_FALLBACK,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
        )

        @JvmStatic
        fun schedulePeriodicHealthCheck(context: Context) {
            scheduleFallbackRepeating(context)
            scheduleNextHealthCheck(context, INITIAL_CHECK_DELAY_MS)
        }

        @JvmStatic
        fun triggerImmediateHealthCheck(context: Context) {
            try {
                val intent = Intent(context, ServiceRestarterReceiver::class.java).apply {
                    action = ACTION_RESTART_BG_SERVICE
                }
                context.sendBroadcast(intent)
            } catch (_: Exception) {
                // Silencioso
            }
        }

        private fun scheduleNextHealthCheck(context: Context, delayMs: Long) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
                val intent = Intent(context, ServiceRestarterReceiver::class.java).apply {
                    action = ACTION_RESTART_BG_SERVICE
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    PERIODIC_REQUEST_CODE,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                alarmManager.cancel(pendingIntent)
                val triggerAt = System.currentTimeMillis() + delayMs
                val mode = scheduleOneShotAlarm(
                    alarmManager = alarmManager,
                    triggerAt = triggerAt,
                    pendingIntent = pendingIntent,
                )
                recordNativeDiag(
                    context = context,
                    updates = mapOf(
                        KEY_NEXT_CHECK_AT to triggerAt.toString(),
                        KEY_SCHEDULE_MODE to mode,
                    )
                )
            } catch (_: Exception) {
                // Sin crash: AlarmWatchdog en Dart sigue como respaldo.
                recordNativeDiag(
                    context = context,
                    updates = mapOf(
                        KEY_LAST_START_STATUS to "SCHEDULE_ERROR",
                        KEY_LAST_START_ERROR to "SCHEDULE_NEXT_FAILED",
                    )
                )
            }
        }

        private fun scheduleFallbackRepeating(context: Context) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
                val intent = Intent(context, ServiceRestarterReceiver::class.java).apply {
                    action = ACTION_RESTART_BG_SERVICE_FALLBACK
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    FALLBACK_REQUEST_CODE,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(pendingIntent)
                val firstAt = System.currentTimeMillis() + (2 * 60 * 1000L)
                alarmManager.setInexactRepeating(
                    AlarmManager.RTC_WAKEUP,
                    firstAt,
                    FALLBACK_REPEAT_INTERVAL_MS,
                    pendingIntent
                )
            } catch (_: Exception) {
                // Silencioso: el one-shot encadenado sigue activo.
            }
        }

        private fun scheduleOneShotAlarm(
            alarmManager: AlarmManager,
            triggerAt: Long,
            pendingIntent: PendingIntent,
        ): String {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                try {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        pendingIntent
                    )
                    return "EXACT_ALLOW_WHILE_IDLE"
                } catch (_: SecurityException) {
                    // Fallback below.
                } catch (_: Exception) {
                    // Fallback below.
                }
            }

            try {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent
                )
                return "ALLOW_WHILE_IDLE_INEXACT"
            } catch (_: Exception) {
                alarmManager.set(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent
                )
                return "RTC_INEXACT"
            }
        }

        private fun recordNativeDiag(
            context: Context,
            updates: Map<String, String>,
            incrementCounter: Boolean = false,
        ) {
            try {
                val prefs = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
                val editor = prefs.edit()
                for ((k, v) in updates) {
                    editor.putString(k, v)
                }
                if (incrementCounter) {
                    val current = prefs.getInt(KEY_RX_COUNT, 0)
                    editor.putInt(KEY_RX_COUNT, current + 1)
                }
                editor.apply()
            } catch (_: Exception) {
                // Silencioso
            }
        }

        private fun readLongPref(
            context: Context,
            key: String,
        ): Long? {
            return try {
                val prefs = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
                if (!prefs.contains(key)) return null
                val value = prefs.all[key] ?: return null
                when (value) {
                    is Long -> value
                    is Int -> value.toLong()
                    is String -> value.toLongOrNull()
                    else -> null
                }
            } catch (_: Exception) {
                null
            }
        }

        private fun ensureBackgroundServiceRunning(
            context: Context,
            forceRestart: Boolean,
        ): Pair<String, String> {
            return try {
                val serviceIntent = Intent(
                    context,
                    id.flutter.flutter_background_service.BackgroundService::class.java,
                )
                if (forceRestart) {
                    try {
                        context.stopService(serviceIntent)
                    } catch (_: Exception) {
                        // Continua con arranque fresco.
                    }
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ContextCompat.startForegroundService(context, serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }

                Pair(
                    if (forceRestart) "FORCE_RESTART_REQUESTED" else "START_REQUESTED",
                    "",
                )
            } catch (e: Exception) {
                Pair(
                    if (forceRestart) "FORCE_RESTART_FAILED" else "START_FAILED",
                    e.javaClass.simpleName,
                )
            }
        }

        private fun isBackgroundServiceRunning(context: Context): Boolean {
            return try {
                val manager =
                    context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                        ?: return false
                @Suppress("DEPRECATION")
                manager.getRunningServices(Int.MAX_VALUE).any { service ->
                    service.service.className ==
                        id.flutter.flutter_background_service.BackgroundService::class.java.name
                }
            } catch (_: Exception) {
                false
            }
        }
    }
}
