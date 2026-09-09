package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener
import java.util.Locale

internal object AgentObservationRedaction {
    fun redact(value: String): String {
        if (value.startsWith("{") || value.startsWith("[")) {
            try {
                val tokens = JSONTokener(value)
                val parsed = tokens.nextValue()
                if (tokens.nextClean() == '\u0000') return redactValue(parsed, 0).toString()
            } catch (_: JSONException) {
                // Partial JSON and command logs still need assignment redaction.
            }
        }
        return redactText(value)
    }

    private fun redactValue(value: Any?, depth: Int): Any = when {
        depth > 64 -> "[nested data omitted]"
        value is JSONObject -> value.apply {
            keys().asSequence().toList().forEach { key ->
                val normalized = key.lowercase(Locale.ROOT).replace('-', '_')
                put(key, if (normalized in secretKeys) "[redacted]" else redactValue(opt(key), depth + 1))
            }
        }
        value is JSONArray -> value.apply {
            for (index in 0 until length()) put(index, redactValue(opt(index), depth + 1))
        }
        value is String -> redactText(value)
        else -> value ?: JSONObject.NULL
    }

    private fun redactText(value: String): String = value
        .replace(PEM_KEY, "[redacted private key]")
        .replace(AUTH_CREDENTIAL, "[redacted authorization]")
        .replace(QUOTED_ASSIGNMENT) { match -> "${match.groupValues[1]}[redacted]" }

    private val secretKeys = setOf("api_key", "apikey", "access_token", "auth_token", "refresh_token",
        "session_token", "password", "secret", "client_secret", "authorization", "private_key", "seed_phrase")
    private val AUTH_CREDENTIAL = Regex("(?i)\\b(?:Basic|Bearer)\\s+[A-Za-z0-9._~+/=-]{8,}")
    private val PEM_KEY = Regex("-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----[\\s\\S]*?(?:-----END (?:[A-Z ]+ )?PRIVATE KEY-----|$)")
    private val QUOTED_ASSIGNMENT = Regex(
        "(?i)((?:[\"']?)(?:api[_-]?key|access[_-]?token|auth[_-]?token|refresh[_-]?token|session[_-]?token|password|secret|client[_-]?secret|private[_-]?key|seed[_-]?phrase)(?:[\"']?)\\s*[:=]\\s*)" +
            "(?:\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|[^\\s,;]+)"
    )
}
