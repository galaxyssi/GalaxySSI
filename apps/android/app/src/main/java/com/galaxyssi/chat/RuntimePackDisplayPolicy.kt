package com.galaxyssi.chat

internal object RuntimePackDisplayPolicy {
    fun installedTitle(title: String, installedVersion: String?): String {
        val normalizedVersion = installedVersion.orEmpty().trim().removePrefix("v")
        return if (normalizedVersion.isBlank()) title else "$title $normalizedVersion"
    }
}
