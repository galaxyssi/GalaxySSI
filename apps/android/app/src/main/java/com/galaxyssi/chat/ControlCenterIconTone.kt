package com.galaxyssi.chat

internal fun controlCenterIconTone(iconRes: Int): ControlCenterTone = when (iconRes) {
    R.drawable.ic_settings_voice, R.drawable.ic_input_voice, R.drawable.ic_voice_call_wave,
    R.drawable.ic_security_shield, R.drawable.ic_scan, R.drawable.ic_send_plane,
    R.drawable.ic_local_model -> ControlCenterTone.GREEN
    R.drawable.ic_agent_memory, R.drawable.ic_agent_knowledge -> ControlCenterTone.VIOLET
    R.drawable.ic_agent_skill, R.drawable.ic_agent_control -> ControlCenterTone.AMBER
    else -> ControlCenterTone.BLUE
}
