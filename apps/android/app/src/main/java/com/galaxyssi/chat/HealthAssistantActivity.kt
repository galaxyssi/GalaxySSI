package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.content.Intent
import android.database.ContentObserver
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.widget.LinearLayout
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class HealthAssistantActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val text by lazy { HealthWeeklyText(this) }
    private val tasks = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var body: LinearLayout
    private lateinit var names: HealthOverviewDatabases
    private val zone = ZoneId.systemDefault()
    private var end = LocalDate.now(zone).minusDays(1)
    private var metrics = setOf(HealthMetric.SLEEP_DURATION, HealthMetric.STEPS)
    private var focus = HealthAnalysisFocus.CHANGES
    private var profileFields = emptySet<HealthProfileField>()
    private var background = emptyMap<String, HealthAnalysisBackgroundChoice>()
    private var active = false
    private var generation = 0
    private var job: Job? = null
    private var profileCheck: Job? = null
    private var signal: CancellationSignal? = null
    private var dialog: AlertDialog? = null
    private var preview: HealthAnalysisPreview? = null
    private var plan: HealthAnalysisPlan? = null
    private var notice: Int? = null
    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            if (active && (preview != null || job?.isActive == true || dialog?.isShowing == true))
                reset(R.string.health_assistant_changed)
        }
    }
    private val privacyObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            val scoped = profileFields.isNotEmpty() || background.isNotEmpty()
            profileFields = emptySet()
            background = emptyMap()
            if (active && scoped) reset(R.string.health_assistant_changed)
            else observer.onChange(selfChange)
        }
    }
    private val profileObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            if (!active || (profileFields.isEmpty() && background.isEmpty())) return
            val result = preview
            if (result == null) {
                if (job?.isActive == true) reset(R.string.health_assistant_profile_changed)
                return
            }
            profileCheck?.cancel()
            profileCheck = tasks.launch {
                val current = withContext(Dispatchers.IO) {
                    runCatching { HealthAnalysis.profileIsCurrent(applicationContext, names, result) }.getOrDefault(false)
                }
                if (active && preview === result && !current) reset(R.string.health_assistant_profile_changed)
            }
        }
    }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val fixture = if (BuildConfig.DEBUG) intent.getStringExtra("health_assistant_test_id")
            ?.takeIf(HealthProfilePolicy::uuid) else null
        names = HealthOverviewDatabases(fixture)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        body = healthProfileBody(R.string.health_assistant_title) { finish() }
    }

    override fun onResume() {
        super.onResume()
        active = true
        contentResolver.registerContentObserver(HealthRecordStore.changes(this, names.records), false, observer)
        contentResolver.registerContentObserver(HealthPrivacyStore.changes(this, names.privacy), false, privacyObserver)
        contentResolver.registerContentObserver(HealthProfileStore.changes(this, names.profile), false, profileObserver)
        render()
    }

    override fun onPause() {
        active = false
        contentResolver.unregisterContentObserver(observer)
        contentResolver.unregisterContentObserver(privacyObserver)
        contentResolver.unregisterContentObserver(profileObserver)
        profileFields = emptySet()
        background = emptyMap()
        reset()
        body.removeAllViews()
        super.onPause()
    }

    override fun onDestroy() { tasks.cancel(); super.onDestroy() }

    private fun reset(message: Int? = null) {
        generation++
        signal?.cancel()
        signal = null
        job?.cancel()
        job = null
        profileCheck?.cancel()
        profileCheck = null
        dialog?.dismiss()
        dialog = null
        preview = null
        plan = null
        notice = message
        if (active) render()
    }

    private fun selection() = HealthWeeklyScope(end, zone, metrics, comparison = focus == HealthAnalysisFocus.CHANGES)

    private fun render() {
        val content = healthProfileContent(body)
        val scope = selection()
        content.addView(ui.text(getString(R.string.health_assistant_scope), 19f, bold = true))
        ui.add(content, ui.profileRow(text.range(scope)) { chooseDate() }, 8)
        if (scope.hasBaseline) ui.add(content, ui.text(getString(R.string.health_assistant_baseline,
            scope.baselineFirst, scope.baselineLast), 13f, muted = true), 4)
        ui.add(content, ui.profileRow(getString(R.string.health_weekly_metrics),
            healthWeeklyMetrics.filter { it in metrics }.joinToString(", ") { text.title(it) }) { chooseMetrics() }, 8)
        ui.add(content, ui.profileRow(getString(R.string.health_assistant_question), getString(focusLabel(focus))) { chooseFocus() }, 6)
        ui.add(content, ui.profileRow(getString(R.string.health_assistant_profile),
            if (profileFields.isEmpty()) getString(R.string.health_assistant_profile_none)
            else healthAnalysisProfileFields.filter { it in profileFields }.joinToString(", ") { getString(it.titleResource()) }
        ) { chooseProfile() }.apply { tag = "health-assistant-profile" }, 6)
        ui.add(content, ui.profileRow(getString(R.string.health_assistant_background),
            if (background.isEmpty()) getString(R.string.health_assistant_profile_none)
            else getString(R.string.health_assistant_background_count, background.size, healthAnalysisBackgroundLimit)
        ) { chooseBackground() }.apply { tag = "health-assistant-background" }, 6)
        ui.add(content, ui.text(getString(R.string.health_assistant_local_scope), 13f, muted = true), 8)
        if (preview == null) ui.add(content, ui.command(R.string.health_assistant_calculate) { calculate() }.apply {
            tag = "health-assistant-calculate"
            isEnabled = notice != R.string.health_loading
        }, 12)
        notice?.let { message ->
            ui.add(content, ui.text(getString(message), 14f, muted = true).apply { tag = "health-assistant-status" }, 12)
            if (message == R.string.health_assistant_blocked || message == R.string.health_assistant_online_blocked ||
                message == R.string.health_assistant_profile_blocked) {
                ui.add(content, ui.profileRow(getString(R.string.health_privacy_title)) {
                    startActivity(healthPrivacyIntent().putExtra("health_privacy_test_db", names.privacy))
                }, 6)
            }
        }
        preview?.let { showResult(content, it) }
    }

    private fun showResult(content: LinearLayout, result: HealthAnalysisPreview) {
        ui.add(content, ui.text(getString(R.string.health_assistant_result), 18f, bold = true), 18)
        val priority = plan?.factKeys.orEmpty()
        result.facts.sortedBy { priority.indexOf(it.key).takeIf { index -> index >= 0 } ?: Int.MAX_VALUE }.forEach { fact ->
            val stat = fact.stat
            ui.add(content, ui.text(text.title(stat.metric), 16f, bold = true).apply { tag = "health-assistant-fact-${stat.metric.name}" }, 12)
            if (result.focus == HealthAnalysisFocus.CHANGES) ui.add(content, ui.text(text.summary(stat)), 4)
            ui.add(content, ui.text(text.coverage(stat), 13f, muted = true), 4)
            fact.refs.forEach { ref ->
                val date = Instant.ofEpochMilli(ref.time).atZone(zone).toLocalDate()
                ui.add(content, ui.profileRow(getString(if (ref.baseline) R.string.health_assistant_source_baseline
                    else R.string.health_assistant_source_recent, date),
                    getString(healthRecordSourceResource(ref.source))) {
                    if (names.fixture == null) startActivity(Intent(this, HealthRecordRevisionActivity::class.java)
                        .putExtra("health_record", ref.id).putExtra("health_revision", ref.revision))
                }.apply { tag = "health-assistant-source" }, 2)
            }
        }
        if (result.weekly.scope.hasBaseline) text.comparison(result.weekly).forEach { ui.add(content, ui.text(it), 10) }
        result.profile?.let { profile ->
            ui.add(content, ui.text(getString(R.string.health_assistant_profile_self_reported), 16f, bold = true), 16)
            profile.fields.forEach { (field, value) ->
                ui.add(content, ui.text(getString(R.string.health_assistant_profile_value,
                    getString(field.titleResource()), healthProfileDisplay(field, value)), 14f).apply {
                    tag = "health-assistant-profile-${field.name}"
                }, 6)
            }
            profile.entries.groupBy { it.kind }.toSortedMap().forEach { (kind, entries) ->
                ui.add(content, ui.text(getString(kind.titleResource()), 14f, bold = true), 10)
                entries.forEach { entry ->
                    ui.add(content, ui.text(entry.name, 14f, bold = true).apply {
                        tag = "health-assistant-background-result-${entry.id}"
                    }, 6)
                    if (entry.detail.isNotBlank()) ui.add(content, ui.text(entry.detail, 14f), 4)
                    if (entry.dose.isNotBlank()) ui.add(content, ui.text(getString(R.string.health_assistant_profile_value,
                        getString(R.string.health_profile_dose), entry.dose), 14f), 4)
                    if (entry.timing.isNotBlank()) ui.add(content, ui.text(getString(R.string.health_assistant_profile_value,
                        getString(R.string.health_profile_timing), entry.timing), 14f), 4)
                }
            }
        }
        ui.add(content, ui.text(getString(R.string.health_not_diagnosis), 13f, muted = true), 12)
        val actions = plan?.actions ?: when (focus) {
            HealthAnalysisFocus.CHANGES -> listOf(HealthAnalysisAction.WEEKLY_REPORT, HealthAnalysisAction.ADD_RECORD)
            else -> listOf(HealthAnalysisAction.ADD_RECORD, HealthAnalysisAction.RECORD_REMINDER)
        }
        actions.forEach { action ->
            val (label, intent) = when (action) {
                HealthAnalysisAction.ADD_RECORD -> R.string.health_manual to
                    Intent(this, HealthCenterActivity::class.java).putExtra("health_manual", true)
                HealthAnalysisAction.RECORD_REMINDER -> R.string.health_reminder_title to Intent(this, HealthReminderActivity::class.java)
                HealthAnalysisAction.WEEKLY_REPORT -> R.string.health_weekly_title to Intent(this, HealthWeeklyActivity::class.java)
            }
            ui.add(content, ui.profileRow(getString(label)) { if (names.fixture == null) startActivity(intent) }, 6)
        }
        if (result.hasData && names.fixture == null) ui.add(content, ui.command(R.string.health_assistant_online) {
            chooseProvider(result)
        }.apply { isEnabled = notice != R.string.health_assistant_sending }, 14)
    }

    private fun calculate() {
        val scope = selection()
        val question = focus
        val fields = profileFields
        val entries = background.mapValues { it.value.token }
        reset(R.string.health_loading)
        val cancel = CancellationSignal().also { signal = it }
        work({ HealthAnalysis.prepare(applicationContext, names, scope, question, cancel, fields, entries) }) {
            preview = it
            notice = if (it.hasData) null else R.string.health_assistant_no_data
            render()
        }
    }

    private fun chooseProvider(result: HealthAnalysisPreview) {
        notice = R.string.health_assistant_sending
        render()
        work({
            HealthAnalysis.requireCurrent(applicationContext, names, result, online = true)
            HealthAnalysisProvider.targets(applicationContext).ifEmpty { throw HealthAnalysisNoModel() }
        }, online = true) { targets ->
            notice = null
            render()
            dialog = AlertDialog.Builder(this).setTitle(R.string.health_assistant_online)
                .setItems(targets.map { "${it.label}\n${it.destination}" }.toTypedArray()) { _, index ->
                    confirm(result, targets[index])
                }.setNegativeButton(android.R.string.cancel, null).show()
        }
    }

    private fun confirm(result: HealthAnalysisPreview, target: HealthAnalysisTarget) {
        if (preview !== result) return
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_assistant_consent)
            .setMessage(getString(R.string.health_assistant_disclosure, target.destination, HealthAnalysis.payload(result).toString(2)))
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.health_assistant_send) { _, _ ->
                if (preview === result) {
                    notice = R.string.health_assistant_sending
                    render()
                    work({
                        HealthAnalysis.explain(applicationContext, names, result, target.destination) { data, guard ->
                            HealthAnalysisProvider.explain(applicationContext, target, data, guard)
                        }
                    }, online = true) {
                        plan = it
                        notice = R.string.health_assistant_verified
                        render()
                    }
                }
            }.show()
    }

    private fun <T> work(read: suspend () -> T, online: Boolean = false, success: (T) -> Unit) {
        val request = ++generation
        job?.cancel()
        job = tasks.launch {
            try {
                val value = withContext(Dispatchers.IO) { read() }
                if (active && generation == request) success(value)
            } catch (failure: Exception) {
                if (failure is CancellationException) throw failure
                if (!active || generation != request) return@launch
                when (failure) {
                    is HealthAnalysisProfileChanged -> reset(R.string.health_assistant_profile_changed)
                    is HealthAnalysisProfileBlocked -> reset(R.string.health_assistant_profile_blocked)
                    is HealthWeeklyChanged -> reset(R.string.health_assistant_changed)
                    is HealthAccessBlocked -> reset(if (online) R.string.health_assistant_online_blocked else R.string.health_assistant_blocked)
                    else -> {
                        notice = when (failure) {
                            is HealthAnalysisNoModel -> R.string.health_assistant_no_model
                            is HealthAnalysisInvalidReply -> R.string.health_assistant_invalid
                            else -> if (online) R.string.health_assistant_network_error else R.string.health_storage_error
                        }
                        render()
                    }
                }
            }
        }
    }

    private fun chooseDate() {
        dialog = DatePickerDialog(this, { _, year, month, day ->
            end = LocalDate.of(year, month + 1, day)
            reset()
        }, end.year, end.monthValue - 1, end.dayOfMonth).apply {
            datePicker.minDate = LocalDate.of(1970, 1, 22).atStartOfDay(zone).toInstant().toEpochMilli()
            datePicker.maxDate = LocalDate.now(zone).minusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
            show()
        }
    }

    private fun chooseMetrics() {
        val selected = metrics.toMutableSet()
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_weekly_metrics)
            .setMultiChoiceItems(healthWeeklyMetrics.map(text::title).toTypedArray(),
                healthWeeklyMetrics.map { it in metrics }.toBooleanArray()) { prompt, index, checked ->
                if (checked) selected += healthWeeklyMetrics[index] else selected -= healthWeeklyMetrics[index]
                (prompt as AlertDialog).getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = selected.isNotEmpty()
            }.setNegativeButton(android.R.string.cancel, null).setPositiveButton(android.R.string.ok) { _, _ ->
                metrics = selected.toSet()
                reset()
            }.show()
    }

    private fun chooseFocus() {
        val choices = HealthAnalysisFocus.entries
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_assistant_question)
            .setItems(choices.map { getString(focusLabel(it)) }.toTypedArray()) { _, index ->
                focus = choices[index]
                reset()
            }.setNegativeButton(android.R.string.cancel, null).show()
    }

    private fun chooseProfile() {
        val selected = profileFields.toMutableSet()
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_assistant_profile)
            .setMultiChoiceItems(healthAnalysisProfileFields.map { getString(it.titleResource()) }.toTypedArray(),
                healthAnalysisProfileFields.map { it in selected }.toBooleanArray()) { _, index, checked ->
                val field = healthAnalysisProfileFields[index]
                if (checked) selected += field else selected -= field
            }
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(android.R.string.ok) { _, _ ->
                if (profileFields != selected) {
                    profileFields = selected.toSet()
                    reset()
                }
            }.show()
    }

    private fun chooseBackground() {
        dialog = chooseHealthAnalysisBackground(tasks, names, background,
            blocked = { reset(R.string.health_assistant_profile_blocked) }) { selected ->
            if (selected != background) {
                background = selected
                reset()
            }
        }
    }

    private fun focusLabel(value: HealthAnalysisFocus) = when (value) {
        HealthAnalysisFocus.CHANGES -> R.string.health_assistant_changes
        HealthAnalysisFocus.COVERAGE -> R.string.health_assistant_coverage
        HealthAnalysisFocus.NEXT_RECORDS -> R.string.health_assistant_next_records
    }
}
