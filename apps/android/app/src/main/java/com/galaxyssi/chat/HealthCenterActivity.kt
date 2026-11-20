package com.galaxyssi.chat

import android.Manifest
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputFilter
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import java.text.DateFormat
import java.time.ZoneId
import java.util.Date
import java.util.concurrent.Executors
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** A separate native page stack; health data never enters the chat transcript or generic agent memory. */
class HealthCenterActivity : ComponentActivity() {
    internal val ui by lazy { HealthCenterViews(this) }
    internal lateinit var body: LinearLayout
    private lateinit var title: TextView
    private lateinit var functionsButton: View
    private lateinit var root: LinearLayout
    private val worker = Executors.newSingleThreadExecutor()
    private val stepTasks = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var stepJob: Job? = null
    private var phoneSteps: HealthPhoneStepReading? = null
    private val stepPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted && active) startPhoneSteps()
        else if (!granted) Toast.makeText(this, R.string.health_phone_steps_permission, Toast.LENGTH_LONG).show()
    }
    internal val main = Handler(Looper.getMainLooper())
    private val overviewNames by lazy { intent.healthNavigationDatabases() }
    private val records by lazy { HealthRecordStore(applicationContext, overviewNames.records) }
    private val overview by lazy { HealthOverviewView(this, overviewNames) }
    internal var measurementPeriod: HealthMeasurementPeriod? = null
        private set
    internal var measurementAbnormal = false
        private set
    internal var measurementRecordsExpanded = false
    private var overviewBase: HealthOverviewSnapshot? = null
    private var displayedMeasurementPeriod: HealthMeasurementPeriod? = null
    @Volatile private var measurementGeneration = 0
    @Volatile private var measurementPickerGeneration = 0
    internal fun chooseMeasurementPeriod() {
        val picker = ++measurementPickerGeneration
        val current = { picker == measurementPickerGeneration }
        showHealthDialog(AlertDialog.Builder(this).setItems(arrayOf(getString(R.string.health_measurement_latest),
            getString(R.string.health_period_weeks), getString(R.string.health_period_months))) { _, index ->
            if (!current()) return@setItems
            if (index == 0) setMeasurementPeriod(null) else {
                val kind = HealthMeasurementPeriodKind.entries[index - 1]
                showHealthPeriodPicker(this, R.string.health_period_choose, ::showHealthDialog, { before, done ->
                    queryCancellable({ store, check ->
                        val guard = { check(); if (!current()) throw java.util.concurrent.CancellationException() }
                        guard()
                        val result = runCatching { HealthPrivacyStore.track(applicationContext,
                            HealthAccessScope(HealthAccessPurpose.OVERVIEW, HealthMeasurementPeriods.metrics), overviewNames.privacy) {
                            HealthMeasurementPeriods.page(store, kind, System.currentTimeMillis(), ZoneId.systemDefault(), before, guard)
                        } }
                        guard(); result.getOrThrow()
                    }) { if (current()) done(it) }
                }, { if (current()) setMeasurementPeriod(it) })
            }
        }.setNegativeButton(android.R.string.cancel, null).create())
    }
    internal fun setMeasurementPeriod(period: HealthMeasurementPeriod?) {
        measurementPickerGeneration++
        if (measurementPeriod == period) return
        measurementPeriod = period
        if (active && route == "overview") refreshOverviewMeasurements()
    }
    private fun refreshOverviewMeasurements() {
        val base = overviewBase ?: return
        val period = measurementPeriod
        val token = ++measurementGeneration
        val pageToken = generation
        overview.setMeasurementsPending(true)
        worker.execute {
            val current = { active && !isDestroyed && pageToken == generation && token == measurementGeneration }
            val check = { if (!current()) throw java.util.concurrent.CancellationException() }
            val result = runCatching {
                check()
                HealthOverviewRepository.measurements(applicationContext, records, overviewNames, base, period, check).also { check() }
            }
            main.post {
                if (!current()) return@post
                result.fold({ snapshot ->
                    displayedMeasurementPeriod = period
                    measurementRecordsExpanded = false
                    overview.updateMeasurements(snapshot)
                }, { failure ->
                    if (failure is java.util.concurrent.CancellationException) return@post
                    measurementPeriod = displayedMeasurementPeriod
                    overview.setMeasurementsPending(false)
                    Toast.makeText(this, if (failure is HealthAccessBlocked) R.string.health_privacy_trend_blocked
                        else R.string.health_storage_error, Toast.LENGTH_LONG).show()
                })
            }
        }
    }
    internal fun filterMeasurementAbnormal(value: Boolean) {
        if (measurementAbnormal == value) return
        measurementAbnormal = value
        if (active && route == "overview") overview.filterMeasurements()
    }
    internal fun compareMeasurements() = startActivity(Intent(this, HealthMeasurementPeriodsActivity::class.java)
        .putHealthNavigationFixture(overviewNames).putExtra("health_period", measurementPeriod?.key))
    internal fun metricTrend(record: HealthObservation) = startActivity(healthComparableTrendIntent(this, overviewNames, record))
    private val cycling = HealthCyclingView(this)
    internal fun cyclingTile() = cycling.tile(overviewNames.fixture != null)
    private val recordCenter by lazy { HealthRecordCenterView(this, overviewNames) }
    private var overviewScroll = 0
    private var recordCenterScroll = 0
    private val reloadOverview = Runnable { if (active && route in LIVE_SUMMARY_ROUTES) render() }
    private val overviewChanges = object : android.database.ContentObserver(main) {
        override fun onChange(selfChange: Boolean) {
            if (active && route in LIVE_SUMMARY_ROUTES) {
                main.removeCallbacks(reloadOverview)
                main.postDelayed(reloadOverview, 120)
            }
        }
    }
    private val overviewCareChanges = object : android.database.ContentObserver(main) {
        override fun onChange(selfChange: Boolean) {
            if (active && (route == "overview" || route == "overview_metric")) {
                main.removeCallbacks(reloadOverview)
                main.postDelayed(reloadOverview, 120)
            }
        }
    }
    private val overviewPrivacy = object : android.database.ContentObserver(main) {
        override fun onChange(selfChange: Boolean) {
            if (active && (route == "overview" || route == "overview_metric")) {
                measurementPeriod = null; measurementAbnormal = false; measurementRecordsExpanded = false
                sensitiveDialogs.toList().forEach { it.dismiss() }
                main.removeCallbacks(reloadOverview)
                render()
            }
        }
    }
    @Volatile private var active = false
    @Volatile private var generation = 0
    private var route = "overview"
    private var selected = HealthMetric.BLOOD_PRESSURE
    private var recordId = ""
    private var undoDeletionRevision = 0
    private var reviewKey = ""
    private val backStack = ArrayDeque<Triple<String, HealthMetric, String>>()
    internal var editor: HealthManualEditor? = null
    internal var saving = false
    internal fun pickHealthFile() = startActivity(healthCaptureIntent(this, overviewNames, HealthCaptureEntry.FILE))
    internal val stagingOcrReview get() = route == "review" && intent.getBooleanExtra("health_stage_ocr_review", false)
    private val sensitiveDialogs = mutableSetOf<android.app.Dialog>()
    private var nextPage: HealthPageCursor? = null
    private var pageAfter: HealthPageCursor? = null
    private val pageHistory = mutableListOf<HealthPageCursor?>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        measurementPeriod = HealthMeasurementPeriod.parse(savedInstanceState?.getString("measurementPeriod"))
        measurementAbnormal = savedInstanceState?.getBoolean("measurementAbnormal") ?: false
        measurementRecordsExpanded = savedInstanceState?.getBoolean("measurementRecordsExpanded") ?: false
        window.statusBarColor = getColor(R.color.page_bg)
        window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        reviewKey = savedInstanceState?.getString("review").orEmpty().ifBlank { intent.getStringExtra("review_draft").orEmpty() }
        intent.getStringExtra("health_metric")?.let { name -> HealthMetric.entries.firstOrNull { it.name == name }?.let { selected = it } }
        if (reviewKey.isNotBlank()) {
            require(reviewKey.matches(Regex("ocr:[0-9a-f-]{36}:[1-9][0-9]*:[a-zA-Z0-9_-]{1,80}")))
            route = "review"
        } else if (savedInstanceState == null && intent.getBooleanExtra("health_functions", false)) {
            route = "functions"
        } else if (savedInstanceState == null && intent.getBooleanExtra("health_manual", false)) {
            route = "manual"
        } else if (savedInstanceState == null && intent.getBooleanExtra("health_metric_records", false)) {
            route = "metric_records"
        } else if (savedInstanceState == null && intent.getBooleanExtra("health_records", false)) {
            route = "records"
        } else if (savedInstanceState == null && !intent.getStringExtra("health_record").isNullOrBlank()) {
            recordId = intent.getStringExtra("health_record").orEmpty()
            require(runCatching { java.util.UUID.fromString(recordId).toString() == recordId }.getOrDefault(false))
            route = if (intent.getBooleanExtra("health_history", false)) "history" else "detail"
        }
        savedInstanceState?.let { state ->
            route = state.getString("route", "overview").orEmpty().ifBlank { "overview" }.let { if (it == "import") "overview" else it }
            selected = HealthMetric.entries.getOrElse(state.getInt("metric")) { HealthMetric.BLOOD_PRESSURE }
            recordId = state.getString("record", "").orEmpty()
            undoDeletionRevision = state.getInt("undoDeletionRevision").takeIf { route == "detail" } ?: 0
            overviewScroll = state.getInt("overviewScroll")
            recordCenterScroll = state.getInt("recordCenterScroll")
            state.getStringArrayList("stack")?.forEach { encoded ->
                val parts = encoded.split('|')
                if (parts.size == 3 && parts[0] != "import") backStack.addLast(Triple(parts[0], HealthMetric.valueOf(parts[1]), parts[2]))
            }
        }
        root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        functionsButton = ui.icon(R.drawable.ic_more_horizontal, R.string.health_functions) { open("functions") }
            .apply { tag = "health-functions" }
        root.addView(ui.toolbar(R.string.health_title, { back() }, functionsButton).apply {
            title = getChildAt(1) as TextView
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        body = ui.column()
        root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
    }
    override fun onStart() {
        super.onStart(); active = true
        contentResolver.registerContentObserver(HealthRecordStore.changes(this, overviewNames.records), false, overviewChanges)
        contentResolver.registerContentObserver(HealthRecordStore.syncIncidentChanges(this, overviewNames.records), false, overviewChanges)
        contentResolver.registerContentObserver(HealthConnectSettings.changes(this), false, overviewChanges)
        contentResolver.registerContentObserver(HealthOriginalStore.changesUri(this).buildUpon().appendPath("jobs").build(), false, overviewChanges)
        contentResolver.registerContentObserver(HealthTableScheduler.changes(this), false, overviewChanges)
        contentResolver.registerContentObserver(HealthReminderStore.changes(this, overviewNames.reminders), false, overviewChanges)
        contentResolver.registerContentObserver(HealthCareStore.changes(this, overviewNames.care), false, overviewCareChanges)
        contentResolver.registerContentObserver(HealthProfileStore.changes(this, overviewNames.profile), false, overviewCareChanges)
        contentResolver.registerContentObserver(HealthOriginalStore.changesUri(this).buildUpon().appendPath("originals").build(), false, overviewCareChanges)
        contentResolver.registerContentObserver(HealthPrivacyStore.changes(this, overviewNames.privacy), false, overviewPrivacy)
        render()
    }
    override fun onStop() {
        saveDraft()
        active = false; generation++
        clearTodaySteps()
        main.removeCallbacks(savePendingDraft); main.removeCallbacks(reloadOverview)
        contentResolver.unregisterContentObserver(overviewChanges); contentResolver.unregisterContentObserver(overviewPrivacy)
        contentResolver.unregisterContentObserver(overviewCareChanges)
        retainOverviewScroll()
        editor = null; body.removeAllViews()
        sensitiveDialogs.toList().forEach { it.dismiss() }; sensitiveDialogs.clear()
        super.onStop()
    }
    override fun onDestroy() {
        stepTasks.cancel()
        worker.execute { records.close() }; worker.shutdown()
        super.onDestroy()
    }
    override fun onSaveInstanceState(out: Bundle) {
        out.putString("measurementPeriod", measurementPeriod?.key)
        out.putBoolean("measurementAbnormal", measurementAbnormal); out.putBoolean("measurementRecordsExpanded", measurementRecordsExpanded)
        saveDraft()
        out.putString("route", route); out.putInt("metric", selected.ordinal); out.putString("record", recordId)
        if (route == "detail" && undoDeletionRevision > 0) out.putInt("undoDeletionRevision", undoDeletionRevision)
        out.putString("review", reviewKey)
        retainOverviewScroll(); out.putInt("overviewScroll", overviewScroll)
        out.putInt("recordCenterScroll", recordCenterScroll)
        out.putStringArrayList("stack", ArrayList(backStack.map { "${it.first}|${it.second.name}|${it.third}" }))
        super.onSaveInstanceState(out)
    }
    @Deprecated("Android activity back callback") override fun onBackPressed() = back()

    private fun back() {
        if (saving) return
        undoDeletionRevision = 0
        saveDraft()
        if (backStack.isEmpty()) { finish(); return }
        val previous = backStack.removeLast()
        route = previous.first; selected = previous.second; recordId = previous.third
        render()
    }
    internal fun open(destination: String, metric: HealthMetric = selected, id: String = "") {
        if (saving) return
        if (destination != "detail" || id != recordId) undoDeletionRevision = 0
        saveDraft()
        if (destination in RECORD_ROUTES && (route != destination || selected != metric)) {
            pageAfter = null; nextPage = null; pageHistory.clear()
        }
        if (route != destination || selected != metric || recordId != id) backStack.addLast(Triple(route, selected, recordId))
        route = destination; selected = metric; recordId = id
        render()
    }
    internal fun changeMetric(metric: HealthMetric) {
        if (saving) return
        saveDraft(); selected = metric; recordId = ""; render()
    }
    internal fun saveDraft() {
        if (saving) return
        val current = editor ?: return
        if (stagingOcrReview && !current.hasChanges) return
        val snapshot = current.snapshot()
        val draft = if (stagingOcrReview) snapshot.copy(evidence = snapshot.evidence?.copy(confirmed = false)) else snapshot
        worker.execute {
            if (runCatching { records.saveDraft(draft) }.isFailure) main.post {
                if (active && !isDestroyed) Toast.makeText(this, R.string.health_draft_error, Toast.LENGTH_LONG).show()
            }
        }
    }
    internal fun draftChanged() {
        main.removeCallbacks(savePendingDraft)
        main.postDelayed(savePendingDraft, 350)
    }
    internal fun showHealthDialog(dialog: android.app.Dialog) {
        sensitiveDialogs += dialog
        dialog.setOnDismissListener { sensitiveDialogs -= dialog }
        dialog.show()
    }

    internal fun editOverviewStepGoal(current: Int?) {
        val field = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER
            filters = arrayOf(InputFilter.LengthFilter(HealthOverviewGuidance.MAX_STEP_GOAL.toString().length))
            hint = getString(R.string.health_overview_steps_unit)
            if (current != null) setText(current.toString())
            selectAll()
        }
        fun save(goal: Int?) {
            query({ HealthOverviewStepGoalStore(applicationContext, overviewNames).save(goal) }) { render() }
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(R.string.health_overview_step_goal_title)
            .setView(ui.column().apply {
                setPadding(ui.dp(24), ui.dp(8), ui.dp(24), 0)
                addView(field, LinearLayout.LayoutParams(-1, -2))
            })
            .setNegativeButton(R.string.common_cancel, null)
            .setPositiveButton(R.string.common_save, null)
            .apply {
                if (current != null) setNeutralButton(R.string.health_overview_step_goal_remove) { _, _ -> save(null) }
            }.create()
        showHealthDialog(dialog)
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val value = field.text.toString().toIntOrNull()
            if (value == null || value !in 1..HealthOverviewGuidance.MAX_STEP_GOAL) {
                field.error = getString(R.string.health_overview_step_goal_invalid, HealthOverviewGuidance.MAX_STEP_GOAL)
            } else {
                save(value)
                dialog.dismiss()
            }
        }
    }

    private val savePendingDraft = Runnable { saveDraft() }

    internal fun <T> query(work: (HealthRecordStore) -> T, done: (T) -> Unit) = queryCancellable({ store, _ -> work(store) }, done)
    internal fun <T> queryCancellable(work: (HealthRecordStore, () -> Unit) -> T, done: (T) -> Unit) {
        val token = generation
        worker.execute {
            val check = { if (!active || token != generation) throw java.util.concurrent.CancellationException() }
            val result = runCatching { check(); work(records, check).also { check() } }
            main.post {
                if (!active || token != generation || isDestroyed) return@post
                result.fold(done) {
                    if (it is java.util.concurrent.CancellationException) return@post
                    Toast.makeText(this, getString(if (it is HealthAccessBlocked) R.string.health_privacy_trend_blocked else R.string.health_storage_error), Toast.LENGTH_LONG).show()
                    body.addView(ui.row(getString(R.string.common_retry)) { render() })
                }
            }
        }
    }
    private fun render() {
        retainOverviewScroll()
        clearTodaySteps()
        generation++; main.removeCallbacks(savePendingDraft); main.removeCallbacks(reloadOverview); editor = null; body.removeAllViews()
        functionsButton.visibility = if (route == "overview") View.VISIBLE else View.INVISIBLE
        title.text = getString(when (route) {
            "manual" -> R.string.health_manual
            "review" -> R.string.health_review_title
            "records" -> R.string.health_records
            "record_center" -> R.string.health_record_center
            "metric_records", "overview_history" -> selected.titleResource()
            "overview_metric" -> selected.titleResource()
            "detail" -> selected.titleResource()
            "history" -> R.string.health_revision_history
            "functions" -> R.string.health_functions
            else -> R.string.health_title
        })
        when (route) {
            "manual", "review" -> renderManual()
            "records", "metric_records", "overview_history" -> renderRecords()
            "overview_metric" -> renderOverviewMetric()
            "record_center" -> {
                val content = scrolling()
                val scroll = (content.parent as ScrollView).apply { tag = "health-record-center-scroll" }
                recordCenter.show(content) {
                    val position = recordCenterScroll
                    if (position > 0) scroll.post { if (active && scroll.parent === body) scroll.scrollTo(0, position) }
                }
            }
            "detail" -> renderDetail()
            "history" -> renderHistory()
            "functions" -> renderFunctions()
            else -> renderOverview()
        }
    }
    internal fun scrolling(): LinearLayout {
        val content = ui.column().apply {
            setPadding(ui.dp(16), ui.dp(if (route == "overview") 8 else 16), ui.dp(16), ui.dp(16))
        }
        body.addView(ScrollView(this).apply { isFillViewport = true; addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        return content
    }
    internal fun date(time: Long): String = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(time))
    private fun retainOverviewScroll() {
        (body.getChildAt(0) as? ScrollView)?.let {
            when (it.tag) {
                "health-overview-scroll" -> overviewScroll = it.scrollY
                "health-record-center-scroll" -> recordCenterScroll = it.scrollY
            }
        }
    }
    private fun renderOverview() {
        val content = scrolling()
        val scroll = (content.parent as ScrollView).apply { tag = "health-overview-scroll" }
        body.addView(overview.quicks(), LinearLayout.LayoutParams(-1, -2))
        content.addView(ui.text(getString(R.string.health_loading), 14f, muted = true))
        val now = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        val period = measurementPeriod
        queryCancellable({ store, check -> HealthOverviewRepository.load(applicationContext, store, overviewNames, now, zone).let { base ->
            base to HealthOverviewRepository.measurements(applicationContext, store, overviewNames, base, period, check)
        } }) { (base, snapshot) ->
            overviewBase = base
            displayedMeasurementPeriod = period
            overview.show(content, snapshot, period)
            if (period != measurementPeriod) refreshOverviewMeasurements()
            observePhoneSteps()
            val position = overviewScroll
            if (position > 0) scroll.post { if (active && scroll.parent === body) scroll.scrollTo(0, position) }
            val tomorrow = HealthOverviewPolicy.localDay(now, zone).plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
            main.postDelayed(reloadOverview, (tomorrow - System.currentTimeMillis()).coerceAtLeast(500))
        }
    }

    private fun renderOverviewMetric() {
        val content = scrolling()
        val metric = selected
        query({ store ->
            HealthOverviewRepository.metricDetail(applicationContext, store, overviewNames, metric,
                System.currentTimeMillis(), ZoneId.systemDefault())
        }) { detail ->
            if (metric == HealthMetric.GLUCOSE && detail.metric.record?.draft?.condition == "fasting") {
                title.setText(R.string.health_overview_fasting_glucose)
            }
            overview.showMetric(content, detail)
        }
    }

    internal fun openOverviewDiscussion(metric: HealthMetric, expectedConcern: String) {
        if (overviewNames.fixture != null || !active || route != "overview_metric" || selected != metric) return
        query({ store ->
            val record = store.overviewLatestSelf(metric, System.currentTimeMillis()) ?: return@query null
            val version = store.metricVersions(setOf(metric)).getValue(metric)
            val concern = HealthOverviewRepository.discussionConcern(applicationContext, overviewNames, record, version)
            if (expectedConcern != concern) null else HealthCareDiscussion.open(applicationContext, expectedConcern)
        }) { id ->
            if (id == null) {
                Toast.makeText(this, R.string.health_care_changed, Toast.LENGTH_SHORT).show()
                render()
            } else {
                startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", id))
            }
        }
    }

    private fun clearTodaySteps() {
        measurementGeneration++
        measurementPickerGeneration++
        overviewBase = null
        displayedMeasurementPeriod = null
        stepJob?.cancel()
        stepJob = null
        phoneSteps = null
        overview.clearTodaySteps()
    }

    private fun observePhoneSteps() {
        if (overviewNames.fixture != null) return
        val supported = HealthPhoneStepService.supported(this)
        if (!supported) {
            overview.updatePhoneSteps(null, supported = false)
            return
        }
        phoneSteps = HealthPhoneStepUpdates.readings.value
        overview.updatePhoneSteps(phoneSteps, supported = true)
        stepJob = stepTasks.launch {
            val stored = withContext(Dispatchers.IO) {
                runCatching {
                    val store = HealthPhoneStepStore(applicationContext)
                    store.enabled to store.load()
                }
            }
            if (HealthPhoneStepUpdates.readings.value == null) {
                phoneSteps = HealthPhoneStepReading(stored.getOrNull()?.second, failed = stored.isFailure)
                overview.updatePhoneSteps(phoneSteps, supported = true)
            }
            if (stored.getOrNull()?.first == true && HealthPhoneStepUpdates.readings.value?.let { it.active || it.failed } != true &&
                HealthPhoneStepService.hasPermission(this@HealthCenterActivity)) startPhoneSteps(resume = true)
            HealthPhoneStepUpdates.readings.collect { reading ->
                if (reading != null) {
                    phoneSteps = reading
                    overview.updatePhoneSteps(reading, supported = true)
                }
            }
        }
    }

    internal fun editPhoneSteps() {
        if (overviewNames.fixture != null || !HealthPhoneStepService.supported(this)) return
        if (phoneSteps?.active == true) {
            showHealthDialog(AlertDialog.Builder(this).setTitle(R.string.health_phone_steps_title)
                .setNegativeButton(R.string.common_cancel, null)
                .setPositiveButton(R.string.health_phone_steps_stop) { _, _ ->
                    startService(Intent(this, HealthPhoneStepService::class.java).setAction(HealthPhoneStepService.STOP))
                }.create())
        } else if (HealthPhoneStepService.hasPermission(this)) startPhoneSteps()
        else stepPermission.launch(Manifest.permission.ACTIVITY_RECOGNITION)
    }

    private fun startPhoneSteps(resume: Boolean = false) {
        val request = Intent(this, HealthPhoneStepService::class.java)
        if (!resume) request.action = HealthPhoneStepService.START
        runCatching { startForegroundService(request) }.onFailure {
            HealthPhoneStepUpdates.publish(HealthPhoneStepReading(phoneSteps?.ledger, failed = true))
        }
    }
    private fun renderFunctions() {
        val content = scrolling().apply { tag = "health-functions-list" }
        fun entry(icon: Int, label: Int, tag: String, action: () -> Unit) {
            content.addView(ui.navigationRow(icon, label, action).apply { this.tag = tag })
        }
        fun launch(type: Class<*>) = startActivity(android.content.Intent(this, type).putHealthNavigationFixture(overviewNames).apply {
            if (overviewNames.fixture != null) {
                putExtra("health_sources_test_id", overviewNames.fixture)
                putExtra("health_profile_test_db", overviewNames.profile)
                putExtra("health_privacy_test_db", overviewNames.privacy)
            }
        })
        entry(R.drawable.ic_health_proactive, R.string.health_care_title, "health-care-entry") { launch(HealthCareActivity::class.java) }
        entry(R.drawable.ic_agent_plan_progress, R.string.health_agenda_title, "health-agenda-entry") { launch(HealthCareActionsActivity::class.java) }
        entry(R.drawable.ic_health_data_chart, R.string.health_record_center, "health-functions-record-center") { open("record_center") }
        entry(R.drawable.ic_rich_file, R.string.health_original_library, "health-originals-entry") { launch(HealthOriginalLibraryActivity::class.java) }
        entry(R.drawable.ic_hub_compose, R.string.health_manual, "health-manual-entry") { open("manual") }
        entry(R.drawable.ic_agent_history, R.string.health_records, "health-records-entry") { open("records") }
        entry(R.drawable.ic_agent_knowledge, R.string.health_catalog_title, "health-catalog-entry") { openCatalog() }
        entry(R.drawable.ic_health_data_chart, R.string.health_weekly_title, "health-weekly-entry") { launch(HealthWeeklyActivity::class.java) }
        entry(R.drawable.ic_tab_agent, R.string.health_assistant_title, "health-assistant-entry") { launch(HealthAssistantActivity::class.java) }
        entry(R.drawable.ic_settings_devices, R.string.health_sources_title, "health-sources-entry") { launch(HealthSourcesActivity::class.java) }
        entry(R.drawable.ic_settings_upload, R.string.health_export_data_files, "health-data-files-entry") { launch(HealthDataFilesActivity::class.java) }
        entry(R.drawable.ic_health_profile, R.string.health_profile_title, "health-profile-entry") { launch(HealthProfileActivity::class.java) }
        entry(R.drawable.ic_security_shield, R.string.health_privacy_title, "health-privacy-entry") { launch(HealthPrivacyActivity::class.java) }
        entry(R.drawable.ic_health_body, R.string.health_body_title, "health-body-entry") { launch(HealthBodyAtlasActivity::class.java) }
    }
    private fun recordRow(record: HealthObservation) = ui.card().apply {
        addView(ui.text(getString(record.draft.metric.titleResource()), 14f, muted = true))
        ui.add(this, ui.text(value(record), if (value(record).length > 24) 18f else 25f, bold = true), 6)
        ui.add(this, ui.text("${date(record.draft.measuredAt)} \u00b7 ${source(record)}", 12f, muted = true), 8)
        setOnClickListener { open("detail", record.draft.metric, record.id) }; isFocusable = true
    }
    internal fun value(record: HealthObservation): String {
        return healthDisplayValue(record.draft)
    }
    private fun renderRecords() {
        val content = scrolling()
        content.tag = "health-record-timeline"
        nextPage = null
        val after = pageAfter
        val selfOnly = route == "overview_history"
        val metric = selected.takeUnless { route == "records" }
        val now = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        query({ if (selfOnly && metric != null) it.careHistory(now, metric, after) else it.page(after, metric) }) { page ->
            nextPage = page.next
            var shownDay: java.time.LocalDate? = null
            val dayFormat = DateFormat.getDateInstance(DateFormat.MEDIUM)
            val timeFormat = DateFormat.getTimeInstance(DateFormat.SHORT)
            page.records.forEach { record ->
                val time = record.draft.measuredAt
                val day = HealthOverviewPolicy.localDay(time, zone)
                if (day != shownDay) {
                    ui.add(content, ui.text(dayFormat.format(Date(time)), 15f, bold = true).apply {
                        tag = "health-record-day"
                        androidx.core.view.ViewCompat.setAccessibilityHeading(this, true)
                    }, if (shownDay == null) 0 else 16)
                    shownDay = day
                }
                content.addView(ui.line().apply {
                    gravity = Gravity.CENTER_VERTICAL
                    minimumHeight = ui.dp(52)
                    setPadding(0, ui.dp(5), 0, ui.dp(5))
                    tag = "health-record-timeline-item"
                    isFocusable = true
                    setOnClickListener { open("detail", record.draft.metric, record.id) }
                    addView(ui.column().apply {
                        addView(ui.text(getString(record.draft.metric.titleResource()), 14f, bold = true))
                        addView(ui.text(getString(R.string.health_overview_source, timeFormat.format(Date(time)), source(record)),
                            12f, muted = true))
                    }, LinearLayout.LayoutParams(0, -2, 1f))
                    addView(ui.text(value(record), 14f, bold = true).apply {
                        gravity = Gravity.END
                        setPadding(ui.dp(6), 0, 0, 0)
                    }, LinearLayout.LayoutParams(0, -2, 1f))
                })
                content.addView(healthOverviewDivider(this))
            }
            if (content.childCount == 0) content.addView(ui.text(getString(R.string.health_no_records), 15f, muted = true))
            if (pageHistory.isNotEmpty()) ui.add(content, ui.command(R.string.health_previous_page) {
                pageAfter = pageHistory.removeAt(pageHistory.lastIndex); render()
            }, 16)
            if (nextPage != null) ui.add(content, ui.command(R.string.health_next_page) {
                pageHistory += pageAfter; pageAfter = nextPage; render()
            }, 16)
            if (metric != null) ui.add(content, ui.command(R.string.health_add_measurement) { open("manual", metric) }, 16)
        }
    }
    private fun renderDetail() {
        val content = scrolling()
        val id = recordId
        val deletionRevision = undoDeletionRevision
        query({ it.record(id) to it.canUndoDelete(id, deletionRevision) }) { (record, undoable) ->
            if (record == null) {
                if (undoable) {
                    content.addView(ui.text(getString(R.string.health_record_deleted)))
                    ui.add(content, ui.command(R.string.health_undo_record_delete) {
                        changeRecordDeletion(0) { it.undoDelete(id, deletionRevision) }
                    }.apply { tag = "health-undo-record-delete" }, 16)
                } else {
                    undoDeletionRevision = 0
                    content.addView(ui.text(getString(R.string.health_record_missing)).apply { tag = "health-record-missing" })
                }
                return@query
            }
            undoDeletionRevision = 0
            title.text = getString(record.draft.metric.titleResource())
            content.addView(recordRow(record))
            ui.add(content, ui.card().apply {
                addView(ui.text(getString(R.string.health_measured_at), 13f, muted = true)); addView(ui.text(date(record.draft.measuredAt)))
                ui.add(this, ui.text(source(record), 14f, muted = true), 14)
                if (record.platformOrigin.isNotBlank()) ui.add(this, ui.text(
                    if (record.source == "bluetooth") getString(R.string.health_ble_device_name, record.platformOrigin)
                    else healthConnectTrendLabel(record.platformOrigin, record.draft.metric), 13f, muted = true), 4)
                record.deviceReceivedAt?.let {
                    ui.add(this, ui.text(getString(R.string.health_ble_received_time, date(it)), 13f, muted = true), 4)
                    ui.add(this, ui.text(if (record.deviceClock.isBlank()) getString(R.string.health_ble_no_clock)
                        else getString(R.string.health_ble_clock, record.deviceClock.replace('T', ' ')), 13f, muted = true), 4)
                }
                record.draft.evidence?.let { evidence ->
                    val location = if (evidence.tableSheet.isNotBlank()) getString(R.string.health_xlsx_source_row, evidence.tableSheet, evidence.tableRow)
                        else getString(if (evidence.kind == "table") R.string.health_table_source_row else R.string.health_source_page,
                            if (evidence.kind == "table") evidence.tableRow else evidence.page.toLong())
                    ui.add(this, ui.row(getString(R.string.health_view_original), location) {
                        startActivity(android.content.Intent(this@HealthCenterActivity, HealthCaptureActivity::class.java).putExtra("original", evidence.originalId))
                    }, 12)
                    ui.add(this, ui.text(evidence.rawText, 13f, muted = true), 8)
                }
                addView(ui.text(getString(healthContextResource(record.draft.condition))))
                if (record.draft.metric == HealthMetric.BLOOD_PRESSURE) {
                    addView(ui.text(getString(healthContextResource(record.draft.side))))
                    record.draft.values["pulse"]?.let { addView(ui.text("${getString(R.string.health_pulse)}: $it bpm")) }
                }
                if (record.draft.note.isNotBlank()) ui.add(this, ui.text(record.draft.note), 12)
                if (record.draft.reference.isNotBlank()) {
                    ui.add(this, ui.text(getString(R.string.health_report_reference), 13f, muted = true), 12)
                    addView(ui.text(record.draft.reference))
                }
                ui.add(this, ui.text(getString(R.string.health_revision, record.revision), 12f, muted = true), 12)
            }, 16)
            ui.add(content, ui.row(getString(R.string.common_edit)) { open("manual", record.draft.metric, record.id) }
                .apply { tag = "health-edit-record" }, 14)
            ui.add(content, ui.row(getString(R.string.health_revision_history)) { open("history", record.draft.metric, record.id) })
            ui.add(content, ui.row(getString(R.string.common_delete)) {
                if (saving) return@row
                showHealthDialog(AlertDialog.Builder(this).setTitle(R.string.health_delete_title).setMessage(R.string.health_delete_description)
                    .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.common_delete) { _, _ ->
                        selected = record.draft.metric
                        changeRecordDeletion(record.revision + 1) { it.delete(record.id, record.revision) }
                    }.create())
            }.apply { tag = "health-delete-record" })
        }
    }
    private fun changeRecordDeletion(deletionRevision: Int, work: (HealthRecordStore) -> Boolean) {
        if (!active || saving) return
        saving = true
        worker.execute {
            val result = runCatching { work(records) }
            main.post {
                saving = false
                if (isDestroyed) return@post
                if (result.getOrNull() == true) undoDeletionRevision = deletionRevision
                if (!active) return@post
                if (result.getOrNull() != true) {
                    val message = if (result.isFailure) R.string.health_storage_error
                    else if (deletionRevision == 0) R.string.health_undo_record_unavailable else R.string.health_conflict
                    Toast.makeText(this, message, Toast.LENGTH_LONG).show()
                }
                if (route == "detail") render()
            }
        }
    }
    private fun renderHistory(beforeRevision: Int = Int.MAX_VALUE) {
        body.removeAllViews()
        val content = scrolling()
        val id = recordId
        query({ it.history(id, beforeRevision) }) { history ->
            history.forEach { record ->
            ui.add(content, ui.card().apply {
                addView(ui.text(getString(R.string.health_revision, record.revision), bold = true))
                addView(ui.text(value(record))); addView(ui.text(date(record.receivedAt), 13f, muted = true))
            }, 12)
            }
            if (beforeRevision != Int.MAX_VALUE) ui.add(content, ui.command(R.string.health_latest_revisions) { renderHistory() }, 16)
            if (history.size == 50) ui.add(content, ui.command(R.string.health_older_revisions) { renderHistory(history.last().revision) }, 16)
        }
    }
    private fun renderManual() {
        val id = recordId
        val metric = selected
        val key = if (route == "review") reviewKey else if (id.isBlank()) "new:${metric.name}" else "edit:$id"
        val reviewing = route == "review"
        query({ store ->
            val draft = if (reviewing) store.draft(key) else if (id.isBlank()) store.draft(key) ?: HealthDraft(metric)
                else store.record(id)?.let { store.draft(key) ?: it.editable() }
            val sourceContext = if (reviewing) draft?.evidence?.takeIf { it.kind == "ocr" }?.let { evidence ->
                runCatching {
                    HealthOriginalStore(applicationContext, overviewNames.originals, overviewNames.originalRoot(applicationContext)).use { originals ->
                        val original = originals.originalForJob(evidence.jobId)
                        if (original == null || original.id != evidence.originalId || original.sha256 != evidence.sha256) null
                        else originals.page(evidence.jobId, evidence.page)?.takeIf { it.recognition == evidence.recognition }
                            ?.let { HealthOcrSourceContext.inspect(it, java.time.ZoneId.systemDefault()) }
                    }
                }.getOrNull() ?: HealthOcrSourceContext()
            } else null
            draft to sourceContext
        }) { (draft, sourceContext) ->
            if (draft == null) { body.addView(ui.text(getString(R.string.health_record_missing))); return@query }
            selected = draft.metric
            editor = HealthManualEditor(this, draft, sourceContext).also { it.render() }
        }
    }
    internal fun saveMeasurement(draft: HealthDraft) {
        if (saving) return
        HealthObservationPolicy.validate(draft)?.let { error -> editor?.showError(error); return }
        saving = true
        editor?.setSaving(true)
        main.removeCallbacks(savePendingDraft)
        if (stagingOcrReview) {
            worker.execute {
                val result = runCatching { records.saveDraft(draft) }
                main.post {
                    saving = false
                    if (isDestroyed) return@post
                    if (result.isSuccess) { editor = null; setResult(RESULT_OK); finish() }
                    else if (active) {
                        editor?.setSaving(false)
                        Toast.makeText(this, R.string.health_draft_error, Toast.LENGTH_LONG).show()
                    }
                }
            }
            return
        }
        worker.execute {
            val result = runCatching { records.save(draft) }
            if (result.getOrNull() is HealthSaveResult.Saved) draft.evidence?.let { evidence ->
                runCatching {
                    HealthOriginalStore(applicationContext, overviewNames.originals, overviewNames.originalRoot(applicationContext)).use {
                        HealthOriginalRetention.releaseAfterReview(it, records, evidence.jobId)
                    }
                }
            }
            main.post {
                saving = false
                if (isDestroyed) return@post
                result.fold({ saved ->
                    when (saved) {
                    is HealthSaveResult.Saved -> {
                        editor = null
                        if (active) {
                            Toast.makeText(this, R.string.health_saved, Toast.LENGTH_SHORT).show()
                            back()
                        } else {
                            val previous = if (backStack.isEmpty()) Triple("overview", selected, "") else backStack.removeLast()
                            route = previous.first; selected = previous.second; recordId = previous.third
                        }
                    }
                    is HealthSaveResult.Duplicate -> if (active) {
                        editor?.setSaving(false)
                        AlertDialog.Builder(this).setMessage(R.string.health_duplicate).setNegativeButton(R.string.common_cancel, null)
                            .setPositiveButton(R.string.health_view_existing) { _, _ -> open("detail", draft.metric, saved.id) }.show()
                    }
                    HealthSaveResult.Conflict -> if (active) { editor?.setSaving(false); Toast.makeText(this, R.string.health_conflict, Toast.LENGTH_LONG).show() }
                    }
                    Unit
                }, {
                    if (active) { editor?.setSaving(false); Toast.makeText(this, R.string.health_storage_error, Toast.LENGTH_LONG).show() }
                    Unit
                })
            }
        }
    }
    private fun openCatalog() { startActivity(android.content.Intent(this, HealthCatalogActivity::class.java).putHealthNavigationFixture(overviewNames)) }
    private fun source(record: HealthObservation) = getString(healthRecordSourceResource(record.source))

    private companion object {
        val RECORD_ROUTES = setOf("records", "metric_records", "overview_history")
        val LIVE_SUMMARY_ROUTES = setOf("overview", "overview_metric", "record_center")
    }
}
