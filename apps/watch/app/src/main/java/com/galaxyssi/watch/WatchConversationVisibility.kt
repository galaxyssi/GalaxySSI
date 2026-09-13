package com.galaxyssi.watch

data class WatchConversationKey(val desktop: String, val route: String, val agent: String, val conversation: String)

fun WatchTask.conversationKey() = WatchConversationKey(desktopId, routeId, agentId, conversationId)

/** Tracks the resumed conversation screen, independently of background transport. */
class WatchConversationVisibility {
    private var owner: Any? = null
    private var conversation: WatchConversationKey? = null

    @Synchronized fun show(screen: Any, task: WatchTask?) {
        owner = screen
        conversation = task?.conversationKey()
    }

    @Synchronized fun hide(screen: Any) {
        if (owner === screen) { owner = null; conversation = null }
    }

    @Synchronized fun isViewing(task: WatchTask) = conversation == task.conversationKey()
}
