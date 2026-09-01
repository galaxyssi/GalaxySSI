package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale

/** Tracks semantic tool progress without imposing a fixed round or call count. */
internal class CloudWebToolLoopProgress {
    private val outputsByCall = linkedMapOf<String, String>()
    private val requestedRepairs = linkedSetOf<String>()

    var finalizationRequested: Boolean = false
        private set

    fun cached(toolName: String, arguments: JSONObject): String? =
        outputsByCall[semanticKey(toolName, arguments)]

    fun record(toolName: String, arguments: JSONObject, output: String): Boolean {
        val key = semanticKey(toolName, arguments)
        if (outputsByCall.containsKey(key)) return false
        outputsByCall[key] = output
        return true
    }

    fun requestRepair(kind: String): Boolean = requestedRepairs.add(kind)

    fun requestFinalization(): Boolean {
        if (finalizationRequested) return false
        finalizationRequested = true
        return true
    }

    internal fun semanticKey(toolName: String, arguments: JSONObject): String {
        val material = toolName.trim().lowercase(Locale.ROOT) + "\u0000" + canonicalJson(arguments)
        return MessageDigest.getInstance("SHA-256")
            .digest(material.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun canonicalJson(value: Any?): String = when (value) {
        null, JSONObject.NULL -> "null"
        is JSONObject -> value.keys().asSequence().toList().sorted().joinToString(",", "{", "}") { key ->
            JSONObject.quote(key) + ":" + canonicalJson(value.opt(key))
        }
        is JSONArray -> (0 until value.length()).joinToString(",", "[", "]") { index ->
            canonicalJson(value.opt(index))
        }
        is Number, is Boolean -> value.toString()
        else -> JSONObject.quote(value.toString())
    }
}
