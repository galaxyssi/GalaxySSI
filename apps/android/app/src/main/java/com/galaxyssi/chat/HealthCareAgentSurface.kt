package com.galaxyssi.chat

import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.LinearLayout
import java.util.concurrent.Executors

/** Displays local health context only inside its independently bound Agent conversation. */
internal class HealthCareAgentSurface(
    private val activity: MainActivity,
    private val names: HealthOverviewDatabases = HealthOverviewDatabases()
) {
    private val host = activity.findViewById<LinearLayout>(R.id.agentHealthCareSurface)
    private val ui = HealthCenterViews(activity)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var active = false
    private var agentPage = activity.findViewById<View>(R.id.collaborationOutputList).visibility != View.VISIBLE
    private var loading = false
    private var dirty = false
    private var generation = 0
    private var visibleConversation = ""
    private val basisRows = mutableSetOf<HealthAnswerBasisRow>()
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) {
            generation++
            basisRows.forEach { requestBasis(it, false) }
            reload()
        }
    }

    fun resume() {
        if (active) return
        active = true
        listOf(HealthCareStore.changes(activity, names.care), HealthPrivacyStore.changes(activity, names.privacy),
            HealthRecordStore.changes(activity, names.records), HealthProfileStore.changes(activity, names.profile)).forEach {
            activity.contentResolver.registerContentObserver(it, false, observer)
        }
        reload()
        basisRows.forEach { requestBasis(it, false) }
    }

    fun pause() {
        if (active) activity.contentResolver.unregisterContentObserver(observer)
        active = false
        clear()
    }

    fun clear() {
        basisRows.forEach { it.hide() }
        modelReviewVisibility(null)
        generation++
        host.removeAllViews()
        host.visibility = View.GONE
    }

    private fun modelReviewVisibility(conversation: String?) {
        val changed = if (conversation == null) HealthCareModelReviewVisibility.hide(this)
            else HealthCareModelReviewVisibility.show(this, names.care, conversation)
        if (changed && names.fixture == null) HealthReminderWork.sourceRemindersChanged(activity.applicationContext)
    }

    fun showForAgent(value: Boolean) {
        agentPage = value
        if (value) reload() else clear()
    }

    fun answerRow(conversation: String, turn: String): View? {
        val current = activity.agentTranscriptStore.activeConversation()
        if (turn.isBlank() || current.id != conversation || HealthCareAgentScope.concernId(current) == null) return null
        return HealthAnswerBasisRow(activity, conversation, turn, { row, attach ->
            if (attach) { basisRows.add(row); requestBasis(row, false) } else basisRows.remove(row)
        }, ::requestBasis)
    }

    private fun requestBasis(row: HealthAnswerBasisRow, expand: Boolean) {
        row.hide()
        if (!active || !agentPage || !row.isAttachedToWindow ||
            activity.agentTranscriptStore.activeConversation().id != row.conversation) return
        val token = row.token
        worker.execute {
            val context = activity.applicationContext
            val result = runCatching {
                val current = AgentTranscriptStore(context).conversation(row.conversation)
                val concern = current?.let(HealthCareAgentScope::concernId) ?: return@runCatching null
                if (HealthCareDiscussion.rejection(context, row.conversation, row.turn, names = names) != null) return@runCatching null
                HealthCareStore(context, names.care).use { store ->
                    val grant = store.discussionGrant(row.turn)?.takeIf { it.conversationId == row.conversation && it.concernId == concern }
                        ?: return@use null
                    store.answerBasis(grant) to (grant.approvedAt + HealthCareDiscussionPolicy.MAX_APPROVAL_AGE)
                }
            }.getOrNull()
            main.post {
                if (active && agentPage && row.isAttachedToWindow && row.token == token && row in basisRows && result != null &&
                    activity.agentTranscriptStore.activeConversation().id == row.conversation)
                    row.display(result.first, result.second, expand)
            }
        }
    }

    fun destroy() {
        pause()
        worker.shutdown()
    }

    private fun reload() {
        if (!active || !agentPage) return
        val conversation = activity.agentTranscriptStore.activeConversation()
        if (conversation.id != visibleConversation) {
            clear()
            visibleConversation = conversation.id
        }
        val concernId = HealthCareAgentScope.concernId(conversation)
        if (concernId == null) {
            clear()
            dirty = false
            return
        }
        if (loading) {
            dirty = true
            return
        }
        loading = true
        dirty = false
        val token = generation
        worker.execute {
            val result = runCatching {
                val context = activity.applicationContext
                if (!context.getDatabasePath(names.care).exists()) return@runCatching null
                HealthCareEngine.evaluate(context, names)
                if (!HealthPrivacyStore(context, names.privacy).use { it.policy().metrics }) return@runCatching null
                HealthCareStore(context, names.care).use { store ->
                    if (store.settings().enabled && store.discussion(conversation.id) == concernId)
                        store.concern(concernId)
                    else null
                }
            }
            main.post {
                loading = false
                if (active && agentPage && token == generation && activity.agentTranscriptStore.activeConversation().id == conversation.id) {
                    val concern = result.getOrNull()
                    modelReviewVisibility(conversation.id.takeIf { concern != null })
                    host.removeAllViews()
                    host.visibility = if (concern == null && result.isSuccess) View.GONE else View.VISIBLE
                    if (result.isFailure) host.addView(ui.profileRow(activity.getString(R.string.health_care_partial)) { reload() })
                    else if (concern != null) host.addView(HealthCareAgentPanel(activity, concern.metric, concern.assessment))
                }
                if (active && agentPage && (dirty || token != generation)) reload()
            }
        }
    }
}
