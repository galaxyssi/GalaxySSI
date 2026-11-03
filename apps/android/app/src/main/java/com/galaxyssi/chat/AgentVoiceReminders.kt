package com.galaxyssi.chat

import android.content.Intent
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Personal reminders occupy the empty transcript viewport, never a second news reader. */
internal class AgentVoiceReminders(private val activity: MainActivity,
    private val load: () -> VoiceReminderSnapshot = { VoiceReminderRepository(activity).load() }) {
    private val content = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(activity.dp(20), activity.dp(8), activity.dp(20), activity.dp(16))
    }
    internal val scroll = ScrollView(activity).apply {
        addView(content); visibility = View.GONE; tag = "voice-reminders"
    }
    private var generation = 0
    private var active = false
    private var loading = false
    private var dirty = false
    private val changed = Runnable { if (active) reload() }
    private val listener = GlobalProactiveDeliveryListener { activity.runOnUiThread { changed.run() } }
    private val scheduleListener: (String) -> Unit = { activity.runOnUiThread { changed.run() } }

    init {
        activity.findViewById<FrameLayout>(R.id.agentOutputViewport)
            .addView(scroll, FrameLayout.LayoutParams(-1, -1))
    }

    fun setActive(value: Boolean) {
        if (active == value) return
        active = value
        generation++
        if (active) {
            GlobalProactiveDeliveryBus.addListener(listener)
            ConversationScheduleState.add(scheduleListener)
            reload()
        } else {
            GlobalProactiveDeliveryBus.removeListener(listener)
            ConversationScheduleState.remove(scheduleListener)
            activity.handler.removeCallbacks(changed)
            dirty = false
            scroll.visibility = View.GONE
            content.removeAllViews()
        }
    }
    private fun reload() {
        if (loading) { dirty = true; return }
        loading = true
        dirty = false
        val token = generation
        activity.navigationContentExecutor.execute {
            val snapshot = runCatching(load).getOrElse { VoiceReminderSnapshot(emptyList(), mapOf("all" to "unavailable")) }
            activity.runOnUiThread {
                loading = false
                if (activity.isDestroyed || !active) return@runOnUiThread
                if (token == generation) {
                    render(snapshot)
                    activity.handler.removeCallbacks(changed)
                    // Only while visible; refresh time-sensitive state without model calls.
                    activity.handler.postDelayed(changed, 60_000L)
                }
                if (dirty || token != generation) reload()
            }
        }
    }

    private fun render(snapshot: VoiceReminderSnapshot) {
        content.removeAllViews()
        if (snapshot.items.isEmpty()) content.addView(TextView(activity).apply {
            setText(if (snapshot.sources.values.any { it == "unavailable" }) R.string.voice_reminder_unavailable
                else R.string.voice_reminder_empty)
            textSize = 16f; setTextColor(activity.getColor(R.color.text_secondary))
            setPadding(0, activity.dp(20), 0, 0)
        })
        snapshot.items.forEach { reminder ->
            val row = LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(0, activity.dp(14), 0, activity.dp(10))
            }
            row.addView(TextView(activity).apply {
                text = reminder.title
                textSize = 13f; setTextColor(activity.getColor(R.color.text_secondary))
                setPadding(0, 0, 0, activity.dp(6))
            })
            row.addView(TextView(activity).apply {
                text = reminder.content
                textSize = 17f; maxLines = 5
                ellipsize = android.text.TextUtils.TruncateAt.END
                setTextColor(activity.getColor(R.color.text_primary))
            })
            if (reminder.kind == "news") row.setOnClickListener {
                activity.startActivity(Intent(activity, ProactiveAttentionActivity::class.java))
            }
            content.addView(row)
        }
        scroll.visibility = View.VISIBLE
    }
}
