package com.signalasi.chat

internal object AgentScreenObservationPolicy {
    private val screenActionKinds = setOf(
        AgentActionKind.READ_SCREEN,
        AgentActionKind.TAP,
        AgentActionKind.TYPE_TEXT,
        AgentActionKind.SWIPE,
        AgentActionKind.LONG_PRESS,
        AgentActionKind.DELETE_TEXT,
        AgentActionKind.PASTE_TEXT,
        AgentActionKind.COPY_SCREEN_TEXT
    )

    private val explicitScreenTerms = listOf(
        "screen",
        "current page",
        "this page",
        "clipboard",
        "selected text",
        "visible text",
        "click",
        "tap",
        "swipe",
        "input field",
        "open app",
        "launch app",
        "\u5c4f\u5e55",
        "\u5f53\u524d\u9875\u9762",
        "\u8fd9\u4e2a\u9875\u9762",
        "\u526a\u8d34\u677f",
        "\u9009\u4e2d\u6587\u5b57",
        "\u53ef\u89c1\u6587\u5b57",
        "\u70b9\u51fb",
        "\u6ed1\u52a8",
        "\u8f93\u5165\u6846",
        "\u6253\u5f00app",
        "\u6253\u5f00 app",
        "\u542f\u52a8app",
        "\u542f\u52a8 app"
    )

    fun requiresObservation(goal: String, selectedAction: AgentAction? = null): Boolean {
        if (selectedAction?.kind in screenActionKinds) return true
        val toolId = selectedAction?.parameters?.get("tool_id").orEmpty().lowercase()
        if (toolId.contains("screen") || toolId.contains("clipboard") || toolId.contains("visible.capture")) {
            return true
        }
        val requirements = AgentTaskRequirementAnalyzer.analyze(goal)
        if (requirements.capabilities.any {
                it == AgentCapability.SCREEN_READING ||
                    it == AgentCapability.APP_NAVIGATION ||
                    it == AgentCapability.CLIPBOARD
            }
        ) {
            return true
        }
        val normalized = goal.lowercase()
        return explicitScreenTerms.any(normalized::contains)
    }
}
