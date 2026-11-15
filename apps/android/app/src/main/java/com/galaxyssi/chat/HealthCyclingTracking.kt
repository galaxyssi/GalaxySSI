package com.galaxyssi.chat

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityRecognitionResult
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull

internal enum class HealthCyclingAvailability { READY, UNSUPPORTED, NO_PERMISSION, FAILED }
internal data class HealthCyclingReading(val state: HealthCyclingState, val availability: HealthCyclingAvailability)

internal object HealthCyclingTracking {
    const val TRANSITION = "com.galaxyssi.chat.health.CYCLING_TRANSITION"
    const val SAMPLE = "com.galaxyssi.chat.health.CYCLING_SAMPLE"
    private const val SAMPLE_INTERVAL_MS = 20_000L
    private val gate = Mutex()
    private val updates = MutableStateFlow<HealthCyclingReading?>(null)
    val readings = updates.asStateFlow()
    val worker = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var registered = false

    fun hasPermission(context: Context): Boolean =
        context.checkSelfPermission(if (Build.VERSION.SDK_INT >= 29) Manifest.permission.ACTIVITY_RECOGNITION
            else "com.google.android.gms.permission.ACTIVITY_RECOGNITION") == PackageManager.PERMISSION_GRANTED

    private fun availability(context: Context) =
        if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS)
            HealthCyclingAvailability.READY else HealthCyclingAvailability.UNSUPPORTED

    private fun pendingIntent(context: Context, action: String, flags: Int) = PendingIntent.getBroadcast(context,
        if (action == TRANSITION) 781 else 782, Intent(context, HealthCyclingReceiver::class.java).setAction(action),
        flags or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0))

    private fun boot(context: Context) = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)

    private suspend fun subscribe(context: Context): Boolean {
        val enter = ActivityTransition.ACTIVITY_TRANSITION_ENTER
        val transitions = (listOf(DetectedActivity.ON_BICYCLE, DetectedActivity.WALKING, DetectedActivity.IN_VEHICLE).map { it to enter } +
            (DetectedActivity.ON_BICYCLE to ActivityTransition.ACTIVITY_TRANSITION_EXIT)).map { (activity, type) ->
            ActivityTransition.Builder().setActivityType(activity).setActivityTransition(type).build()
        }
        val changes = requireNotNull(pendingIntent(context, TRANSITION, PendingIntent.FLAG_UPDATE_CURRENT))
        val samples = requireNotNull(pendingIntent(context, SAMPLE, PendingIntent.FLAG_UPDATE_CURRENT))
        var success = false
        try {
            success = withTimeoutOrNull(4_000) {
                val client = ActivityRecognition.getClient(context)
                val transitionTask = client.requestActivityTransitionUpdates(ActivityTransitionRequest(transitions), changes)
                val sampleTask = client.requestActivityUpdates(SAMPLE_INTERVAL_MS, samples)
                transitionTask.await()
                sampleTask.await()
                true
            } == true
            return success
        } catch (failure: CancellationException) {
            throw failure
        } catch (_: Exception) {
            return false
        } finally {
            if (!success) { changes.cancel(); samples.cancel() }
        }
    }

    private suspend fun unsubscribe(context: Context, canRequest: Boolean) {
        val changes = pendingIntent(context, TRANSITION, PendingIntent.FLAG_NO_CREATE)
        val samples = pendingIntent(context, SAMPLE, PendingIntent.FLAG_NO_CREATE)
        try {
            if (canRequest && (changes != null || samples != null)) withTimeoutOrNull(4_000) {
                val client = ActivityRecognition.getClient(context)
                val transitionTask = changes?.let(client::removeActivityTransitionUpdates)
                val sampleTask = samples?.let(client::removeActivityUpdates)
                transitionTask?.await()
                sampleTask?.await()
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            // The app still cancels both pending intents and rejects callbacks after opt-out.
        } finally { changes?.cancel(); samples?.cancel() }
    }

    private fun restoreState(context: Context, store: HealthCyclingStore, resetUnknownBoot: Boolean = false): HealthCyclingState {
        val saved = store.load()
        val ledger = saved.ledger.onBoot(boot(context), System.currentTimeMillis(), ZoneId.systemDefault(), resetUnknownBoot)
        return saved.copy(ledger = ledger).also { if (it != saved) store.save(it) }
    }

    suspend fun refresh(context: Context, restart: Boolean = false) = gate.withLock {
        val store = HealthCyclingStore(context)
        var state = restoreState(context, store, resetUnknownBoot = restart)
        var access = availability(context)
        if (state.enabled && access == HealthCyclingAvailability.READY) {
            if (!hasPermission(context)) {
                registered = false
                unsubscribe(context, canRequest = false)
                if (state.ledger.start != null || state.ledger.possibleStart != null) {
                    state = state.copy(ledger = state.ledger.settle(System.currentTimeMillis(), ZoneId.systemDefault()))
                    store.save(state)
                }
                access = HealthCyclingAvailability.NO_PERMISSION
            } else if (!registered || restart) {
                registered = subscribe(context)
                if (!registered) access = HealthCyclingAvailability.FAILED
            }
        }
        updates.value = HealthCyclingReading(state, access)
    }

    suspend fun setEnabled(context: Context, enabled: Boolean) = gate.withLock {
        val store = HealthCyclingStore(context)
        val prior = restoreState(context, store)
        val changedAt = SystemClock.elapsedRealtime()
        var access = availability(context)
        if (enabled) {
            if (access == HealthCyclingAvailability.READY && !hasPermission(context)) access = HealthCyclingAvailability.NO_PERMISSION
            if (access == HealthCyclingAvailability.READY) {
                registered = subscribe(context)
                if (!registered) access = HealthCyclingAvailability.FAILED
            }
            if (access != HealthCyclingAvailability.READY) {
                updates.value = HealthCyclingReading(prior, access)
                return@withLock
            }
        }
        val ledger = prior.ledger.settle(System.currentTimeMillis(), ZoneId.systemDefault()).copy(lastEvent = changedAt)
        val next = prior.copy(enabled = enabled, ledger = ledger)
        try {
            store.save(next)
        } catch (failure: Exception) {
            if (enabled && !prior.enabled) {
                unsubscribe(context, canRequest = false)
                registered = false
            }
            throw failure
        }
        updates.value = HealthCyclingReading(next, access)
        if (!enabled) {
            registered = false
            unsubscribe(context, canRequest = access == HealthCyclingAvailability.READY && hasPermission(context))
        }
    }

    suspend fun receive(context: Context, signals: List<HealthCyclingSignal>) = gate.withLock {
        val store = HealthCyclingStore(context)
        if (!store.enabled || !hasPermission(context)) return@withLock
        val state = restoreState(context, store)
        val elapsed = SystemClock.elapsedRealtime()
        val wall = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        val ledger = signals.sortedBy { it.elapsed }.fold(state.ledger) { log, signal ->
            log.observe(signal, elapsed, wall, zone)
        }
        if (ledger != state.ledger) {
            val next = state.copy(ledger = ledger)
            store.save(next)
            updates.value = HealthCyclingReading(next, HealthCyclingAvailability.READY)
        }
    }

    fun failed() {
        val state = updates.value?.state ?: HealthCyclingState()
        updates.value = HealthCyclingReading(state, HealthCyclingAvailability.FAILED)
    }
}

class HealthCyclingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        val restart = intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        val signals = runCatching { signals(intent) }.getOrDefault(emptyList())
        if (!restart && signals.isEmpty()) return
        val pending = goAsync()
        HealthCyclingTracking.worker.launch {
            try {
                if (restart) {
                    if (HealthCyclingStore(app).enabled) HealthCyclingTracking.refresh(app, restart = true)
                } else HealthCyclingTracking.receive(app, signals)
            } catch (_: Exception) {
                HealthCyclingTracking.failed()
            } finally { pending.finish() }
        }
    }

    private fun signals(intent: Intent): List<HealthCyclingSignal> = when (intent.action) {
        HealthCyclingTracking.TRANSITION -> ActivityTransitionResult.extractResult(intent)?.transitionEvents.orEmpty().mapNotNull { event ->
            val enter = event.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER
            val motion = when {
                event.activityType == DetectedActivity.ON_BICYCLE && enter -> HealthCyclingMotion.ENTER
                event.activityType == DetectedActivity.ON_BICYCLE && event.transitionType == ActivityTransition.ACTIVITY_TRANSITION_EXIT ->
                    HealthCyclingMotion.EXIT
                event.activityType == DetectedActivity.WALKING && enter -> HealthCyclingMotion.FOOT
                event.activityType == DetectedActivity.IN_VEHICLE && enter -> HealthCyclingMotion.MOTOR
                else -> null
            }
            motion?.let { HealthCyclingSignal(it, event.elapsedRealTimeNanos / 1_000_000) }
        }
        HealthCyclingTracking.SAMPLE -> ActivityRecognitionResult.extractResult(intent)?.let { result ->
            val bike = result.getActivityConfidence(DetectedActivity.ON_BICYCLE)
            val foot = maxOf(result.getActivityConfidence(DetectedActivity.ON_FOOT),
                result.getActivityConfidence(DetectedActivity.WALKING), result.getActivityConfidence(DetectedActivity.RUNNING))
            val motor = result.getActivityConfidence(DetectedActivity.IN_VEHICLE)
            val still = result.getActivityConfidence(DetectedActivity.STILL)
            cyclingMotion(bike, foot, motor, still)?.let { listOf(HealthCyclingSignal(it, result.elapsedRealtimeMillis)) }
        }.orEmpty()
        else -> emptyList()
    }
}
