package com.galaxyssi.chat

import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Projects existing delivered reminders. It never synthesizes weather, calendar events or task status. */
internal class AgentVoiceReminders(private val activity: MainActivity) {
    private val content = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(activity.dp(20), activity.dp(8), activity.dp(20), activity.dp(16))
    }
    private val scroll = ScrollView(activity).apply { addView(content); visibility = View.GONE }
    private var generation = 0
    private var active = false
    private val listener = GlobalProactiveDeliveryListener { activity.runOnUiThread { if (active) reload() } }

    init {
        val output = activity.findViewById<View>(R.id.agentOutputViewport)
        val parent = output.parent as LinearLayout
        parent.addView(scroll, parent.indexOfChild(output), LinearLayout.LayoutParams(-1, -2))
    }

    fun setActive(value: Boolean) {
        if (active == value) return
        active = value
        if (active) { GlobalProactiveDeliveryBus.addListener(listener); reload() }
        else {
            generation++
            GlobalProactiveDeliveryBus.removeListener(listener)
            scroll.visibility = View.GONE
            content.removeAllViews()
        }
    }
    private fun reload() {
        val token = ++generation
        activity.navigationContentExecutor.execute {
            val reminders = runCatching {
                GlobalAgentRepository(activity).proactiveInboxPreview(AttentionReaderState(), emptySet())
                    .filter { it.isNew }.take(4)
            }.getOrDefault(emptyList())
            activity.runOnUiThread {
                if (!active || token != generation || activity.isDestroyed) return@runOnUiThread
                content.removeAllViews()
                for (reminder in reminders) {
                    content.addView(TextView(activity).apply {
                        text = reminder.topic.ifBlank { reminder.title }
                        textSize = 13f; setTextColor(activity.getColor(R.color.text_secondary))
                        setPadding(0, activity.dp(14), 0, activity.dp(6))
                    })
                    content.addView(TextView(activity).apply {
                        text = reminder.content
                        textSize = 17f; maxLines = 5
                        ellipsize = android.text.TextUtils.TruncateAt.END
                        setTextColor(activity.getColor(R.color.text_primary))
                    })
                }
                scroll.visibility = if (reminders.isEmpty()) View.GONE else View.VISIBLE
                scroll.layoutParams = (scroll.layoutParams as LinearLayout.LayoutParams).apply {
                    height = (activity.resources.configuration.screenHeightDp * 0.45f).toInt().let(activity::dp)
                }
            }
        }
    }
}
