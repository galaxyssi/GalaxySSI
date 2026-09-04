package com.galaxyssi.chat

import java.net.URI
import java.util.Locale

/** Normalizes model-provided download arguments before they reach Android services. */
internal object AgentPublicDownloadPolicy {
    private val HTTPS_URL = Regex(
        pattern = "https://[A-Za-z0-9._~:/?#\\[\\]@!$&'()*+,;=%-]+",
        option = RegexOption.IGNORE_CASE
    )
    private val TRAILING_PROSE_PUNCTUATION = setOf('.', ',', ';', ':', '!', '?', ')', ']', '}')

    fun normalizeHttpsUrl(value: String): String? {
        var candidate = HTTPS_URL.find(value.trim())?.value.orEmpty()
        while (candidate.lastOrNull() in TRAILING_PROSE_PUNCTUATION) candidate = candidate.dropLast(1)
        if (candidate.isBlank()) return null
        val parsed = runCatching { URI(candidate) }.getOrNull() ?: return null
        return candidate.takeIf {
            parsed.scheme?.lowercase(Locale.US) == "https" &&
                !parsed.host.isNullOrBlank() &&
                parsed.userInfo.isNullOrBlank()
        }
    }
}
