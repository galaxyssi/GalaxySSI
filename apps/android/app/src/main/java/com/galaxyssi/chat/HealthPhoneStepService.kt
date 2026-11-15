package com.galaxyssi.chat

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.SystemClock
import android.provider.Settings
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class HealthPhoneStepService : Service(), SensorEventListener {
    private lateinit var thread: HandlerThread
    private lateinit var worker: Handler
    private val store by lazy { HealthPhoneStepStore(applicationContext) }
    private val sensors by lazy { getSystemService(SensorManager::class.java) }
    private var ledger: HealthPhoneStepLedger? = null
    private var registered = false
    private var pendingWrite = false
    private var boot = -1
    @Volatile private var destroyed = false
    private val checkpoint = Runnable {
        pendingWrite = false
        if (registered) persist(true)
    }

    override fun onCreate() {
        super.onCreate()
        thread = HandlerThread("health-phone-steps").apply { start() }
        worker = Handler(thread.looper)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            worker.post {
                detach()
                ledger = (ledger ?: runCatching { store.load() }.getOrNull() ?: HealthPhoneStepLedger(LocalDate.now()))
                    .today(LocalDate.now()).copy(counter = null)
                val saved = persist(false)
                publish(false, failed = !saved)
                stopSelfResult(startId)
            }
            return START_NOT_STICKY
        }
        if (!runCatching { startForeground(NOTIFICATION_ID, notification()) }.isSuccess) {
            HealthPhoneStepUpdates.publish(HealthPhoneStepReading(null, failed = true))
            stopSelfResult(startId)
            return START_NOT_STICKY
        }
        worker.post { if (!destroyed) begin(intent?.action == START, startId) }
        return START_STICKY
    }

    private fun begin(userRequested: Boolean, startId: Int) {
        if (registered) return
        val sensor = sensors?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (!hasPermission(this) || sensor == null || (!userRequested && !store.enabled)) {
            stopSelfResult(startId)
            return
        }
        val restored = runCatching { store.load() }
        boot = Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT, -1)
        val today = LocalDate.now()
        ledger = if (restored.isFailure) null else (restored.getOrNull() ?: HealthPhoneStepLedger(today)).today(today)
            .let { if (!store.enabled || boot < 0 || it.boot != boot) it.copy(counter = null, boot = boot) else it }
        registered = ledger != null && runCatching {
            sensors?.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL, 5_000_000, worker) == true
        }.getOrDefault(false)
        if (!registered || !persist(true)) {
            detach()
            publish(false, failed = true)
            stopSelfResult(startId)
        } else publish(true)
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (destroyed || !registered || event.sensor.type != Sensor.TYPE_STEP_COUNTER) return
        val raw = event.values.firstOrNull()?.takeIf { it.isFinite() && it >= 0 && it.toDouble() <= Int.MAX_VALUE }
            ?.toLong() ?: return
        val current = ledger ?: return
        val zone = ZoneId.systemDefault()
        val now = Instant.now()
        val ageMillis = ((SystemClock.elapsedRealtimeNanos() - event.timestamp).coerceAtLeast(0L)) / 1_000_000
        val updated = current.observe(raw, boot, now.atZone(zone).toLocalDate(), now.minusMillis(ageMillis).atZone(zone).toLocalDate())
        if (updated == current) return
        ledger = updated
        publish(true)
        if (!pendingWrite) {
            pendingWrite = true
            worker.postDelayed(checkpoint, 5_000)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    override fun onBind(intent: Intent?): IBinder? = null

    private fun persist(enabled: Boolean): Boolean = runCatching { store.save(requireNotNull(ledger), enabled) }.isSuccess
    private fun publish(active: Boolean, failed: Boolean = false) {
        if (!destroyed) HealthPhoneStepUpdates.publish(HealthPhoneStepReading(ledger, active, failed))
    }

    private fun detach() {
        if (registered) sensors?.unregisterListener(this)
        registered = false
        worker.removeCallbacks(checkpoint)
        pendingWrite = false
    }

    override fun onDestroy() {
        destroyed = true
        HealthPhoneStepUpdates.readings.value?.takeIf { it.active }?.let {
            HealthPhoneStepUpdates.publish(it.copy(active = false))
        }
        worker.post {
            val flush = registered && pendingWrite
            detach()
            if (flush) persist(true)
        }
        thread.quitSafely()
        super.onDestroy()
    }

    private fun notification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.health_phone_steps_title),
            NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
        val stop = PendingIntent.getService(this, 0, Intent(this, HealthPhoneStepService::class.java).setAction(STOP),
            PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, 0, Intent(this, HealthCenterActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_health_data_chart)
            .setContentTitle(getString(R.string.health_phone_steps_title))
            .setContentText(getString(R.string.health_phone_steps_counting))
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, getString(R.string.health_phone_steps_stop), stop).build())
            .build()
    }

    internal companion object {
        private const val CHANNEL = "health-phone-steps"
        private const val NOTIFICATION_ID = 71109
        const val START = "com.galaxyssi.chat.health.START_PHONE_STEPS"
        const val STOP = "com.galaxyssi.chat.health.STOP_PHONE_STEPS"
        fun hasPermission(context: Context) = Build.VERSION.SDK_INT < 29 ||
            context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
        fun supported(context: Context) = context.getSystemService(SensorManager::class.java)
            ?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) != null
    }
}
