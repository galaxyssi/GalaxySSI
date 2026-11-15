package com.galaxyssi.chat

import android.Manifest
import android.app.AlertDialog
import android.content.res.ColorStateList
import android.os.Build
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
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
        val total = ui.text(activity.getString(R.string.health_cycling_minutes, 0), 22f, bold = true).apply {
            gravity = Gravity.END
            setPadding(ui.dp(4), 0, ui.dp(5), 0)
            tag = "health-overview-cycling-duration"
        }
        val arrow = ImageView(activity).apply {
            setImageResource(R.drawable.ic_arrow_right)
            imageTintList = ColorStateList.valueOf(activity.getColor(R.color.text_secondary))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val row = ui.column().apply {
            tag = "health-overview-cycling"
            minimumHeight = ui.dp(50)
            setPadding(0, ui.dp(10), 0, ui.dp(10))
            addHealthOverviewHeadline(activity, activity.getString(R.string.health_cycling_today), R.drawable.ic_health_bike, total, arrow)
            ui.add(this, detail, 4)
        }
        val result = ui.column().apply {
            addView(row)
            addView(View(activity).apply { setBackgroundColor(activity.getColor(R.color.separator)) },
                LinearLayout.LayoutParams(-1, ui.dp(1)))
        }
        if (fixture) return result
        fun riding(reading: HealthCyclingReading?) = reading?.let {
            it.availability == HealthCyclingAvailability.READY && it.state.enabled &&
                it.state.ledger.riding(SystemClock.elapsedRealtime())
        } == true
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
                    riding(reading) -> R.string.health_cycling_riding
                    else -> R.string.health_cycling_stopped
                }
            })
            val configurable = reading != null && (reading.availability != HealthCyclingAvailability.UNSUPPORTED || state?.enabled == true)
            row.setOnClickListener(if (configurable) View.OnClickListener { showSettings(reading!!) } else null)
            row.isClickable = configurable
            row.isFocusable = configurable
            arrow.visibility = if (configurable) View.VISIBLE else View.INVISIBLE
        }
        bind(HealthCyclingTracking.readings.value)
        row.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            private var observer: Job? = null
            override fun onViewAttachedToWindow(view: View) {
                observer = activity.lifecycleScope.launch {
                    HealthCyclingTracking.readings.collectLatest {
                        bind(it)
                        if (riding(it)) {
                            while (riding(it)) delay(30_000)
                            bind(it)
                        }
                    }
                }
                refresh()
            }
            override fun onViewDetachedFromWindow(view: View) { observer?.cancel(); observer = null }
        })
        return result
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
