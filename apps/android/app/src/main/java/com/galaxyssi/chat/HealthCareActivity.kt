package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Switch
import android.widget.Toast
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.Executors

class HealthCareActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val names by lazy { intent.healthNavigationDatabases() }
    private val store by lazy { HealthCareStore(applicationContext, names.care) }
    private val planReview by lazy { HealthCarePlanReview(this, names) }
    private val actionReview by lazy { HealthCareActionReview(this, names) }
    private val targetReview by lazy { HealthCareTargetReview(this, names) }
    private val historyReview by lazy { HealthCareHistoryReview(this, names) }
    private val researchReview by lazy { HealthCareResearchReview(this, names) }
    private lateinit var body: LinearLayout
    private var active = false
    private var generation = 0
    private var loading = false
    private var dirty = false
    private var mutating = false
    private var dialog: AlertDialog? = null
    private var selected: String? = null
    private var cursor: HealthCareCursor? = null
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) { planReview.clear(); actionReview.clear(); targetReview.clear(); historyReview.clear(); generation++; load() }
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            if (uri != HealthCareStore.changes(this@HealthCareActivity, names.care)) researchReview.clear()
            onChange(selfChange)
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        selected = savedInstanceState?.getString("care_id") ?: intent.getStringExtra("health_care_id")
        selected = selected?.takeIf(HealthProfilePolicy::uuid)
        body = healthProfileBody(R.string.health_care_title) { back() }
    }
    override fun onSaveInstanceState(outState: Bundle) { outState.putString("care_id", selected); super.onSaveInstanceState(outState) }
    override fun onStart() {
        super.onStart(); active = true
        listOf(HealthCareStore.changes(this, names.care), HealthRecordStore.changes(this, names.records),
            HealthPrivacyStore.changes(this, names.privacy)).forEach { contentResolver.registerContentObserver(it, false, observer) }
        load()
    }
    override fun onStop() {
        active = false; generation++; dialog?.dismiss(); dialog = null; planReview.clear(); actionReview.clear(); targetReview.clear(); historyReview.clear(); researchReview.clear(); body.removeAllViews()
        contentResolver.unregisterContentObserver(observer); super.onStop()
    }
    override fun onDestroy() { planReview.destroy(); actionReview.destroy(); targetReview.destroy(); historyReview.destroy(); researchReview.destroy(); worker.execute { store.close() }; worker.shutdown(); super.onDestroy() }
    @Deprecated("Uses the existing native health navigation contract")
    override fun onBackPressed() = back()
    private fun back() { if (selected == null) finish() else { selected = null; cursor = null; generation++; load() } }
    private data class Snapshot(val settings: HealthCareSettings, val permitted: Boolean, val page: HealthCarePage,
        val item: HealthCareConcern?, val history: List<HealthCareConcern>, val proposals: List<HealthCarePlan>, val profile: Boolean)
    private fun load() {
        if (!active) return
        if (loading || mutating) { dirty = true; return }
        loading = true; dirty = false
        val token = generation; val id = selected; val after = cursor
        worker.execute {
            val result = runCatching {
                HealthCareEngine.evaluate(applicationContext, names)
                val privacy = HealthPrivacyStore(applicationContext, names.privacy).use { it.policy() }
                val allowed = privacy.metrics
                Snapshot(store.settings(), allowed, if (allowed) store.page(after) else HealthCarePage(emptyList(), null),
                    if (allowed && id != null) store.concern(id) else null,
                    if (allowed && id != null) store.history(id) else emptyList(),
                    if (allowed && privacy.profile && id != null) store.pendingPlans(id) else emptyList(), privacy.profile)
            }
            main.post {
                loading = false
                if (active && token == generation) result.fold(::render, ::error)
                if (active && (dirty || token != generation)) load()
            }
        }
    }
    private fun render(snapshot: Snapshot) {
        val content = healthProfileContent(body)
        if (!snapshot.permitted) {
            content.addView(ui.profileRow(getString(R.string.health_overview_permission)) {
                startActivity(Intent(this, HealthPrivacyActivity::class.java).putHealthNavigationFixture(names))
            })
            return
        }
        if (selected != null) {
            snapshot.item?.let { detail(content, it, snapshot.history, snapshot.proposals, snapshot.profile) } ?: content.addView(ui.text(getString(R.string.health_care_removed)))
            return
        }
        content.addView(Switch(this).apply {
            text = getString(R.string.health_care_enable); isChecked = snapshot.settings.enabled; minimumHeight = ui.dp(48)
            tag = "health-care-enabled"
            setOnCheckedChangeListener { _, enabled ->
                if (enabled) {
                    dialog = AlertDialog.Builder(this@HealthCareActivity).setTitle(R.string.health_care_title)
                        .setMessage(R.string.health_care_consent).setNegativeButton(R.string.common_cancel) { _, _ -> load() }
                        .setOnCancelListener { load() }.setPositiveButton(android.R.string.ok) { _, _ ->
                            mutate { store.configure(true, snapshot.settings.version); HealthCareEngine.evaluate(applicationContext, names) }
                        }.show()
                } else mutate { store.configure(false, snapshot.settings.version) }
            }
        })
        heading(content, R.string.health_care_attention)
        if (!snapshot.settings.enabled) ui.add(content, ui.text(getString(R.string.health_care_disabled), 14f, muted = true), 8)
        if (snapshot.page.items.isEmpty()) ui.add(content, ui.text(getString(R.string.health_care_empty), 14f, muted = true), 8)
        snapshot.page.items.forEach { item ->
            ui.add(content, ui.profileRow(getString(if (HealthCarePriority.rank(item.assessment) > 0) R.string.health_care_bp_title else item.metric.titleResource()),
                "${item.assessment.value} ${item.assessment.unit} · ${getString(item.stage.titleResource())}") {
                selected = item.id; generation++; load()
            }.apply { tag = "health-care-item-${item.metric.name}" }, 8)
        }
        snapshot.page.next?.let { after -> ui.add(content, ui.command(R.string.health_care_more) { cursor = after; generation++; load() }, 8) }
        heading(content, R.string.health_care_plans)
        val actions = snapshot.page.items.flatMap { issue -> issue.actions.map { issue to it } }
        if (actions.isEmpty()) ui.add(content, ui.text(getString(R.string.health_care_no_plan), 14f, muted = true), 8)
        actions.forEach { (issue, action) -> ui.add(content, ui.profileRow(action.description, getString(action.state.titleResource())) {
            selected = issue.id; generation++; load()
        }, 6) }
        heading(content, R.string.health_care_evidence)
        ui.add(content, ui.profileRow(getString(R.string.health_catalog_title)) { open(HealthCatalogActivity::class.java) }, 6)
        ui.add(content, ui.profileRow(getString(R.string.health_export_data_files)) { open(HealthDataFilesActivity::class.java) }, 6)
    }
    private fun detail(content: LinearLayout, value: HealthCareConcern, history: List<HealthCareConcern>, proposals: List<HealthCarePlan>, profile: Boolean) {
        content.addView(ui.text(getString(value.metric.titleResource()), 23f, bold = true))
        ui.add(content, ui.text("${value.assessment.value} ${value.assessment.unit}", 22f, bold = true), 8)
        ui.add(content, ui.text(getString(value.stage.titleResource()), 14f, muted = true), 6)
        HealthCarePriorityPresentation.add(this, content, value)
        if (profile && value.assessment.series != null) ui.add(content, ui.profileRow(getString(R.string.health_series_title),
            getString(R.string.health_series_summary)) { historyReview.show(value.id) }.apply { tag = "health-care-series" }, 8)
        ui.add(content, ui.command(R.string.health_care_discussion_title_short) { discuss(value) }
            .apply { tag = "health-care-discuss" }, 12)
        if (profile) ui.add(content, ui.profileRow(getString(R.string.health_research_title)) { researchReview.show(value.id) }
            .apply { tag = "health-care-research" }, 8)
        proposals.forEach { plan -> ui.add(content, ui.profileRow(HealthCareTargetPresentation.planTitle(this, plan)) {
            planReview.show(plan.id)
        }.apply { tag = "health-care-plan-${plan.id}" }, 8) }
        if (profile) value.maintenance?.let { review ->
            ui.add(content, ui.profileRow(getString(R.string.health_maintenance_review_title),
                getString(if (value.stage == HealthCareStage.MAINTENANCE) R.string.health_maintenance_active else R.string.health_maintenance_reassess)) {
                planReview.show(review.planId)
            }.apply { tag = "health-care-maintenance" }, 8)
            if (value.stage == HealthCareStage.MAINTENANCE) ui.add(content, ui.command(R.string.health_maintenance_reopen) {
                mutate { store.update(value.id, value.revision, "maintenance_user_reassessment") { it.copy(stage = HealthCareStage.REASSESS) } }
            }.apply { tag = "health-care-maintenance-reopen" }, 8)
        }
        heading(content, R.string.health_care_why)
        if (value.assessment.signals.isEmpty()) ui.add(content, ui.text(getString(R.string.health_care_changed_result), 15f), 8)
        value.assessment.signals.forEach { ui.add(content, ui.text(getString(it.titleResource()), 15f), 8) }
        if (value.metric == HealthMetric.GLUCOSE && value.assessment.record != null) {
            ui.add(content, ui.command(R.string.health_care_context) { context(value) }.apply { tag = "health-care-context" }, 12)
        }
        HealthCareComparisonPresentation.details(this, value)?.let { comparison ->
            heading(content, R.string.health_care_comparison_title)
            ui.add(content, ui.text(comparison, 15f).apply { tag = "health-care-comparison" }, 8)
        }
        heading(content, R.string.health_care_evidence)
        basis(content, R.string.health_care_reference, value.assessment.reportReference.ifBlank { getString(R.string.health_care_reference_missing) })
        basis(content, R.string.health_care_guideline, value.assessment.guideline?.let { "${it.title}\n${it.applicability}\n${it.statement}" }
            ?: getString(R.string.health_care_no_guideline))
        basis(content, R.string.health_care_baseline, value.assessment.baseline?.let(HealthCarePolicy::baselineText) ?: getString(R.string.health_care_no_baseline))
        if (profile) basis(content, R.string.health_care_target, HealthCareTargetPresentation.details(this, value))
        if (profile && value.target != null) ui.add(content, ui.profileRow(getString(R.string.health_target_review)) { targetReview.show(value.id) }
            .apply { tag = "health-care-target" }, 8)
        value.assessment.record?.let { ref -> ui.add(content, ui.profileRow(getString(R.string.health_care_record)) {
            if (names.fixture == null) startActivity(Intent(this, HealthRecordRevisionActivity::class.java)
                .putExtra("health_record", ref.id).putExtra("health_revision", ref.revision))
        }, 8) }
        value.assessment.guideline?.let { guideline -> ui.add(content, ui.profileRow(getString(R.string.health_care_sources), guideline.version) {
            runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(guideline.url))) }
                .onFailure { Toast.makeText(this, R.string.health_storage_error, Toast.LENGTH_LONG).show() }
        }, 8) }
        heading(content, R.string.health_care_plans)
        if (value.actions.isEmpty()) ui.add(content, ui.text(getString(R.string.health_care_no_plan), 14f, muted = true), 8)
        value.actions.forEach { action ->
            ui.add(content, ui.text(action.description, 16f, bold = true), 12)
            ui.add(content, ui.text(action.rationale, 14f), 4)
            ui.add(content, ui.text(action.source, 13f, muted = true), 4)
            ui.add(content, ui.text(getString(action.state.titleResource()), 13f, muted = true), 4)
            action.dueFrom?.let { from -> ui.add(content, ui.text("${date(from)} - ${date(action.dueUntil!!)}", 14f), 4) }
            if (action.state in setOf(HealthCareActionState.CONFIRMED, HealthCareActionState.DONE)) {
                ui.add(content, ui.profileRow(getString(R.string.health_care_followup_title)) { actionReview.show(value.id, action.id) }
                    .apply { tag = "health-care-followup-${action.id}" }, 8)
            }
            if (action.state == HealthCareActionState.PROPOSED) {
                ui.add(content, ui.command(R.string.health_care_confirm_action) { mutate {
                    store.update(value.id, value.revision, "action_confirmed") { current -> current.copy(actions = current.actions.map {
                        if (it.id == action.id) it.copy(state = HealthCareActionState.CONFIRMED, confirmedAt = System.currentTimeMillis(),
                            basis = HealthCareFollowUpPolicy.basis(current)) else it
                    }, stage = HealthCareStage.WAITING_RESULTS) }
                } }, 8)
                ui.add(content, ui.profileRow(getString(R.string.health_care_decline_action)) { mutate {
                    store.update(value.id, value.revision, "action_declined") { current -> current.copy(actions = current.actions.map {
                        if (it.id == action.id) it.copy(state = HealthCareActionState.DECLINED) else it
                    }) }
                } }, 4)
            }
        }
        ui.add(content, ui.profileRow(getString(if (value.stage == HealthCareStage.PAUSED) R.string.health_care_resume else R.string.health_care_pause)) {
            mutate { store.update(value.id, value.revision, "user_pause_changed") { current ->
                HealthCarePolicy.review(current, if (current.stage == HealthCareStage.PAUSED) HealthCareStage.REASSESS else HealthCareStage.PAUSED,
                    "User changed tracking state", "user", System.currentTimeMillis())
            } }
        }, 16)
        heading(content, R.string.health_care_history)
        history.forEach { item -> ui.add(content, ui.text(getString(R.string.health_care_version, item.revision, date(item.updatedAt)) +
            "\n" + getString(item.stage.titleResource()), 13f, muted = true), 8) }
        ui.add(content, ui.profileRow(getString(R.string.health_care_remove)) {
            dialog = AlertDialog.Builder(this).setTitle(R.string.health_care_remove).setMessage(R.string.health_care_remove_question)
                .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.common_delete) { _, _ ->
                    mutate { store.delete(value.id, value.revision) }; selected = null
                }.show()
        }, 16)
    }
    private fun context(value: HealthCareConcern) {
        val ref = value.assessment.record ?: return
        var context = value.context?.takeIf { it.record == ref } ?: HealthCareContext(ref, confirmedAt = System.currentTimeMillis())
        val content = ui.column().apply { setPadding(ui.dp(20), ui.dp(8), ui.dp(20), ui.dp(8)) }
        fun choice(title: Int, values: List<Int>, current: Int, select: (Int) -> Unit) {
            ui.add(content, ui.text(getString(title), 15f, bold = true), 12)
            content.addView(RadioGroup(this).apply {
                values.forEachIndexed { index, label -> addView(RadioButton(this@HealthCareActivity).apply {
                    id = View.generateViewId(); text = getString(label); isChecked = current == index
                    setOnClickListener { select(index) }
                }) }
            })
        }
        val answers = listOf(R.string.health_care_unknown, R.string.health_care_yes, R.string.health_care_no)
        choice(R.string.health_care_adult, answers, context.adult.ordinal) { context = context.copy(adult = HealthCareTruth.entries[it]) }
        choice(R.string.health_care_pregnant, answers, context.pregnant.ordinal) { context = context.copy(pregnant = HealthCareTruth.entries[it]) }
        choice(R.string.health_care_diabetes, answers, context.diagnosedDiabetes.ordinal) { context = context.copy(diagnosedDiabetes = HealthCareTruth.entries[it]) }
        choice(R.string.health_care_sample, listOf(R.string.health_care_unknown, R.string.health_care_lab_plasma,
            R.string.health_care_capillary, R.string.health_care_interstitial), context.specimen.ordinal) {
            context = context.copy(specimen = HealthCareSpecimen.entries[it])
        }
        ui.add(content, ui.text(getString(R.string.health_care_fasting), 15f, bold = true), 12)
        val fasting = EditText(this).apply {
            isSaveEnabled = false; importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            imeOptions = android.view.inputmethod.EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
            filters = arrayOf(android.text.InputFilter.LengthFilter(2))
            inputType = InputType.TYPE_CLASS_NUMBER; setText(context.fastingHours?.toString().orEmpty())
            hint = getString(R.string.health_care_unknown); tag = "health-care-fasting-hours"
        }
        content.addView(fasting)
        choice(R.string.health_care_illness, answers, context.illnessOrMedication.ordinal) { context = context.copy(illnessOrMedication = HealthCareTruth.entries[it]) }
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_care_context).setView(ScrollView(this).apply { addView(content) })
            .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_care_save_context, null).create().also { d ->
                d.setOnShowListener { d.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                    val text = fasting.text.toString().trim(); val hours = text.toIntOrNull()
                    if (text.isNotEmpty() && (hours == null || hours !in 0..72)) { fasting.error = getString(R.string.health_invalid_context); return@setOnClickListener }
                    val confirmed = context.copy(fastingHours = hours, confirmedAt = System.currentTimeMillis())
                    d.dismiss(); mutate { store.confirmContext(value.id, value.revision, confirmed); HealthCareEngine.evaluate(applicationContext, names) }
                } }
                d.show()
            }
    }
    private fun heading(content: LinearLayout, title: Int) = ui.add(content, ui.text(getString(title), 18f, bold = true), 22)
    private fun discuss(value: HealthCareConcern) {
        // Fixture pages never create real user conversations or contact an actual provider.
        if (names.fixture != null || mutating) return
        mutating = true
        worker.execute {
            val result = runCatching { HealthCareDiscussion.open(applicationContext, value.id) }
            main.post {
                mutating = false
                if (!active) return@post
                result.fold({ id -> startActivity(Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", id)) }, ::error)
            }
        }
    }
    private fun basis(content: LinearLayout, title: Int, value: String) {
        ui.add(content, ui.text(getString(title), 14f, bold = true), 14)
        ui.add(content, ui.text(value, 14f, muted = true), 4)
    }
    private fun date(value: Long) = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(value))
    private fun open(type: Class<*>) { if (names.fixture == null) startActivity(Intent(this, type)) }
    private fun mutate(action: () -> Unit) {
        if (mutating) return
        mutating = true
        worker.execute {
            val result = runCatching(action)
            main.post { mutating = false; if (active) { result.exceptionOrNull()?.let(::error); generation++; load() } }
        }
    }
    private fun error(failure: Throwable) {
        val message = if (failure is HealthCareConflict) R.string.health_care_changed else R.string.health_storage_error
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        val content = healthProfileContent(body)
        content.addView(ui.text(getString(message)))
        ui.add(content, ui.command(R.string.common_retry) { load() }, 12)
    }
}
