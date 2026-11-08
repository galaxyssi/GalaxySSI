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
    private var active = false
    private var agentPage = activity.findViewById<View>(R.id.collaborationOutputList).visibility != View.VISIBLE
    private var loading = false
    private var dirty = false
    private var generation = 0
    private var visibleConversation = ""
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) { planReview.clear(); generation++; reload() }
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
    fun clear() { generation++; planReview.clear(); host.removeAllViews(); host.visibility = View.GONE }
    fun showForAgent(value: Boolean) {
        agentPage = value
        if (value) reload() else clear()
    }
    fun destroy() { pause(); planReview.destroy(); worker.shutdown() }
    private data class Snapshot(val concerns: List<HealthCareConcern>, val plans: List<HealthCarePlan> = emptyList())
    private fun reload() {
        if (!active || !agentPage) return
        val conversation = activity.agentTranscriptStore.activeConversation()
        if (conversation.id != visibleConversation) {
            visibleConversation = conversation.id
            planReview.clear(); generation++
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
                            Snapshot(concerns, if (privacy.policy().profile) concerns.firstOrNull()?.let { store.pendingPlans(it.id) }
                                ?: emptyList() else emptyList())
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
                        host.addView(ui.profileRow(activity.getString(item.metric.titleResource()) + " · " + activity.getString(item.stage.titleResource()),
                            "${item.assessment.value} ${item.assessment.unit}") {
                            activity.startActivity(Intent(activity, HealthCareActivity::class.java).putExtra("health_care_id", item.id)
                                .putHealthNavigationFixture(names))
                        }.apply { tag = "agent-health-care-concern" })
                        snapshot.plans.firstOrNull()?.let { plan ->
                            host.addView(ui.profileRow(activity.getString(R.string.health_care_plan_pending, plan.actions.size)) {
                                planReview.show(plan.id)
                            }.apply { tag = "agent-health-care-plan" })
                        }
                    }
                }
                if (active && agentPage && (dirty || token != generation)) reload()
            }
        }
    }
}
