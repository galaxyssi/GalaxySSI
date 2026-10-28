package com.galaxyssi.chat

internal object PhoneAssistantToolPolicy {
    val directActionToolIds = setOf(
        AgentNativeToolAgentActionAdapter.defaultToolId(AgentActionKind.SET_ALARM),
        AgentNativeToolAgentActionAdapter.defaultToolId(AgentActionKind.OPEN_APP)
    )

    fun allowsGeneralPhoneTool(id: String): Boolean =
        allowsRemotePhoneTool(id) || AgentPhoneDevelopmentPolicy.isPhoneDevelopmentTool(id)

    fun allowsRemotePhoneTool(id: String): Boolean = id == AgentConversationRecallTool.ID || id in AgentAppControlTools.toolIds ||
        id in AgentToolInspectionTools.toolIds || id in AgentPhoneUiNativeTools.toolIds ||
        id in AgentWebIntelligenceNativeTools.directSearchToolIds ||
        id in AgentInteractiveBrowserTools.toolIds ||
        id in AgentRuntimeControlTools.toolIds ||
        id in setOf(AgentAndroidSystemNativeTools.AUDIO_STATUS, AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET,
            AgentAndroidSystemNativeTools.AUDIO_MUTE_SET) ||
        id in setOf(AgentOnDeviceRuntimeTools.STATUS, AgentOnDeviceRuntimeTools.LIST_PACKS, AgentOnDeviceRuntimeTools.INSTALL_PACK) ||
        id.startsWith("galaxyssi.hardware.") || id.startsWith("galaxyssi.notifications.") ||
        id in setOf(AgentVisibleCaptureNativeTools.CAMERA_CAPTURE, AgentVisibleCaptureNativeTools.MICROPHONE_RECORD,
            AgentNativeToolAgentActionAdapter.defaultToolId(AgentActionKind.OPEN_APP),
            AgentNativeToolAgentActionAdapter.defaultToolId(AgentActionKind.SET_ALARM),
            AgentNativeToolAgentActionAdapter.defaultToolId(AgentActionKind.BACK),
            AgentNativeToolAgentActionAdapter.defaultToolId(AgentActionKind.HOME))
}
