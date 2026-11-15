package com.galaxyssi.chat

import android.Manifest
import android.app.AlertDialog
import android.os.Build
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal class HealthCyclingView(private val activity: HealthCenterActivity) {
    private val ui get() = activity.ui
    private var change: Job? = null
    private var refreshJob: Job? = null
    private val permission = activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) setEnabled(true) else refresh()
    }

    fun row(fixture: Boolean): View {
        val detail = ui.text(activity.getString(R.string.health_cycling_auto_off), 12f, muted = true)
        val total = ui.text(activity.getString(R.string.health_cycling_minutes, 0), 20f, bold = true).apply {
            gravity = Gravity.END
            tag = "health-overview-cycling-duration"
        }
        val row = ui.line().apply {
            tag = "health-overview-cycling"
            minimumHeight = ui.dp(56)
            setPadding(0, ui.dp(10), 0, ui.dp(10))
            addView(ui.column().apply {
                addView(ui.text(activity.getString(R.string.health_cycling_today), 15f, bold = true))
                addView(detail)
            }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(total, LinearLayout.LayoutParams(-2, -2).apply { marginStart = ui.dp(8) })
        }
        if (fixture) return row
        fun bind(reading: HealthCyclingReading?) {
            val state = reading?.state
            val time = state?.ledger?.today(System.currentTimeMillis(), ZoneId.systemDefault()) ?: 0
            total.text = activity.getString(if (time in 1..59_999) R.string.health_cycling_under_minute
                else R.string.health_cycling_minutes, time / 60_000)
            detail.setText(when (reading?.availability) {
                HealthCyclingAvailability.UNSUPPORTED -> R.string.health_cycling_unavailable
                HealthCyclingAvailability.NO_PERMISSION -> R.string.health_cycling_permission
                HealthCyclingAvailability.FAILED -> R.string.health_cycling_failed
                else -> when {
                    state?.enabled != true -> R.string.health_cycling_auto_off
                    state.ledger.riding(SystemClock.elapsedRealtime()) -> R.string.health_cycling_riding
                    else -> R.string.health_cycling_auto_on
                }
            })
            val configurable = reading != null && (reading.availability != HealthCyclingAvailability.UNSUPPORTED || state?.enabled == true)
            row.setOnClickListener(if (configurable) View.OnClickListener { showSettings(reading!!) } else null)
            row.isClickable = configurable
            row.isFocusable = configurable
        }
        bind(HealthCyclingTracking.readings.value)
        row.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            private var observer: Job? = null
            override fun onViewAttachedToWindow(view: View) {
                observer = activity.lifecycleScope.launch {
                    HealthCyclingTracking.readings.collect { bind(it) }
                }
                refresh()
            }
            override fun onViewDetachedFromWindow(view: View) { observer?.cancel(); observer = null }
        })
        return row
    }

    private fun showSettings(reading: HealthCyclingReading) {
        if (change?.isActive == true) return
        val current = reading.state.enabled
        val canEnable = reading.availability != HealthCyclingAvailability.UNSUPPORTED
        val dialog = AlertDialog.Builder(activity)
            .setTitle(R.string.health_cycling_auto_title)
            .setMessage(R.string.health_cycling_auto_detail)
            .setNegativeButton(R.string.common_cancel, null)
        if (current && (reading.availability == HealthCyclingAvailability.READY || !canEnable))
            dialog.setPositiveButton(R.string.health_cycling_auto_disable) { _, _ -> setEnabled(false) }
        else {
            if (canEnable) dialog.setPositiveButton(R.string.health_cycling_auto_enable) { _, _ ->
                if (Build.VERSION.SDK_INT >= 29 && !HealthCyclingTracking.hasPermission(activity))
                    permission.launch(Manifest.permission.ACTIVITY_RECOGNITION)
                else setEnabled(true)
            }
            if (current) dialog.setNeutralButton(R.string.health_cycling_auto_disable) { _, _ -> setEnabled(false) }
        }
        activity.showHealthDialog(dialog.create())
    }

    private fun refresh() {
        if (change?.isActive != true && refreshJob?.isActive != true)
            refreshJob = launchUpdate { HealthCyclingTracking.refresh(it) }
    }

    private fun setEnabled(enabled: Boolean) {
        if (change?.isActive == true) return
        change = launchUpdate { HealthCyclingTracking.setEnabled(it, enabled) }
    }

    private fun launchUpdate(action: suspend (android.content.Context) -> Unit) = activity.lifecycleScope.launch {
        try {
            withContext(Dispatchers.IO) { action(activity.applicationContext) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            HealthCyclingTracking.failed()
        }
    }
}
