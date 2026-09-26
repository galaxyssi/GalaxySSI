package com.galaxyssi.glasses

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class VoiceCommandCatalogTest {
    @Test fun mapsEveryControlGroupToItsAction() {
        val expected = mapOf(
            VoiceCommand.SEND to listOf("发送", "提交", "确认发送"),
            VoiceCommand.CLEAR to listOf("取消", "清空"),
            VoiceCommand.SPEAK_REPLY to listOf("朗读", "读出来"),
            VoiceCommand.STOP_SPEAKING to listOf("停止朗读", "别读了"),
            VoiceCommand.NEW_CHAT to listOf("新对话"),
            VoiceCommand.OPEN_SETTINGS to listOf("设置", "打开设置", "手机配置"),
            VoiceCommand.STOP_CONFIGURATION to listOf("停止配置", "结束配置", "退出配置", "停止配网"),
            VoiceCommand.CONFIRM_PAIRING to listOf("确认配对", "配对确认"),
            VoiceCommand.CANCEL_PAIRING to listOf("取消配对"),
            VoiceCommand.OPEN_CHAT to listOf("返回", "打开对话", "对话", "back"),
            VoiceCommand.OPEN_SESSIONS to listOf("会话", "最近对话"),
            VoiceCommand.OPEN_CAMERA to listOf("打开相机", "启动相机", "打开拍照"),
            VoiceCommand.SCAN_WIFI to listOf("扫描配网", "扫描配网码", "连接 Wi-Fi", "scan Wi-Fi"),
            VoiceCommand.CONFIRM_WIFI to listOf("确认联网", "confirm Wi-Fi"),
            VoiceCommand.CANCEL_WIFI to listOf("取消联网", "cancel Wi-Fi"),
            VoiceCommand.TAKE_PHOTO to listOf("拍照", "拍一张", "照相", "拍张照", "拍张照片", "take photo"),
            VoiceCommand.START_RECORDING to listOf("开始录像", "启动录像", "录像", "录视频", "开始录制", "start recording"),
            VoiceCommand.STOP_RECORDING to listOf("停止录像", "结束录像", "停止录制", "stop recording"),
            VoiceCommand.OPEN_GALLERY to listOf("打开相册", "查看照片"),
            VoiceCommand.HOME to listOf("回到桌面", "返回桌面", "home"),
            VoiceCommand.OPEN_WIFI_SETTINGS to listOf("打开 Wi-Fi 设置", "打开无线设置"),
            VoiceCommand.OPEN_BLUETOOTH_SETTINGS to listOf("打开蓝牙设置"),
            VoiceCommand.VOLUME_UP to listOf("音量加", "调大音量"),
            VoiceCommand.VOLUME_DOWN to listOf("音量减", "调小音量"),
            VoiceCommand.BATTERY to listOf("电量", "查看电量"),
            VoiceCommand.TIME to listOf("几点了", "现在几点", "级别了", "几点啊", "现在几点了", "现在几点啊"),
            VoiceCommand.HELP to listOf("帮助", "有什么命令", "控制词")
        )
        expected.forEach { (command, phrases) ->
            phrases.forEach { phrase -> assertEquals(phrase, command, VoiceCommandCatalog.resolve(phrase)) }
        }
    }

    @Test fun acceptsPunctuationSpacingAndPoliteShortCommands() {
        assertEquals(VoiceCommand.TAKE_PHOTO, VoiceCommandCatalog.resolve("请帮我拍照一下。"))
        assertEquals(VoiceCommand.START_RECORDING, VoiceCommandCatalog.resolve("Start recording!"))
        assertEquals(VoiceCommand.STOP_CONFIGURATION, VoiceCommandCatalog.resolve("请停止配置吧"))
    }

    @Test fun doesNotExecuteUnknownSpeech() {
        assertNull(VoiceCommandCatalog.resolve("今天适合拍照吗"))
    }
}
