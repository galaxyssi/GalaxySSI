package com.galaxyssi.chat

import android.view.View
import android.widget.LinearLayout

internal fun MainActivity.addAgentTeamMessageHistory(supervisorRunId: String) {
    addSectionTitle(getString(R.string.agent_team_messages_label))
    val title = featureContent.getChildAt(featureContent.childCount - 1).apply { visibility = View.GONE }
    val rows = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    featureContent.addView(rows)
    lateinit var load: AgentTeamHistoryLoad
    load = AgentTeamHistoryLoad(
        executor = navigationContentExecutor,
        post = { action -> runOnUiThread(action) },
        read = { globalSuperAgentRuntime.recentAgentTeamMessages(supervisorRunId) },
        render = render@{ result ->
            if (isFinishing || isDestroyed || !rows.isAttachedToWindow || rows.parent !== featureContent) return@render
            rows.removeAllViews()
            title.visibility = if (result.isFailure || result.getOrNull().orEmpty().isNotEmpty()) View.VISIBLE else View.GONE
            result.fold(onSuccess = { messages ->
                messages.forEach { message ->
                    rows.addView(featureRow(
                        title = getString(R.string.agent_team_message_route, message.fromInstanceId,
                            message.toInstanceId.ifBlank { getString(R.string.agent_team_everyone) }),
                        subtitle = message.text,
                        iconRes = R.drawable.ic_composer_send_plane,
                        action = when (message.state) {
                            AgentTeamMessageState.PENDING -> getString(R.string.agent_team_message_pending)
                            AgentTeamMessageState.DELIVERED -> getString(R.string.agent_team_message_delivered)
                            AgentTeamMessageState.ACKNOWLEDGED -> getString(R.string.agent_team_message_acknowledged)
                        }
                    ))
                }
            }, onFailure = {
                rows.addView(featureRow(title = getString(R.string.agent_team_history_load_failed), subtitle = "",
                    iconRes = R.drawable.ic_agent_history, action = getString(R.string.common_retry)).apply {
                    setOnClickListener { isEnabled = false; load.refresh() }
                })
            })
        }
    )
    rows.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(view: View) { load.refresh() }
        override fun onViewDetachedFromWindow(view: View) { load.cancel() }
    })
    if (rows.isAttachedToWindow) load.refresh()
}
