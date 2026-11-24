package com.galaxyssi.chat

import android.app.DatePickerDialog
import android.os.Bundle
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import java.time.LocalDate
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.hypot

internal class HealthActivityComparisonActivity : HealthHistoryPage() {
    override val heading = R.string.health_activity_comparison
    private var kind = HealthActivityKind.STEPS
    private var days = 7
    private var first = LocalDate.now().minusDays(6)
    private var last = LocalDate.now()
    private val liveScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var updates: Job? = null
    private var loaded: HealthActivityComparison? = null
    private var savedToday: HealthActivityDay? = null
    private var displayed: HealthActivityComparison? = null
    private var selectedDay: LocalDate? = null
    private var touchX = 0f
    private var touchY = 0f
    override fun onCreate(savedInstanceState: Bundle?) {
        savedInstanceState?.let {
            kind = HealthActivityKind.entries.getOrElse(it.getInt("kind")) { HealthActivityKind.STEPS }
            days = it.getInt("days", 7)
            runCatching { first = LocalDate.parse(it.getString("first")); last = LocalDate.parse(it.getString("last")) }
            selectedDay = it.getString("selected_day")?.let { day -> runCatching { LocalDate.parse(day) }.getOrNull() }
        }
        super.onCreate(savedInstanceState)
    }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putInt("kind", kind.ordinal); outState.putInt("days", days)
        outState.putString("first", first.toString()); outState.putString("last", last.toString())
        outState.putString("selected_day", selectedDay?.toString())
        super.onSaveInstanceState(outState)
    }
    override fun onStart() {
        super.onStart()
        if (names.fixture != null) return
        updates = liveScope.launch {
            launch {
                combine(HealthPhoneStepUpdates.readings, HealthCyclingTracking.readings) { _, _ -> Unit }
                    .drop(1).collect {
                        delay(750)
                        renderLive()
                    }
            }
            launch {
                while (isActive) {
                    val now = Instant.now()
                    val midnight = LocalDate.now().plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant()
                    delay((midnight.toEpochMilli() - now.toEpochMilli()).coerceAtLeast(1))
                    refresh()
                }
            }
        }
    }
    override fun onStop() {
        updates?.cancel(); updates = null
        loaded = null; savedToday = null; displayed = null
        super.onStop()
    }
    override fun onDestroy() { liveScope.cancel(); super.onDestroy() }
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> { touchX = event.rawX; touchY = event.rawY }
            MotionEvent.ACTION_UP -> {
                if (selectedDay != null && hypot(event.rawX - touchX, event.rawY - touchY) <=
                    ViewConfiguration.get(this).scaledTouchSlop) {
                    content.findViewWithTag<HealthActivityComparisonChart>("health-activity-chart")?.let { chart ->
                        val position = IntArray(2)
                        chart.getLocationOnScreen(position)
                        if (event.rawX < position[0] || event.rawX >= position[0] + chart.width ||
                            event.rawY < position[1] || event.rawY >= position[1] + chart.height) chart.clearSelection()
                    }
                }
            }
        }
        return super.dispatchTouchEvent(event)
    }
    override fun refresh() {
        if (days > 0) HealthActivityComparison.trailing(days, LocalDate.now()).let { first = it.start; last = it.endInclusive }
        val from = first; val until = last; val selected = kind
        loaded = null; savedToday = null; displayed = null
        render(null)
        query({ check ->
            val zone = ZoneId.systemDefault()
            HealthPrivacyStore.track(applicationContext, HealthAccessScope(HealthAccessPurpose.OVERVIEW, setOf(HealthMetric.STEPS),
                from.atStartOfDay(zone).toInstant().toEpochMilli(), until.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli(), zone.id), names.privacy) {
                check()
                val today = if (names.fixture == null) {
                    // Only surviving checkpoints can be migrated; missing older days remain unknown.
                    when (selected) {
                        HealthActivityKind.STEPS -> HealthPhoneStepStore(applicationContext).let { store ->
                            val ledger = store.load()
                            ledger?.let(store::archive)
                            healthActivityStepDay(ledger, LocalDate.now())
                        }
                        HealthActivityKind.CYCLING -> HealthCyclingStore(applicationContext).let { store ->
                            val state = store.load()
                            store.archive(state)
                            healthActivityCyclingDay(state, System.currentTimeMillis(), zone)
                        }
                    }
                } else null
                HealthActivityHistoryStore(applicationContext, names.activity).use {
                    HealthActivityComparison.build(from, until, it.read(selected, from, until), selected) to today
                }
            }
        }) { (result, today) -> loaded = result; savedToday = today; renderLive() }
    }
    private fun renderLive() {
        var result = loaded ?: return
        if (content.findViewWithTag<HealthActivityComparisonChart>("health-activity-chart")?.trackingTouch == true) return
        val today = LocalDate.now()
        val live = if (names.fixture != null) null else when (kind) {
            HealthActivityKind.STEPS -> healthActivityStepDay(HealthPhoneStepUpdates.readings.value?.ledger, today)
            HealthActivityKind.CYCLING -> healthActivityCyclingDay(HealthCyclingTracking.readings.value?.state,
                System.currentTimeMillis(), ZoneId.systemDefault())
        }
        (live ?: savedToday)?.takeIf { it.day == today }?.let { result = result.withDay(today, it.total) }
        if (displayed != result) { displayed = result; render(result) }
    }
    private fun render(result: HealthActivityComparison?) {
        content.removeAllViews()
        segment(listOf(R.string.health_overview_today_steps, R.string.health_cycling_today), kind.ordinal) {
            kind = HealthActivityKind.entries[it]; selectedDay = null; refresh()
        }
        val periods = listOf(7, 30, 90, 0)
        segment(listOf(R.string.health_trend_7, R.string.health_trend_30, R.string.health_trend_90, R.string.health_trend_custom), periods.indexOf(days)) {
            if (it == 3) custom() else { days = periods[it]; selectedDay = null; refresh() }
        }
        val count = ChronoUnit.DAYS.between(first, last) + 1
        if (result == null) { ui.add(content, ui.text(getString(R.string.health_loading)), 24); return }
        ui.add(content, ui.text(getString(R.string.health_activity_total), 13f, muted = true), 20)
        val totals = result.current.filterNotNull()
        ui.add(content, ui.text(if (totals.isEmpty()) "\u2014" else amount(totals.sum()), 30f, bold = true).apply {
            tag = "health-activity-total"
        }, 4)
        ui.add(content, ui.text(getString(R.string.health_activity_coverage, result.current.count { it != null }, count.toInt()), 12f, muted = true), 4)
        totals.takeIf { it.isNotEmpty() }?.let { totals ->
            ui.add(content, ui.text(getString(R.string.health_activity_average, amount(totals.sum() / totals.size)), 13f, muted = true), 4)
        }
        ui.add(content, HealthActivityComparisonChart(this, result, kind, selectedDay, ::renderLive) { selectedDay = it }.apply {
            tag = "health-activity-chart"
        }, 16)
    }
    private fun amount(value: Long) = healthActivityAmount(this, kind, value)
    private fun segment(labels: List<Int>, selected: Int, choose: (Int) -> Unit) {
        ui.add(content, RadioGroup(this).apply {
            orientation = RadioGroup.HORIZONTAL
            labels.forEachIndexed { index, label -> addView(RadioButton(this@HealthActivityComparisonActivity).apply {
                id = android.view.View.generateViewId(); text = getString(label); textSize = 13f; minimumHeight = ui.dp(48)
                buttonDrawable = null; gravity = android.view.Gravity.CENTER
                setTextColor(getColor(if (selected == index) R.color.health_overview_green else R.color.text_primary))
                background = ui.background(getColor(if (selected == index) R.color.button_soft else R.color.page_bg), radius = 6)
                setPadding(ui.dp(2), ui.dp(4), ui.dp(2), ui.dp(4))
                isChecked = selected == index; setOnClickListener { choose(index) }
            }, RadioGroup.LayoutParams(0, -2, 1f)) }
        }, 4)
    }
    private fun custom() {
        show(DatePickerDialog(this, { _, y, m, d ->
            val start = LocalDate.of(y, m + 1, d)
            show(DatePickerDialog(this, { _, ey, em, ed ->
                val end = LocalDate.of(ey, em + 1, ed)
                if (HealthActivityComparison.validDates(start, end, LocalDate.now())) {
                    first = start; last = end; days = 0; selectedDay = null; refresh()
                } else android.widget.Toast.makeText(this, R.string.health_activity_dates_invalid, android.widget.Toast.LENGTH_LONG).show()
            }, last.year, last.monthValue - 1, last.dayOfMonth))
        }, first.year, first.monthValue - 1, first.dayOfMonth))
    }
}
