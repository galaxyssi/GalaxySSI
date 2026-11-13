package com.galaxyssi.chat

import android.content.Intent
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Toast
import java.util.concurrent.Executors

/** Displays local health context only inside its independently bound Agent conversation. */
internal class HealthCareAgentSurface(private val activity: MainActivity, private val names: HealthOverviewDatabases = HealthOverviewDatabases()) {
    private val host = activity.findViewById<LinearLayout>(R.id.agentHealthCareSurface)
    private val ui = HealthCenterViews(activity)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val planReview = HealthCarePlanReview(activity, names)
    private val actionReview = HealthCareActionReview(activity, names)
    private val targetReview = HealthCareTargetReview(activity, names)
    private val historyReview = HealthCareHistoryReview(activity, names)
    private val researchReview = HealthCareResearchReview(activity, names)
    private val answerReview = HealthCareAnswerReview(activity, names)
    private var active = false
    private var agentPage = activity.findViewById<View>(R.id.collaborationOutputList).visibility != View.VISIBLE
    private var loading = false
    private var dirty = false
    private var generation = 0
    private var visibleConversation = ""
    private var expanded = false
    private var visibleConcern = ""
    private var openingDiscussion = false
    private var navigationGeneration = 0
    private val deadlineRefresh = Runnable { generation++; reload() }
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) { planReview.clear(); actionReview.clear(); targetReview.clear(); historyReview.clear(); answerReview.clear(); generation++; reload() }
        override fun onChange(selfChange: Boolean, uri: android.net.Uri?) {
            if (uri != HealthCareStore.changes(activity, names.care)) { researchReview.clear(); navigationGeneration++ }
            onChange(selfChange)
        }
    }
    fun resume() {
        if (active) return
        active = true
        listOf(HealthCareStore.changes(activity, names.care), HealthPrivacyStore.changes(activity, names.privacy),
            HealthRecordStore.changes(activity, names.records)).forEach {
            activity.contentResolver.registerContentObserver(it, false, observer)
        }
        reload()
    }
    fun pause() {
        if (active) activity.contentResolver.unregisterContentObserver(observer)
        active = false; clear()
    }
    fun clear() { modelReviewVisibility(null); generation++; navigationGeneration++; main.removeCallbacks(deadlineRefresh); expanded = false; visibleConcern = ""; planReview.clear(); actionReview.clear(); targetReview.clear(); historyReview.clear(); researchReview.clear(); answerReview.clear(); host.removeAllViews(); host.visibility = View.GONE }
    private fun modelReviewVisibility(conversation: String?) {
        val changed = if (conversation == null) HealthCareModelReviewVisibility.hide(this)
            else HealthCareModelReviewVisibility.show(this, names.care, conversation)
        if (changed && names.fixture == null) HealthReminderWork.sourceRemindersChanged(activity.applicationContext)
    }
    fun showForAgent(value: Boolean) {
        agentPage = value
        if (value) reload() else clear()
    }
    fun destroy() { pause(); planReview.destroy(); actionReview.destroy(); targetReview.destroy(); historyReview.destroy(); researchReview.destroy(); answerReview.destroy(); worker.shutdown() }
    private data class Snapshot(val concerns: List<HealthCareConcern>, val plans: List<HealthCarePlan> = emptyList(),
        val action: HealthCareAction? = null, val reminder: HealthCareReminder? = null, val profile: Boolean = false,
        val authorization: HealthCareResearchAuthorization? = null, val research: HealthCareResearchJob? = null, val answers: Boolean = false)
    private fun reload() {
        if (!active || !agentPage) return
        val conversation = activity.agentTranscriptStore.activeConversation()
        if (conversation.id != visibleConversation) {
            clear()
            visibleConversation = conversation.id
        }
        val concernId = HealthCareAgentScope.concernId(conversation)
        if (concernId == null) { clear(); dirty = false; return }
        if (loading) { dirty = true; return }
        loading = true; dirty = false; val token = generation
        worker.execute {
            val result = runCatching {
                val context = activity.applicationContext
                if (!context.getDatabasePath(names.care).exists()) Snapshot(emptyList()) else {
                    HealthCareEngine.evaluate(context, names)
                    HealthPrivacyStore(context, names.privacy).use { privacy ->
                        if (!privacy.policy().metrics) Snapshot(emptyList()) else HealthCareStore(context, names.care).use { store ->
                            val concerns = if (store.settings().enabled && store.discussion(conversation.id) == concernId)
                                listOfNotNull(store.concern(concernId)) else emptyList()
                            val issue = concerns.firstOrNull()
                            val profile = privacy.policy().profile
                            val reminders = if (profile && issue != null) store.reminders(issue.id) else emptyList()
                            val action = if (profile) issue?.actions?.filter { it.state == HealthCareActionState.CONFIRMED }
                                ?.minByOrNull { item -> reminders.firstOrNull { it.actionId == item.id && it.state != HealthCareReminderState.CANCELLED }?.dueAt ?: Long.MAX_VALUE }
                                else null
                            val plans = if (profile && issue != null) store.pendingPlans(issue.id).filter {
                                HealthCarePlanPolicy.current(it, issue, store.settings(), privacy.policy(), issue.inputVersion)
                            } else emptyList()
                            Snapshot(concerns, plans,
                                action, reminders.firstOrNull { it.actionId == action?.id }, profile,
                                if (profile && issue != null) store.researchAuthorization(issue.id) else null,
                                if (profile && issue != null) store.latestResearchJob(issue.id) else null,
                                profile && issue != null && store.answers(issue, limit = 1).items.isNotEmpty())
                        }
                    }
                }
            }
            main.post {
                loading = false
                if (active && agentPage && token == generation && activity.agentTranscriptStore.activeConversation().id == conversation.id) {
                    main.removeCallbacks(deadlineRefresh)
                    val previousScroll = host.findViewWithTag<ScrollView>("agent-health-care-scroll")?.scrollY ?: 0
                    host.removeAllViews()
                    val snapshot = result.getOrDefault(Snapshot(emptyList()))
                    val concerns = snapshot.concerns
                    modelReviewVisibility(conversation.id.takeIf { concerns.isNotEmpty() && result.isSuccess })
                    host.visibility = if (concerns.isEmpty() && result.isSuccess) View.GONE else View.VISIBLE
                    if (result.isFailure) host.addView(ui.profileRow(activity.getString(R.string.health_care_partial)) { reload() })
                    else concerns.firstOrNull()?.let { item ->
                        val sameConcern = visibleConcern == item.id
                        if (!sameConcern) { expanded = false; visibleConcern = item.id }
                        val panel = HealthCareAgentPanel(activity,
                            activity.getString(item.metric.titleResource()) + " · " + activity.getString(item.stage.titleResource()),
                            HealthCareComparisonPresentation.summary(activity, item.assessment)
                                ?: "${item.assessment.value} ${item.assessment.unit}",
                            if (HealthCarePriority.rank(item.assessment) > 0) activity.getString(R.string.health_care_bp_title) else null,
                            expanded) { expanded = it }
                        val content = panel.content
                        val scroll = panel.scroll
                        host.addView(panel)
                        HealthCarePriorityPresentation.add(activity, content, item, compact = true) {
                            activity.startActivity(Intent(activity, HealthCareActivity::class.java).putExtra("health_care_id", item.id)
                                .putHealthNavigationFixture(names))
                        }
                        val why = item.assessment.signals.joinToString(" ") { activity.getString(it.titleResource()) }
                            .ifBlank { activity.getString(R.string.health_care_changed_result) }
                        content.addView(ui.text(activity.getString(R.string.health_agent_why, why), 14f).apply {
                            tag = "agent-health-care-why"
                        })
                        content.addView(ui.text(activity.getString(R.string.health_agent_next, activity.getString(
                            if (snapshot.plans.isNotEmpty()) R.string.health_agent_next_plan else nextStep(item))), 14f).apply {
                            tag = "agent-health-care-next"
                        })
                        val details = ui.column()
                        content.addView(ui.line().apply {
                            if (snapshot.profile) addView(ui.text(activity.getString(R.string.health_care_discussion_title_short), 14f, bold = true).apply {
                                tag = "agent-health-care-discuss"; minimumHeight = ui.dp(48); gravity = android.view.Gravity.CENTER_VERTICAL
                                setCompoundDrawablesWithIntrinsicBounds(R.drawable.ic_tab_chat, 0, 0, 0)
                                compoundDrawableTintList = android.content.res.ColorStateList.valueOf(activity.getColor(R.color.text_primary))
                                compoundDrawablePadding = ui.dp(6)
                                isFocusable = true; setOnClickListener { discuss(item.id) }
                            }, LinearLayout.LayoutParams(0, -2, 1f))
                            else addView(ui.text(activity.getString(R.string.health_care_attention), 14f), LinearLayout.LayoutParams(0, -2, 1f))
                        })
                        if (snapshot.profile) content.addView(ui.text(activity.getString(R.string.health_agent_research_state, activity.getString(
                            if (snapshot.authorization?.active != true) R.string.health_research_off else
                                HealthCareResearchPolicy.displayState(item, snapshot.authorization, snapshot.research, System.currentTimeMillis())
                                    ?.titleResource() ?: R.string.health_research_queued)), 13f, muted = true).apply { tag = "agent-health-care-state" })
                        content.addView(details)
                        details.addView(ui.profileRow(activity.getString(R.string.health_agent_open_record)) {
                            activity.startActivity(Intent(activity, HealthCareActivity::class.java).putExtra("health_care_id", item.id)
                                .putHealthNavigationFixture(names))
                        }.apply { tag = "agent-health-care-record" })
                        if (snapshot.answers) details.addView(ui.profileRow(activity.getString(R.string.health_answer_title),
                            activity.getString(R.string.health_answer_pending)) { answerReview.show(item.id) }
                            .apply { tag = "agent-health-care-answers" })
                        if (snapshot.profile) details.addView(ui.profileRow(activity.getString(R.string.health_research_title)) {
                            researchReview.show(item.id)
                        }.apply { tag = "agent-health-care-research" })
                        if (snapshot.profile && item.assessment.series != null) details.addView(ui.profileRow(
                            activity.getString(R.string.health_series_title), activity.getString(R.string.health_series_summary)) {
                            historyReview.show(item.id)
                        }.apply { tag = "agent-health-care-series" })
                        snapshot.plans.firstOrNull()?.let { plan ->
                            details.addView(ui.profileRow(HealthCareTargetPresentation.planTitle(activity, plan)) {
                                planReview.show(plan.id)
                            }.apply { tag = "agent-health-care-plan" })
                        }
                        if (snapshot.profile) item.maintenance?.let { review ->
                            details.addView(ui.profileRow(activity.getString(R.string.health_maintenance_review_title),
                                activity.getString(if (item.stage == HealthCareStage.MAINTENANCE) R.string.health_maintenance_active else R.string.health_maintenance_reassess)) {
                                planReview.show(review.planId)
                            }.apply { tag = "agent-health-care-maintenance" })
                        }
                        if (snapshot.profile && item.target != null) details.addView(ui.profileRow(activity.getString(R.string.health_target_review),
                            HealthCareTargetPresentation.status(activity, item)) { targetReview.show(item.id) }
                            .apply { tag = "agent-health-care-target" })
                        snapshot.action?.let { action ->
                            details.addView(ui.profileRow(activity.getString(R.string.health_care_followup_title), action.description) {
                                actionReview.show(item.id, action.id)
                            }.apply { tag = "agent-health-care-followup" })
                        }
                        if (sameConcern && expanded && previousScroll > 0) scroll.post { scroll.scrollTo(0, previousScroll) }
                        if (snapshot.profile) {
                            val now = System.currentTimeMillis()
                            HealthCareResearchPolicy.nextDisplayChange(item, now)?.let {
                                main.postDelayed(deadlineRefresh, it - now)
                            }
                        }
                    }
                }
                if (active && agentPage && (dirty || token != generation)) reload()
            }
        }
    }

    private fun nextStep(issue: HealthCareConcern): Int = when (issue.stage) {
        HealthCareStage.VERIFY_CONTEXT -> R.string.health_agent_next_context
        HealthCareStage.REVIEW_EVIDENCE -> R.string.health_agent_next_evidence
        HealthCareStage.REVIEW_PLAN -> R.string.health_agent_next_plan
        HealthCareStage.WAITING_RESULTS -> R.string.health_agent_next_results
        HealthCareStage.REASSESS -> R.string.health_agent_next_reassess
        HealthCareStage.MAINTENANCE -> R.string.health_agent_next_maintenance
        HealthCareStage.PAUSED -> R.string.health_agent_next_paused
        HealthCareStage.CLOSED -> R.string.health_agent_next_closed
    }

    private fun discuss(concernId: String) {
        if (names.fixture != null || openingDiscussion || !active || !agentPage) return
        openingDiscussion = true
        val from = visibleConversation
        val token = navigationGeneration
        worker.execute {
            val result = runCatching {
                HealthPrivacyStore(activity.applicationContext, names.privacy).use { check(it.policy().metrics && it.policy().profile) }
                HealthCareDiscussion.open(activity.applicationContext, concernId)
            }
            main.post {
                openingDiscussion = false
                if (!active || !agentPage || token != navigationGeneration || activity.isFinishing || activity.isDestroyed ||
                    activity.agentTranscriptStore.activeConversation().id != from) return@post
                result.fold({ id -> activity.startActivity(Intent(activity, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", id)) }, {
                    Toast.makeText(activity, R.string.health_care_changed, Toast.LENGTH_LONG).show()
                })
            }
        }
    }
}
