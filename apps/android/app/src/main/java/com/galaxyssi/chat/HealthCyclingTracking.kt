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
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionEvent
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
    const val ACTION = "com.galaxyssi.chat.health.CYCLING_TRANSITION"
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

    private fun pendingIntent(context: Context, flags: Int) = PendingIntent.getBroadcast(context, 781, Intent(context,
        HealthCyclingReceiver::class.java).setAction(ACTION),
        flags or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0))

    private fun boot(context: Context) = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)

    private suspend fun subscribe(context: Context): Boolean {
        val transitions = listOf(ActivityTransition.ACTIVITY_TRANSITION_ENTER, ActivityTransition.ACTIVITY_TRANSITION_EXIT).map { kind ->
            ActivityTransition.Builder().setActivityType(DetectedActivity.ON_BICYCLE).setActivityTransition(kind).build()
        }
        val callback = requireNotNull(pendingIntent(context, PendingIntent.FLAG_UPDATE_CURRENT))
        try {
            val success = withTimeoutOrNull(4_000) {
                ActivityRecognition.getClient(context)
                    .requestActivityTransitionUpdates(ActivityTransitionRequest(transitions), callback).await()
                true
            } == true
            if (!success) callback.cancel()
            return success
        } catch (failure: CancellationException) {
            callback.cancel()
            throw failure
        } catch (_: Exception) {
            callback.cancel()
            return false
        }
    }

    private fun restoreState(context: Context, store: HealthCyclingStore, resetUnknownBoot: Boolean = false): HealthCyclingState {
        val saved = store.load()
        val boot = boot(context)
        val ledger = if (boot < 0 && resetUnknownBoot) saved.ledger.copy(boot = boot, lastEvent = -1, start = null)
            else saved.ledger.onBoot(boot)
        return saved.copy(ledger = ledger).also { if (it != saved) store.save(it) }
    }

    suspend fun refresh(context: Context, restart: Boolean = false) = gate.withLock {
        val store = HealthCyclingStore(context)
        var state = restoreState(context, store, resetUnknownBoot = restart)
        var access = availability(context)
        if (state.enabled && access == HealthCyclingAvailability.READY) {
            if (!hasPermission(context)) {
                registered = false
                if (state.ledger.start != null) {
                    state = state.copy(ledger = state.ledger.copy(start = null))
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
        val ledger = prior.ledger.copy(start = null, lastEvent = changedAt)
        val next = prior.copy(enabled = enabled, ledger = ledger)
        try {
            store.save(next)
        } catch (failure: Exception) {
            if (enabled && !prior.enabled) {
                pendingIntent(context, PendingIntent.FLAG_NO_CREATE)?.cancel()
                registered = false
            }
            throw failure
        }
        updates.value = HealthCyclingReading(next, access)
        if (!enabled) {
            registered = false
            pendingIntent(context, PendingIntent.FLAG_NO_CREATE)?.let { callback ->
                try {
                    if (access == HealthCyclingAvailability.READY && hasPermission(context)) {
                        withTimeoutOrNull(4_000) { ActivityRecognition.getClient(context).removeActivityTransitionUpdates(callback).await() }
                    }
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    // Canceling the callback still protects the already persisted opt-out.
                } finally { callback.cancel() }
            }
        }
    }

    suspend fun receive(context: Context, transitions: List<ActivityTransitionEvent>) = gate.withLock {
        val store = HealthCyclingStore(context)
        if (!store.enabled || !hasPermission(context)) return@withLock
        val state = restoreState(context, store)
        val elapsed = SystemClock.elapsedRealtime()
        val wall = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        val ledger = transitions.sortedBy { it.elapsedRealTimeNanos }.fold(state.ledger) { log, event ->
            if (event.activityType != DetectedActivity.ON_BICYCLE) log else when (event.transitionType) {
                ActivityTransition.ACTIVITY_TRANSITION_ENTER ->
                    log.transition(true, event.elapsedRealTimeNanos / 1_000_000, elapsed, wall, zone)
                ActivityTransition.ACTIVITY_TRANSITION_EXIT ->
                    log.transition(false, event.elapsedRealTimeNanos / 1_000_000, elapsed, wall, zone)
                else -> log
            }
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
        val events = if (intent.action == HealthCyclingTracking.ACTION) {
            runCatching { ActivityTransitionResult.extractResult(intent)?.transitionEvents }.getOrNull() ?: return
        } else null
        if (events == null && intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) return
        val pending = goAsync()
        HealthCyclingTracking.worker.launch {
            try {
                if (events != null) HealthCyclingTracking.receive(app, events)
                else if (HealthCyclingStore(app).enabled) HealthCyclingTracking.refresh(app, restart = true)
            } catch (_: Exception) {
                HealthCyclingTracking.failed()
            } finally { pending.finish() }
        }
    }
}
