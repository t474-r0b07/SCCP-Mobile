package com.sccp.mobile

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.content.SharedPreferences
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "sccp/mobile_system"
    private val restartRequestCode = 990061
    private val flutterPrefsFile = "FlutterSharedPreferences"
    private val keyUserId = "flutter.user_id"
    private val keyDeviceId = "flutter.user_device_id"
    private val keyLegacyImei = "flutter.user_imei"
    private val keyOperationalReady = "flutter.operational_ready"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (hasOperationalSessionSeed()) {
            ServiceRestarterReceiver.schedulePeriodicHealthCheck(applicationContext)
            ServiceRestarterReceiver.triggerImmediateHealthCheck(applicationContext)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }
                "requestIgnoreBatteryOptimizations" -> {
                    result.success(requestIgnoreBatteryOptimizations())
                }
                "openIgnoreBatteryOptimizationSettings" -> {
                    result.success(openIgnoreBatteryOptimizationSettings())
                }
                "openDataUsageSettings" -> {
                    result.success(openDataUsageSettings())
                }
                "getRestrictBackgroundStatus" -> {
                    result.success(getRestrictBackgroundStatus())
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (hasOperationalSessionSeed()) {
            ServiceRestarterReceiver.schedulePeriodicHealthCheck(applicationContext)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        // Si la app es removida por swipe/cierre de tarea, intentamos
        // reactivar el servicio en segundo plano con una alarma corta.
        if (isFinishing && hasOperationalSessionSeed()) {
            scheduleBackgroundServiceRestart()
        }
    }

    private fun hasOperationalSessionSeed(): Boolean {
        return try {
            val prefs: SharedPreferences =
                getSharedPreferences(flutterPrefsFile, Context.MODE_PRIVATE)
            val userId = prefs.getString(keyUserId, "")?.trim().orEmpty()
            val deviceId = prefs.getString(keyDeviceId, "")?.trim().orEmpty()
            val legacyImei = prefs.getString(keyLegacyImei, "")?.trim().orEmpty()
            val operationalReady = prefs.getBoolean(keyOperationalReady, false)
            userId.isNotEmpty() &&
                (deviceId.isNotEmpty() || legacyImei.isNotEmpty()) &&
                operationalReady
        } catch (_: Exception) {
            false
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pm.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!isIgnoringBatteryOptimizations()) {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                }
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openIgnoreBatteryOptimizationSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openDataUsageSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_DATA_USAGE_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun getRestrictBackgroundStatus(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return 0
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return 0
        return cm.restrictBackgroundStatus
    }

    private fun scheduleBackgroundServiceRestart() {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(applicationContext, ServiceRestarterReceiver::class.java).apply {
                action = ServiceRestarterReceiver.ACTION_RESTART_BG_SERVICE
            }
            val pendingIntent = PendingIntent.getBroadcast(
                applicationContext,
                restartRequestCode,
                intent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )

            val triggerAt = System.currentTimeMillis() + 1500L
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAt,
                pendingIntent
            )
        } catch (_: Exception) {
            // Silencioso: la app seguirá con el watchdog existente.
        }
    }
}
