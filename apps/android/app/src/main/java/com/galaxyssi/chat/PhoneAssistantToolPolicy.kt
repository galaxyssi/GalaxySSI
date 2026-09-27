package com.galaxyssi.chat

internal object PhoneAssistantToolPolicy {
    fun allowsRemotePhoneTool(id: String): Boolean = id in AgentPhoneUiNativeTools.toolIds ||
        id.startsWith("galaxyssi.hardware.") || id.startsWith("galaxyssi.notifications.") ||
        id in setOf(AgentVisibleCaptureNativeTools.CAMERA_CAPTURE, AgentVisibleCaptureNativeTools.MICROPHONE_RECORD,
            AgentNativeToolAgentActionAdapter.defaultToolId(AgentActionKind.OPEN_APP),
            AgentNativeToolAgentActionAdapter.defaultToolId(AgentActionKind.BACK),
            AgentNativeToolAgentActionAdapter.defaultToolId(AgentActionKind.HOME))
}
