package com.galaxyssi.chat

import android.view.View
import android.widget.ScrollView

/** Poll only the already-hydrated projection. Never load research records on the UI thread. */
internal fun MainActivity.watchCollaborationTeamDetails(initial: AgentTeamExecutionSnapshot) {
    val anchor = featureContent.getChildAt(0) ?: return
    fun fingerprint(team: AgentTeamExecutionSnapshot): Int = listOf(team.state, team.paused, team.goalDisposition,
        CollaborationCurrentStatePolicy.members(team).map { CollaborationCurrentStateStore.metadata(team, it) }).hashCode()
    val initialFingerprint = fingerprint(initial)
    val refresh = object : Runnable {
        override fun run() {
            if (!anchor.isAttachedToWindow || isFinishing || isDestroyed) return
            if (anchor.isShown) {
                val team = CollaborationCurrentStateStore.team(initial.supervisorRunId)
                if (team != null && fingerprint(team) != initialFingerprint) {
                    val scroll = featureContent.parent as? ScrollView
                    val y = scroll?.scrollY ?: 0
                    val back = featureBackAction
                    showAgentTeamDetails(team)
                    featureBackAction = back
                    scroll?.post { scroll.scrollTo(0, y) }
                    return
                }
            }
            handler.postDelayed(this, 1_000L)
        }
    }
    anchor.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(view: View) = Unit
        override fun onViewDetachedFromWindow(view: View) { handler.removeCallbacks(refresh) }
    })
    handler.postDelayed(refresh, 1_000L)
}
