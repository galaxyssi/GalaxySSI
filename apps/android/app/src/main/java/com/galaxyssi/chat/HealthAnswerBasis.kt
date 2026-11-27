package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal enum class HealthBasisKind { MEASUREMENT, CONTEXT, PROFILE, GUIDELINE, TARGET, INSTRUCTION, FOLLOW_UP, RETRIEVED }

internal data class HealthBasisSource(val kind: HealthBasisKind, val at: Long, val title: String = "", val metric: HealthMetric? = null) {
    fun json() = JSONObject().put("kind", kind.name).put("at", at).put("title", title)
        .apply { metric?.let { put("metric", it.name) } }

    companion object {
        fun from(v: JSONObject) = HealthBasisSource(HealthBasisKind.valueOf(v.getString("kind")), v.getLong("at"),
            v.optString("title").take(256), v.optString("metric").takeIf(String::isNotBlank)?.let(HealthMetric::valueOf))
    }
}

/** Project only the actual approved snapshot, never the rest of the profile or model-generated citations. */
internal object HealthAnswerBasis {
    fun snapshot(json: String): List<HealthBasisSource> {
        val root = JSONObject(json)
        if (root.has("selected_instruction")) return listOf(HealthBasisSource(HealthBasisKind.INSTRUCTION, 0))
        if (root.has("selected_visit_followup")) return listOf(HealthBasisSource(HealthBasisKind.FOLLOW_UP, 0))
        val rows = linkedMapOf<String, HealthBasisSource>()
        fun measurement(value: JSONObject?, name: String) {
            val record = value?.optJSONObject("record") ?: return
            val id = record.optString("id")
            val metric = runCatching { HealthMetric.valueOf(name) }.getOrNull() ?: return
            if (id.isNotBlank() && record.optInt("revision") > 0 && value.optLong("measured_at") > 0)
                rows["record:$id:${record.optInt("revision")}"] = HealthBasisSource(HealthBasisKind.MEASUREMENT, value.getLong("measured_at"), metric = metric)
        }
        fun each(a: JSONArray?, block: (JSONObject) -> Unit) { if (a != null) for (i in 0 until a.length()) a.optJSONObject(i)?.let(block) }
        val assessment = root.optJSONObject("assessment")
        measurement(assessment, root.optString("metric"))
        each(root.optJSONObject("measurement_history")?.optJSONArray("samples")) { measurement(it, it.optString("metric")) }
        each(root.optJSONObject("related_measurements")?.optJSONArray("selected")) {
            if (it.optBoolean("available")) measurement(it.optJSONObject("sample"), it.optString("metric"))
        }
        root.optJSONObject("clarification_context")?.takeIf { it.optString("context_status") == "CURRENT_RECORD" && it.optLong("confirmed_at") > 0 }?.let {
            rows["context"] = HealthBasisSource(HealthBasisKind.CONTEXT, it.getLong("confirmed_at"))
        }
        root.optJSONObject("selected_profile")?.let { profile ->
            val times = mutableListOf<Long>()
            val fields = profile.optJSONObject("fields")
            fields?.keys()?.forEach { key -> fields.optJSONObject(key)?.takeIf { it.optString("state") == "KNOWN" }?.let { times.add(it.optLong("updated_at")) } }
            each(profile.optJSONArray("entries")) { times.add(it.optLong("updated")) }
            if (times.isNotEmpty()) rows["profile"] = HealthBasisSource(HealthBasisKind.PROFILE, times.max())
        }
        assessment?.optJSONObject("guideline")?.takeIf { it.optString("title").isNotBlank() }?.let {
            rows["guideline"] = HealthBasisSource(HealthBasisKind.GUIDELINE, it.optLong("checked_at"), it.getString("title").take(256))
        }
        root.optJSONObject("individual_target")?.takeIf { it.optLong("confirmed_at") > 0 }?.let {
            rows["target"] = HealthBasisSource(HealthBasisKind.TARGET, it.getLong("confirmed_at"))
        }
        return rows.values.toList()
    }
}
