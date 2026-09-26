package com.galaxyssi.glasses

import java.util.Locale

internal enum class VoiceCommand {
    SEND,
    CLEAR,
    SPEAK_REPLY,
    STOP_SPEAKING,
    NEW_CHAT,
    OPEN_SETTINGS,
    STOP_CONFIGURATION,
    CONFIRM_PAIRING,
    CANCEL_PAIRING,
    OPEN_CHAT,
    OPEN_SESSIONS,
    OPEN_CAMERA,
    SCAN_WIFI,
    CONFIRM_WIFI,
    CANCEL_WIFI,
    TAKE_PHOTO,
    START_RECORDING,
    STOP_RECORDING,
    OPEN_GALLERY,
    HOME,
    OPEN_WIFI_SETTINGS,
    OPEN_BLUETOOTH_SETTINGS,
    VOLUME_UP,
    VOLUME_DOWN,
    BATTERY,
    TIME,
    HELP
}

/** Converts short Whisper transcripts into an explicit, allow-listed glasses action. */
internal object VoiceCommandCatalog {
    private val ignoredCharacters = Regex("[\\s,，。.!！?？、:：;；'\"“”‘’_\\-]+")
    private val aliases = buildMap {
        fun command(command: VoiceCommand, vararg phrases: String) {
            phrases.forEach { put(normalize(it), command) }
        }

        command(VoiceCommand.SEND, "发送", "提交", "确认发送")
        command(VoiceCommand.CLEAR, "取消", "清空")
        command(VoiceCommand.SPEAK_REPLY, "朗读", "读出来")
        command(VoiceCommand.STOP_SPEAKING, "停止朗读", "别读了")
        command(VoiceCommand.NEW_CHAT, "新对话")
        command(VoiceCommand.OPEN_SETTINGS, "设置", "打开设置", "手机配置")
        command(VoiceCommand.STOP_CONFIGURATION, "停止配置", "结束配置", "退出配置", "停止配网")
        command(VoiceCommand.CONFIRM_PAIRING, "确认配对", "配对确认")
        command(VoiceCommand.CANCEL_PAIRING, "取消配对")
        command(VoiceCommand.OPEN_CHAT, "返回", "打开对话", "对话", "back")
        command(VoiceCommand.OPEN_SESSIONS, "会话", "最近对话")
        command(VoiceCommand.OPEN_CAMERA, "打开相机", "启动相机", "打开拍照")
        command(VoiceCommand.SCAN_WIFI, "扫描配网", "扫描配网码", "连接 Wi-Fi", "scan Wi-Fi")
        command(VoiceCommand.CONFIRM_WIFI, "确认联网", "confirm Wi-Fi")
        command(VoiceCommand.CANCEL_WIFI, "取消联网", "cancel Wi-Fi")
        command(VoiceCommand.TAKE_PHOTO, "拍照", "拍一张", "照相", "拍张照", "拍张照片", "take photo")
        command(VoiceCommand.START_RECORDING, "开始录像", "启动录像", "录像", "录视频", "开始录制", "start recording")
        command(VoiceCommand.STOP_RECORDING, "停止录像", "结束录像", "停止录制", "stop recording")
        command(VoiceCommand.OPEN_GALLERY, "打开相册", "查看照片")
        command(VoiceCommand.HOME, "回到桌面", "返回桌面", "home")
        command(VoiceCommand.OPEN_WIFI_SETTINGS, "打开 Wi-Fi 设置", "打开无线设置")
        command(VoiceCommand.OPEN_BLUETOOTH_SETTINGS, "打开蓝牙设置")
        command(VoiceCommand.VOLUME_UP, "音量加", "调大音量")
        command(VoiceCommand.VOLUME_DOWN, "音量减", "调小音量")
        command(VoiceCommand.BATTERY, "电量", "查看电量")
        command(VoiceCommand.TIME, "几点了", "现在几点", "级别了", "几点啊", "现在几点了", "现在几点啊")
        command(VoiceCommand.HELP, "帮助", "有什么命令", "控制词")
    }

    fun resolve(transcript: String): VoiceCommand? {
        val normalized = normalize(transcript)
        aliases[normalized]?.let { return it }
        val withoutPoliteness = normalized
            .removePrefix("麻烦你")
            .removePrefix("请帮我")
            .removePrefix("帮我")
            .removePrefix("请你")
            .removePrefix("请")
            .removeSuffix("可以吗")
            .removeSuffix("一下")
            .removeSuffix("吧")
        return aliases[withoutPoliteness]
    }

    private fun normalize(text: String): String = text
        .lowercase(Locale.ROOT)
        .replace(ignoredCharacters, "")
        .trim()
}
