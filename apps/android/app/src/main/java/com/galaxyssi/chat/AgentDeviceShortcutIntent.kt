package com.galaxyssi.chat

import java.util.Locale

/** A shortcut owns the whole command, or leaves it unchanged for the selected model. */
internal object AgentDeviceShortcutIntent {
    data class Parsed(val toolId: String, val input: AgentNativeJsonObject)

    private enum class Family { FLASHLIGHT, VOLUME, CAMERA, MICROPHONE }

    fun requiresReasoning(goal: String): Boolean =
        family(goal) != null && parse(goal) == null || AgentDeviceStatusShortcutCoverage.requiresReasoning(goal)

    fun parse(goal: String): Parsed? {
        val command = normalize(goal)
        return when (family(command)) {
            Family.FLASHLIGHT -> {
                val on = FLASHLIGHT_ON.matches(command)
                if (!on && !FLASHLIGHT_OFF.matches(command)) return null
                Parsed(AgentHardwareNativeTools.FLASHLIGHT_SET, mapOf("enabled" to on))
            }
            Family.VOLUME -> {
                val match = VOLUME_EN.matchEntire(command) ?: VOLUME_ZH.matchEntire(command) ?: return null
                val percent = match.groupValues[2].toIntOrNull()?.takeIf { it in 0..100 } ?: return null
                val stream = when (match.groupValues[1]) {
                    "ring", "ringer", "\u94c3\u58f0", "\u9234\u8072" -> "ring"
                    "alarm", "\u95f9\u949f", "\u9b27\u9418" -> "alarm"
                    "notification", "\u901a\u77e5" -> "notification"
                    "call", "\u901a\u8bdd", "\u901a\u8a71" -> "voice_call"
                    else -> "music"
                }
                Parsed(AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET, mapOf("stream" to stream, "percent" to percent))
            }
            Family.CAMERA -> if (CAMERA_EN.matches(command) || CAMERA_ZH.matches(command)) {
                Parsed(AgentVisibleCaptureNativeTools.CAMERA_CAPTURE, mapOf("facing" to "back"))
            } else null
            Family.MICROPHONE -> {
                val match = RECORD_EN.matchEntire(command) ?: RECORD_ZH.matchEntire(command) ?: return null
                val seconds = AgentDeviceIntent.completeDurationSeconds(match.groupValues[1])
                    ?.takeIf { it in 1..AgentVisibleCaptureNativeTools.MAX_AUDIO_DURATION_SECONDS } ?: return null
                Parsed(AgentVisibleCaptureNativeTools.MICROPHONE_RECORD, mapOf("max_duration_seconds" to seconds))
            }
            null -> null
        }
    }

    private fun family(goal: String): Family? {
        val text = goal.lowercase(Locale.ROOT)
        return when {
            VOLUME_SUBJECT.containsMatchIn(text) && VOLUME_ACTION.containsMatchIn(text) -> Family.VOLUME
            FLASHLIGHT_SUBJECT.containsMatchIn(text) && SWITCH_ACTION.containsMatchIn(text) -> Family.FLASHLIGHT
            CAMERA_ACTION.containsMatchIn(text) -> Family.CAMERA
            RECORD_ACTION.containsMatchIn(text) -> Family.MICROPHONE
            else -> null
        }
    }

    private fun normalize(goal: String): String = goal.trim().lowercase(Locale.ROOT)
        .trimEnd('.', '!', '\u3002', '\uff01').trim()
        .replaceFirst(Regex("^(?:please\\s+|(?:\u8bf7|\u8acb)(?:\u5e2e\u6211|\u5e6b\u6211)?\\s*|(?:\u5e2e\u6211|\u5e6b\u6211)\\s*)"), "")

    private val FLASHLIGHT_SUBJECT = Regex("\\b(?:flashlight|torch)\\b|\u624b\u7535\u7b52|\u624b\u96fb\u7b52|\u95ea\u5149\u706f|\u9583\u5149\u71c8")
    private val SWITCH_ACTION = Regex("\\b(?:on|off|open|close|enable|disable)\\b|\u6253\u5f00|\u6253\u958b|\u5f00\u542f|\u958b\u555f|\u5173\u95ed|\u95dc\u9589|\u5173\u6389|\u95dc\u6389")
    private val FLASHLIGHT_ON = Regex("(?:(?:turn|switch) on (?:the )?(?:flashlight|torch)|open (?:the )?(?:flashlight|torch)|(?:flashlight|torch) on|(?:\u6253\u5f00|\u6253\u958b|\u5f00\u542f|\u958b\u555f)(?:\u624b\u7535\u7b52|\u624b\u96fb\u7b52|\u95ea\u5149\u706f|\u9583\u5149\u71c8))")
    private val FLASHLIGHT_OFF = Regex("(?:(?:turn|switch) off (?:the )?(?:flashlight|torch)|close (?:the )?(?:flashlight|torch)|(?:flashlight|torch) off|(?:\u5173\u95ed|\u95dc\u9589|\u5173\u6389|\u95dc\u6389)(?:\u624b\u7535\u7b52|\u624b\u96fb\u7b52|\u95ea\u5149\u706f|\u9583\u5149\u71c8))")
    private val VOLUME_SUBJECT = Regex("\\bvolume\\b|\u97f3\u91cf")
    private val VOLUME_ACTION = Regex("\\b(?:set|change|adjust|increase|decrease|raise|lower|turn)\\b|\u8bbe|\u8a2d|\u8c03|\u8abf|\u6539|\u964d|\u63d0|\\d")
    private val VOLUME_EN = Regex("(?:set|change|adjust) (?:(media|music|ring|ringer|alarm|notification|call) )?volume (?:to )?(\\d{1,3})\\s*(?:%|percent)?")
    private val VOLUME_ZH = Regex("(?:\u628a)?(\u5a92\u4f53|\u5a92\u9ad4|\u94c3\u58f0|\u9234\u8072|\u95f9\u949f|\u9b27\u9418|\u901a\u77e5|\u901a\u8bdd|\u901a\u8a71)?\u97f3\u91cf(?:\u8bbe\u7f6e\u4e3a|\u8a2d\u7f6e\u70ba|\u8bbe\u4e3a|\u8a2d\u70ba|\u8c03\u5230|\u8abf\u5230|\u6539\u6210)\\s*(\\d{1,3})\\s*%?")
    private val CAMERA_ACTION = Regex("\\b(?:open|launch|use) (?:the )?(?:phone )?camera\\b|\\btake (?:a |one )?photo\\b|\u62cd\u7167|\u62cd.*\u7167\u7247|(?:\u6253\u5f00|\u6253\u958b|\u542f\u52a8|\u555f\u52d5|\u8c03\u7528|\u8abf\u7528|\u4f7f\u7528).*(?:\u76f8\u673a|\u76f8\u6a5f|\u6444\u50cf\u5934|\u651d\u50cf\u982d)")
    private val CAMERA_EN = Regex("(?:(?:open|launch) (?:the )?camera(?: and take (?:a |one )?photo)?|use phone camera|take (?:a |one )?photo)")
    private val CAMERA_ZH = Regex("(?:(?:\u6253\u5f00|\u6253\u958b|\u542f\u52a8|\u555f\u52d5|\u8c03\u7528|\u8abf\u7528|\u4f7f\u7528)(?:\u624b\u673a|\u624b\u6a5f|\u672c\u673a|\u672c\u6a5f)?(?:\u76f8\u673a|\u76f8\u6a5f|\u6444\u50cf\u5934|\u651d\u50cf\u982d)(?:\u62cd\u7167|\u62cd\u4e00\u5f20\u7167\u7247|\u62cd\u4e00\u5f35\u7167\u7247)?|\u62cd\u7167|\u62cd\u4e00\u5f20\u7167\u7247|\u62cd\u4e00\u5f35\u7167\u7247)")
    private val RECORD_ACTION = Regex("\\brecord (?:audio|voice|with microphone)\\b|\\buse microphone to record\\b|\u5f55\u97f3|\u9304\u97f3|(?:\u4f7f\u7528|\u8c03\u7528|\u8abf\u7528|\u5f00\u59cb|\u958b\u59cb).*\u9ea6\u514b\u98ce|(?:\u4f7f\u7528|\u8abf\u7528|\u958b\u59cb).*\u9ea5\u514b\u98a8")
    private val RECORD_EN = Regex("(?:record (?:audio|voice|with microphone)|use microphone to record) (?:for )?(.+)")
    private val RECORD_ZH = Regex("(?:(?:\u5f00\u59cb|\u958b\u59cb)?(?:\u5f55\u97f3|\u9304\u97f3))\\s*(.+)")
}
