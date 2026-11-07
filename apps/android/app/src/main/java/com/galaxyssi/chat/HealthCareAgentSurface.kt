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
    private var active = false
    private var agentPage = activity.findViewById<View>(R.id.collaborationOutputList).visibility != View.VISIBLE
    private var loading = false
    private var dirty = false
    private var generation = 0
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) { generation++; reload() }
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
    fun clear() { generation++; host.removeAllViews(); host.visibility = View.GONE }
    fun showForAgent(value: Boolean) {
        agentPage = value
        if (value) reload() else clear()
    }
    fun destroy() { pause(); worker.shutdown() }
    private fun reload() {
        if (!active || !agentPage) return
        if (loading) { dirty = true; return }
        loading = true; dirty = false; val token = generation
        val conversation = activity.agentTranscriptStore.activeConversation()
        worker.execute {
            val result = runCatching {
                val context = activity.applicationContext
                if (!context.getDatabasePath(names.care).exists()) emptyList() else {
                    HealthCareEngine.evaluate(context, names)
                    HealthPrivacyStore(context, names.privacy).use { privacy ->
                        if (!privacy.policy().metrics) emptyList() else HealthCareStore(context, names.care).use { store ->
                            if (!store.settings().enabled) emptyList()
                            else if (conversation.globalTopicKey.startsWith(HealthCareDiscussionPolicy.TOPIC_PREFIX))
                                listOfNotNull(store.discussion(conversation.id)?.let(store::concern))
                            else store.page(limit = 3, includePaused = false).items
                        }
                    }
                }
            }
            main.post {
                loading = false
                if (active && agentPage && token == generation && activity.agentTranscriptStore.activeConversation().id == conversation.id) {
                    host.removeAllViews()
                    val concerns = result.getOrDefault(emptyList())
                    host.visibility = if (concerns.isEmpty() && result.isSuccess) View.GONE else View.VISIBLE
                    if (result.isFailure) host.addView(ui.profileRow(activity.getString(R.string.health_care_partial)) { reload() })
                    else concerns.firstOrNull()?.let { item ->
                        host.addView(ui.profileRow(activity.getString(item.metric.titleResource()) + " · " + activity.getString(item.stage.titleResource()),
                            "${item.assessment.value} ${item.assessment.unit}") {
                            activity.startActivity(Intent(activity, HealthCareActivity::class.java).putExtra("health_care_id", item.id)
                                .putHealthNavigationFixture(names))
                        }.apply { tag = "agent-health-care-concern" })
                    }
                }
                if (active && agentPage && (dirty || token != generation)) reload()
            }
        }
    }
}
