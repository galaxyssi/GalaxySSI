package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.content.Intent
import android.content.res.ColorStateList
import android.database.ContentObserver
import android.graphics.Rect
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.core.view.OneShotPreDrawListener
import androidx.core.widget.doAfterTextChanged
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
    private var preview: HealthAnalysisInput? = null
    private var trend: HealthTrendAnalysisHandoff? = null
    private var plan: HealthAnalysisPlan? = null
    private var notice: Int? = null
    private var gateway: HealthAnalysisGateway = HealthAnalysisProvider
    private var followUpDraft = ""
    private val followUps = ArrayList<Pair<String, HealthFollowUpAnswer>>()
    private var followUpStatus = false
    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            if (active && (preview != null || job?.isActive == true || dialog?.isShowing == true))
                reset(changedMessage())
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
        names = fixture?.let(::HealthOverviewDatabases) ?: intent.healthNavigationDatabases()
        if (intent.hasExtra(HEALTH_TREND_ANALYSIS_VERSION)) {
            trend = intent.healthTrendAnalysisHandoff()
            if (trend == null) { finish(); return }
        }
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        body = healthProfileBody(R.string.health_assistant_title) { finish() }
    }

    override fun onResume() {
        super.onResume()
        if (!::body.isInitialized) return
        active = true
        contentResolver.registerContentObserver(HealthRecordStore.changes(this, names.records), false, observer)
        contentResolver.registerContentObserver(HealthPrivacyStore.changes(this, names.privacy), false, privacyObserver)
        contentResolver.registerContentObserver(HealthProfileStore.changes(this, names.profile), false, profileObserver)
        render()
    }

    override fun onPause() {
        if (!::body.isInitialized) { super.onPause(); return }
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

    internal fun useFixtureGateway(value: HealthAnalysisGateway) {
        check(BuildConfig.DEBUG && names.fixture != null)
        gateway = value
    }

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
        followUpDraft = ""
        followUps.clear()
        followUpStatus = false
        notice = message
        if (active) render()
    }

    private fun selection() = HealthWeeklyScope(end, zone, metrics, comparison = focus == HealthAnalysisFocus.CHANGES)
    private fun changedMessage() = if (trend == null) R.string.health_assistant_changed else R.string.health_trend_analysis_changed

    private fun render(reveal: String? = null) {
        val content = healthProfileContent(body)
        content.addView(ui.text(getString(R.string.health_assistant_scope), 19f, bold = true))
        val trendScope = trend
        if (trendScope == null) showWeeklyScope(content) else showTrendScope(content, trendScope.spec)
        if (notice == R.string.health_trend_analysis_changed) {
            ui.add(content, ui.command(R.string.health_trend_return) { finish() }, 12)
        } else if (preview == null) ui.add(content, ui.command(R.string.health_assistant_calculate) { calculate() }.apply {
            tag = "health-assistant-calculate"
            isEnabled = notice != R.string.health_loading
        }, 12)
        notice?.takeUnless { followUpStatus }?.let { message ->
            ui.add(content, ui.text(getString(message), 14f, muted = true).apply { tag = "health-assistant-status" }, 12)
            if (message == R.string.health_assistant_blocked || message == R.string.health_assistant_online_blocked ||
                message == R.string.health_assistant_profile_blocked) {
                ui.add(content, ui.profileRow(getString(R.string.health_privacy_title)) {
                    startActivity(healthPrivacyIntent().putExtra("health_privacy_test_db", names.privacy))
                }, 6)
            }
        }
        preview?.let { showResult(content, it) }
        if (reveal != null) {
            val scroll = body.getChildAt(0) as ScrollView
            content.findViewWithTag<View>(reveal)?.let { target ->
                OneShotPreDrawListener.add(scroll) {
                    if (active && scroll.parent === body) {
                        val rect = Rect().also(target::getDrawingRect)
                        scroll.offsetDescendantRectToMyCoords(target, rect)
                        scroll.scrollTo(0, rect.top)
                    }
                }
            }
        }
    }

    private fun showWeeklyScope(content: LinearLayout) {
        val scope = selection()
        ui.add(content, ui.profileRow(text.range(scope)) { chooseDate() }.apply { tag = "health-assistant-date" }, 8)
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
    }

    private fun showTrendScope(content: LinearLayout, spec: HealthTrendSpec) {
        val unit = spec.unit.ifBlank { getString(R.string.health_unit_not_applicable) }
        ui.add(content, ui.card().apply {
            tag = "health-trend-analysis-scope"
            addView(ui.text(getString(spec.metric.titleResource()), 16f, bold = true))
            ui.add(this, ui.text(getString(R.string.health_trend_analysis_period, spec.first, spec.last, spec.zone.id)), 6)
            ui.add(this, ui.text(getString(R.string.health_trend_analysis_source, healthTrendSourceLabel(spec))), 6)
            ui.add(this, ui.text(getString(R.string.health_trend_analysis_unit, unit, getString(spec.aggregation.titleResource()))), 6)
        }, 8)
        ui.add(content, ui.text(getString(R.string.health_trend_analysis_scope), 13f, muted = true), 8)
    }

    private fun showResult(content: LinearLayout, result: HealthAnalysisInput) {
        ui.add(content, ui.text(getString(R.string.health_assistant_result), 18f, bold = true), 18)
        val priority = plan?.factKeys.orEmpty()
        val keys = result.factKeys.sortedBy { priority.indexOf(it).takeIf { index -> index >= 0 } ?: Int.MAX_VALUE }
        when (result) {
            is HealthAnalysisPreview -> showWeeklyResult(content, result, keys)
            is HealthTrendAnalysisPreview -> {
                showTrendCoverage(content, result)
                showTrendFacts(content, result, keys, changes = true, sources = true)
            }
        }
        ui.add(content, ui.text(getString(R.string.health_not_diagnosis), 13f, muted = true), 12)
        val actions = plan?.actions ?: when {
            result is HealthTrendAnalysisPreview -> listOf(HealthAnalysisAction.ADD_RECORD)
            focus == HealthAnalysisFocus.CHANGES -> listOf(HealthAnalysisAction.WEEKLY_REPORT, HealthAnalysisAction.ADD_RECORD)
            else -> listOf(HealthAnalysisAction.ADD_RECORD, HealthAnalysisAction.RECORD_REMINDER)
        }
        showActions(content, result, actions)
        if (result.hasData && (names.fixture == null || gateway !== HealthAnalysisProvider)) {
            ui.add(content, ui.command(R.string.health_assistant_online) {
                chooseProvider(result)
            }.apply { isEnabled = !onlineBusy() }, 14)
            followUps.forEachIndexed { index, (question, answer) -> showFollowUp(content, result, index, question, answer) }
            showComposer(content, result)
        }
    }

    private fun showWeeklyResult(content: LinearLayout, result: HealthAnalysisPreview, keys: List<String>) {
        keys.map(result.facts.associateBy { it.key }::getValue).forEach { fact ->
            val stat = fact.stat
            ui.add(content, ui.text(text.title(stat.metric), 16f, bold = true).apply { tag = "health-assistant-fact-${stat.metric.name}" }, 12)
            if (result.focus == HealthAnalysisFocus.CHANGES) ui.add(content, ui.text(text.summary(stat)), 4)
            ui.add(content, ui.text(text.coverage(stat), 13f, muted = true), 4)
            showSources(content, fact, "health-assistant-source")
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
    }

    private fun showTrendCoverage(content: LinearLayout, result: HealthTrendAnalysisPreview) {
        val spec = result.handoff.spec
        ui.add(content, ui.text(getString(R.string.health_trend_counts, result.numericRecords, result.numericDays,
            result.recordedDays, spec.days - result.recordedDays), 14f).apply { tag = "health-trend-analysis-coverage" }, 8)
        ui.add(content, ui.text(getString(R.string.health_trend_excluded, result.nonNumeric, result.otherUnits), 13f, muted = true), 6)
    }

    private fun showTrendFacts(content: LinearLayout, result: HealthTrendAnalysisPreview, keys: List<String>,
                               changes: Boolean, sources: Boolean) {
        val spec = result.handoff.spec
        for (fact in keys.map(result.facts.associateBy { it.key }::getValue)) {
            val field = fact.first.field
            ui.add(content, ui.text(getString(healthFieldResource(field)), 16f, bold = true), 12)
            val points = if (fact.delta == null) listOf(fact.first) else listOf(fact.first, fact.last)
            if (changes) {
                val delta = fact.delta
                ui.add(content, ui.text(if (delta == null) getString(R.string.health_trend_analysis_one_point)
                    else getString(R.string.health_trend_analysis_delta, trendValue(delta.toPlainString(), spec.unit)), 14f)
                    .apply { tag = "health-trend-analysis-delta-$field" }, 4)
            }
            points.forEachIndexed { index, point ->
                val date = if (point.first == point.last) point.first.toString()
                    else getString(R.string.health_trend_chart_data_dates, point.first, point.last)
                val value = trendValue(point.value.toPlainString(), spec.unit)
                if (sources) ui.add(content, ui.profileRow(getString(R.string.health_trend_analysis_point, date, value),
                    getString(R.string.health_trend_analysis_open_records)) {
                    openTrendEvidence(result.handoff, point)
                }.apply { tag = "health-trend-analysis-source-$field-$index" }, 4)
                else if (changes) ui.add(content, ui.text(getString(R.string.health_trend_analysis_point, date, value)), 4)
            }
        }
    }

    private fun trendValue(value: String, unit: String) = if (unit.isBlank()) value else "$value $unit"

    private fun openTrendEvidence(handoff: HealthTrendAnalysisHandoff, point: HealthTrendPoint) {
        startActivity(Intent(this, HealthTrendRecordsActivity::class.java)
            .putHealthTrend(handoff.spec.copy(first = point.first, last = point.last)).putHealthNavigationFixture(names)
            .putExtra("health_privacy_test_db", names.privacy).putExtra("health_numeric", true)
            .putExtra("health_point_field", point.field).putExtra("health_version", handoff.version))
    }

    private fun showSources(content: LinearLayout, fact: HealthAnalysisFact, rowTag: String) {
        fact.refs.forEach { ref ->
            val date = Instant.ofEpochMilli(ref.time).atZone(zone).toLocalDate()
            ui.add(content, ui.profileRow(getString(if (ref.baseline) R.string.health_assistant_source_baseline
                else R.string.health_assistant_source_recent, date), getString(healthRecordSourceResource(ref.source))) {
                startActivity(Intent(this, HealthRecordRevisionActivity::class.java).putHealthNavigationFixture(names)
                    .putExtra("health_record", ref.id).putExtra("health_revision", ref.revision))
            }.apply { tag = rowTag }, 2)
        }
    }

    private fun showActions(content: LinearLayout, result: HealthAnalysisInput, actions: List<HealthAnalysisAction>) {
        actions.forEach { action ->
            val (label, intent) = when (action) {
                HealthAnalysisAction.ADD_RECORD -> R.string.health_manual to
                    Intent(this, HealthCenterActivity::class.java).putExtra("health_manual", true).apply {
                        trend?.spec?.metric?.let { putExtra("health_metric", it.name) }
                    }
                HealthAnalysisAction.RECORD_REMINDER -> R.string.health_reminder_title to Intent(this, HealthReminderActivity::class.java)
                HealthAnalysisAction.WEEKLY_REPORT -> R.string.health_weekly_title to Intent(this, HealthWeeklyActivity::class.java)
                    .putHealthWeeklyHandoff((result as HealthAnalysisPreview).weekly.stamp).putHealthNavigationFixture(names)
            }
            ui.add(content, ui.profileRow(getString(label)) {
                if (names.fixture == null || action == HealthAnalysisAction.WEEKLY_REPORT) startActivity(intent)
            }.apply { tag = "health-assistant-action-${action.name}" }, 6)
        }
    }

    private fun showFollowUp(content: LinearLayout, result: HealthAnalysisInput, index: Int, question: String, answer: HealthFollowUpAnswer) {
        val turn = ui.column().apply { tag = "health-follow-up-turn-$index" }
        turn.addView(ui.line().apply {
            gravity = Gravity.END
            addView(ui.text(question, 16f).apply {
                setPadding(ui.dp(14), ui.dp(10), ui.dp(14), ui.dp(10))
                background = ui.background(getColor(R.color.health_data_summary_fill), radius = 8)
                setTextIsSelectable(true)
            }, LinearLayout.LayoutParams(-2, -2))
        })
        ui.add(turn, ui.text(getString(R.string.health_assistant_title), 15f, bold = true), 14)
        ui.add(turn, ui.card().apply {
            when (answer.status) {
                HealthFollowUpStatus.OUT_OF_SCOPE -> addView(ui.text(getString(R.string.health_follow_up_outside)))
                HealthFollowUpStatus.PARTIAL -> addView(ui.text(getString(R.string.health_follow_up_partial)).apply {
                    setTextColor(getColor(R.color.health_data_warning_text))
                })
                else -> Unit
            }
            if (result is HealthTrendAnalysisPreview) {
                if (answer.sections.any { it.topic == HealthFollowUpTopic.COVERAGE }) showTrendCoverage(this, result)
                val changes = answer.sections.firstOrNull { it.topic == HealthFollowUpTopic.CHANGES }?.facts.orEmpty()
                val cited = answer.sections.flatMap { it.facts }.distinct()
                showTrendFacts(this, result, changes, changes = true, sources = true)
                showTrendFacts(this, result, cited - changes.toSet(), changes = false, sources = true)
                if (cited.isNotEmpty()) ui.add(this, ui.text(getString(R.string.health_not_diagnosis), 13f, muted = true), 8)
            } else if (result is HealthAnalysisPreview) {
                showWeeklyFollowUpEvidence(this, result, answer)
            }
            if (answer.actions.isNotEmpty()) {
                ui.add(this, ui.text(getString(R.string.health_follow_up_actions), 14f, bold = true), if (childCount > 0) 12 else 0)
                showActions(this, result, answer.actions)
            }
        }, 8)
        ui.add(content, turn, 18)
    }

    private fun showWeeklyFollowUpEvidence(content: LinearLayout, result: HealthAnalysisPreview, answer: HealthFollowUpAnswer) {
        val facts = result.facts.associateBy { it.key }
        val covered = answer.sections.firstOrNull { it.topic == HealthFollowUpTopic.COVERAGE }?.facts.orEmpty()
        for (section in answer.sections.filter { it.topic != HealthFollowUpTopic.SOURCES }) {
            val title = if (section.topic == HealthFollowUpTopic.CHANGES) R.string.health_follow_up_changes
                else R.string.health_follow_up_coverage
            ui.add(content, ui.text(getString(title), 15f, bold = true), if (content.childCount > 0) 10 else 0)
            for (key in section.facts) {
                val fact = facts.getValue(key)
                ui.add(content, ui.text(text.title(fact.stat.metric), 14f, bold = true), 8)
                if (section.topic == HealthFollowUpTopic.CHANGES) {
                    ui.add(content, ui.text(text.summary(fact.stat), 15f), 4)
                    if (fact.stat.metric == HealthMetric.SLEEP_DURATION) text.comparison(result.weekly).forEach {
                        ui.add(content, ui.text(it, 14f), 4)
                    }
                }
                if (section.topic == HealthFollowUpTopic.COVERAGE || key !in covered) {
                    ui.add(content, ui.text(text.coverage(fact.stat), 13f, muted = true), 4)
                }
            }
        }
        val cited = answer.sections.flatMap { it.facts }.distinct().map(facts::getValue)
        if (cited.isNotEmpty()) {
            ui.add(content, ui.text(getString(R.string.health_follow_up_sources), 15f, bold = true), if (content.childCount > 0) 12 else 0)
            for (fact in cited) {
                if (cited.size > 1) ui.add(content, ui.text(text.title(fact.stat.metric), 14f, bold = true), 6)
                if (fact.refs.isEmpty()) {
                    ui.add(content, ui.text(getString(R.string.health_follow_up_no_source), 13f, muted = true), 4)
                }
                showSources(content, fact, "health-follow-up-source")
            }
            ui.add(content, ui.text(getString(R.string.health_not_diagnosis), 13f, muted = true), 8)
        }
    }

    private fun onlineBusy() = notice == R.string.health_assistant_sending || notice == R.string.health_follow_up_checking

    private fun showComposer(content: LinearLayout, result: HealthAnalysisInput) {
        ui.add(content, ui.column().apply {
            tag = "health-follow-up-composer"
            background = ui.background(stroke = getColor(R.color.separator), radius = 8)
            setPadding(ui.dp(12), ui.dp(6), ui.dp(8), ui.dp(8))
            val input = healthProfileInput(followUpDraft, HEALTH_FOLLOW_UP_MAX_LENGTH, multiline = true).apply {
                tag = "health-follow-up-input"
                hint = getString(R.string.health_follow_up_hint)
                minLines = 2
                maxLines = 6
                isEnabled = !onlineBusy()
                background = null
            }
            addView(input, LinearLayout.LayoutParams(-1, -2))
            addView(ui.line().apply {
                gravity = Gravity.END
                val send = ui.icon(R.drawable.ic_agent_arrow_up, R.string.health_follow_up_send) {
                    if (!onlineBusy() && preview === result) {
                        HealthFollowUpQuestion.from(followUpDraft, followUps.lastOrNull()?.second)?.let { chooseProvider(result, it) }
                    }
                }.apply {
                    tag = "health-follow-up-send"
                    background = ui.background(getColor(R.color.accent_green), radius = 8)
                    imageTintList = ColorStateList.valueOf(android.graphics.Color.rgb(8, 40, 29))
                }
                fun enabled() {
                    send.isEnabled = !onlineBusy() && HealthFollowUpQuestion.from(followUpDraft) != null
                    send.alpha = if (send.isEnabled) 1f else .45f
                }
                input.doAfterTextChanged { draft -> followUpDraft = draft?.toString().orEmpty(); enabled() }
                enabled()
                addView(send)
            })
            if (followUpStatus) notice?.let {
                ui.add(this, ui.text(getString(it), 14f).apply {
                    tag = "health-assistant-status"
                    accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
                }, 8)
                if (it == R.string.health_assistant_online_blocked) ui.add(this, ui.profileRow(getString(R.string.health_privacy_title)) {
                    startActivity(healthPrivacyIntent().putExtra("health_privacy_test_db", names.privacy))
                })
            }
        }, 16)
    }

    private fun calculate() {
        val trendScope = trend
        val scope = if (trendScope == null) selection() else null
        val question = focus
        val fields = profileFields
        val entries = background.mapValues { it.value.token }
        reset(R.string.health_loading)
        val cancel = CancellationSignal().also { signal = it }
        work({
            if (trendScope != null) HealthTrendAnalysis.prepare(applicationContext, names, trendScope, cancel)
            else HealthAnalysis.prepare(applicationContext, names, requireNotNull(scope), question, cancel, fields, entries)
        }) {
            preview = it
            notice = if (it.hasData) null else R.string.health_assistant_no_data
            render()
        }
    }

    private fun chooseProvider(result: HealthAnalysisInput, question: HealthFollowUpQuestion? = null) {
        if (onlineBusy()) return
        followUpStatus = question != null
        val reveal = if (question == null) null else "health-follow-up-composer"
        notice = if (question == null) R.string.health_assistant_sending else R.string.health_follow_up_checking
        render(reveal)
        work({
            HealthAnalysis.requireCurrent(applicationContext, names, result, online = true)
            gateway.targets(applicationContext).ifEmpty { throw HealthAnalysisNoModel() }
        }, online = true) { targets ->
            notice = null
            render(reveal)
            dialog = AlertDialog.Builder(this).setTitle(if (question == null) R.string.health_assistant_online else R.string.health_follow_up_model)
                .setItems(targets.map { "${it.label}\n${it.destination}" }.toTypedArray()) { _, index ->
                    confirm(result, targets[index], question)
                }.setNegativeButton(android.R.string.cancel, null).show()
        }
    }

    private fun confirm(result: HealthAnalysisInput, target: HealthAnalysisTarget, question: HealthFollowUpQuestion?) {
        if (preview !== result) return
        val payload = if (question == null) HealthAnalysis.payload(result) else HealthAnalysisFollowUp.payload(result, question)
        val disclosure = if (question == null) R.string.health_assistant_disclosure else R.string.health_follow_up_disclosure
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_assistant_consent)
            .setMessage(getString(disclosure, target.destination, payload.toString(2)))
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.health_assistant_send) { _, _ ->
                if (preview === result) {
                    notice = R.string.health_assistant_sending
                    if (question == null) {
                        render()
                        work({
                            HealthAnalysis.explain(applicationContext, names, result, target.destination) { data, guard ->
                                gateway.exchange(applicationContext, target, data, HealthAnalysisRequest.SUMMARY, guard)
                            }
                        }, online = true) {
                            plan = it
                            notice = R.string.health_assistant_verified
                            render()
                        }
                    } else {
                        render("health-follow-up-composer")
                        work({
                            HealthAnalysis.followUp(applicationContext, names, result, target.destination, question) { data, guard ->
                                gateway.exchange(applicationContext, target, data, HealthAnalysisRequest.FOLLOW_UP, guard)
                            }
                        }, online = true) { answer ->
                            followUps += question.text to answer
                            followUpDraft = ""
                            notice = null
                            render("health-follow-up-turn-${followUps.lastIndex}")
                        }
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
                    is HealthTrendChangedException -> reset(R.string.health_trend_analysis_changed)
                    is HealthAccessBlocked -> reset(if (online) R.string.health_assistant_online_blocked else R.string.health_assistant_blocked)
                    else -> {
                        notice = when (failure) {
                            is HealthAnalysisNoModel -> R.string.health_assistant_no_model
                            is HealthAnalysisInvalidReply -> R.string.health_assistant_invalid
                            else -> if (online) R.string.health_assistant_network_error else R.string.health_storage_error
                        }
                        render(if (followUpStatus) "health-follow-up-composer" else null)
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
