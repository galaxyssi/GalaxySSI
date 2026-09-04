package com.galaxyssi.chat.voice.asr.local

import java.io.File

internal object WhisperCpuFeatures {
    fun osExposesSme(cpuInfo: String = readCpuInfo()): Boolean = cpuInfo
        .lineSequence()
        .filter { it.substringBefore(':').trim().equals("Features", ignoreCase = true) }
        .flatMap { it.substringAfter(':', "").trim().split(Regex("\\s+")).asSequence() }
        .any { it.equals("sme", ignoreCase = true) }

    private fun readCpuInfo(): String = runCatching { File("/proc/cpuinfo").readText() }.getOrDefault("")
}
