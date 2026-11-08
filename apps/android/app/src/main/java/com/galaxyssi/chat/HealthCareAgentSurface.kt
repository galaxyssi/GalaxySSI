package com.galaxyssi.chat

import android.content.Intent
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.LinearLayout
import java.util.concurrent.Executors

/** The Agent landing page surfaces local concerns without putting health data in an unrelated chat transcript. */
internal class HealthCareAgentSurface(private val activity: MainActivity, private val names: HealthOverviewDatabases = HealthOverviewDatabases()) {
    private val host = activity.findViewById<LinearLayout>(R.id.agentHealthCareSurface)
    private val ui = HealthCenterViews(activity)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val planReview = HealthCarePlanReview(activity, names)
    private val actionReview = HealthCareActionReview(activity, names)
    private val targetReview = HealthCareTargetReview(activity, names)
    private val historyReview = HealthCareHistoryReview(activity, names)
    private var active = false
    private var agentPage = activity.findViewById<View>(R.id.collaborationOutputList).visibility != View.VISIBLE
    private var loading = false
    private var dirty = false
    private var generation = 0
    private var visibleConversation = ""
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) { planReview.clear(); actionReview.clear(); targetReview.clear(); historyReview.clear(); generation++; reload() }
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
    fun clear() { generation++; planReview.clear(); actionReview.clear(); targetReview.clear(); historyReview.clear(); host.removeAllViews(); host.visibility = View.GONE }
    fun showForAgent(value: Boolean) {
        agentPage = value
        if (value) reload() else clear()
    }
    fun destroy() { pause(); planReview.destroy(); actionReview.destroy(); targetReview.destroy(); historyReview.destroy(); worker.shutdown() }
    private data class Snapshot(val concerns: List<HealthCareConcern>, val plans: List<HealthCarePlan> = emptyList(),
        val action: HealthCareAction? = null, val reminder: HealthCareReminder? = null, val profile: Boolean = false)
    private fun reload() {
        if (!active || !agentPage) return
        val conversation = activity.agentTranscriptStore.activeConversation()
        if (conversation.id != visibleConversation) {
            visibleConversation = conversation.id
            planReview.clear(); actionReview.clear(); targetReview.clear(); historyReview.clear(); generation++
        }
        if (loading) { dirty = true; return }
        loading = true; dirty = false; val token = generation
        worker.execute {
            val result = runCatching {
                val context = activity.applicationContext
                if (!context.getDatabasePath(names.care).exists()) Snapshot(emptyList()) else {
                    HealthCareEngine.evaluate(context, names)
                    HealthPrivacyStore(context, names.privacy).use { privacy ->
                        if (!privacy.policy().metrics) Snapshot(emptyList()) else HealthCareStore(context, names.care).use { store ->
                            val concerns = if (!store.settings().enabled) emptyList()
                            else if (conversation.globalTopicKey.startsWith(HealthCareDiscussionPolicy.TOPIC_PREFIX))
                                listOfNotNull(store.discussion(conversation.id)?.let(store::concern))
                            else store.page(limit = 3, includePaused = false).items
                            val issue = concerns.firstOrNull()
                            val profile = privacy.policy().profile
                            val reminders = if (profile && issue != null) store.reminders(issue.id) else emptyList()
                            val action = if (profile) issue?.actions?.filter { it.state == HealthCareActionState.CONFIRMED }
                                ?.minByOrNull { item -> reminders.firstOrNull { it.actionId == item.id && it.state != HealthCareReminderState.CANCELLED }?.dueAt ?: Long.MAX_VALUE }
                                else null
                            Snapshot(concerns, if (profile && issue != null) store.pendingPlans(issue.id) else emptyList(),
                                action, reminders.firstOrNull { it.actionId == action?.id }, profile)
                        }
                    }
                }
            }
            main.post {
                loading = false
                if (active && agentPage && token == generation && activity.agentTranscriptStore.activeConversation().id == conversation.id) {
                    host.removeAllViews()
                    val snapshot = result.getOrDefault(Snapshot(emptyList()))
                    val concerns = snapshot.concerns
                    host.visibility = if (concerns.isEmpty() && result.isSuccess) View.GONE else View.VISIBLE
                    if (result.isFailure) host.addView(ui.profileRow(activity.getString(R.string.health_care_partial)) { reload() })
                    else concerns.firstOrNull()?.let { item ->
                        HealthCarePriorityPresentation.add(activity, host, item, compact = true) {
                            activity.startActivity(Intent(activity, HealthCareActivity::class.java).putExtra("health_care_id", item.id)
                                .putHealthNavigationFixture(names))
                        }
                        host.addView(ui.profileRow(activity.getString(item.metric.titleResource()) + " · " + activity.getString(item.stage.titleResource()),
                            HealthCareComparisonPresentation.summary(activity, item.assessment)
                                ?: "${item.assessment.value} ${item.assessment.unit}") {
                            activity.startActivity(Intent(activity, HealthCareActivity::class.java).putExtra("health_care_id", item.id)
                                .putHealthNavigationFixture(names))
                        }.apply { tag = "agent-health-care-concern" })
                        if (snapshot.profile && item.assessment.series != null) host.addView(ui.profileRow(
                            activity.getString(R.string.health_series_title), activity.getString(R.string.health_series_summary)) {
                            historyReview.show(item.id)
                        }.apply { tag = "agent-health-care-series" })
                        snapshot.plans.firstOrNull()?.let { plan ->
                            host.addView(ui.profileRow(HealthCareTargetPresentation.planTitle(activity, plan)) {
                                planReview.show(plan.id)
                            }.apply { tag = "agent-health-care-plan" })
                        }
                        if (snapshot.profile && item.target != null) host.addView(ui.profileRow(activity.getString(R.string.health_target_review),
                            HealthCareTargetPresentation.status(activity, item)) { targetReview.show(item.id) }
                            .apply { tag = "agent-health-care-target" })
                        snapshot.action?.let { action ->
                            host.addView(ui.profileRow(activity.getString(R.string.health_care_followup_title), action.description) {
                                actionReview.show(item.id, action.id)
                            }.apply { tag = "agent-health-care-followup" })
                        }
                    }
                }
                if (active && agentPage && (dirty || token != generation)) reload()
            }
        }
    }
}
