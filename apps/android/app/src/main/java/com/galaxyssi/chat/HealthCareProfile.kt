package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.Period
import java.time.ZoneOffset

/** A durable field/record selection, not permission to read the complete profile. */
internal data class HealthCareProfileScope(val generation: String, val fields: Set<HealthProfileField>,
    val entries: Set<String>) {
    init {
        require(generation.isEmpty() || HealthProfilePolicy.uuid(generation))
        require(fields.all { it != HealthProfileField.NAME })
        require(fields.isNotEmpty() || entries.isNotEmpty())
        require(entries.size <= 30 && entries.all(HealthProfilePolicy::uuid))
    }
    val keys get() = fields.map { "field:${it.name}" }.toSet() + entries.map { "entry:$it" }
    fun json() = JSONObject().put("generation", generation)
        .put("fields", JSONArray(fields.map { it.name }.sorted())).put("entries", JSONArray(entries.sorted()))
    companion object {
        fun from(j: JSONObject) = HealthCareProfileScope(j.getString("generation"),
            j.getJSONArray("fields").let { a -> (0 until a.length()).map { HealthProfileField.valueOf(a.getString(it)) }.toSet() },
            j.getJSONArray("entries").let { a -> (0 until a.length()).map { a.getString(it) }.toSet() })
    }
}

/** Only dependency tokens are copied into the concern; values remain in the profile database. */
internal data class HealthCareProfileLink(val scope: HealthCareProfileScope, val stamp: HealthProfileStamp) {
    init { require(scope.generation == stamp.generation && scope.keys == stamp.versions.keys) }
    fun json() = JSONObject().put("scope", scope.json()).put("stamp", stamp.json())
    companion object { fun from(j: JSONObject) = HealthCareProfileLink(HealthCareProfileScope.from(j.getJSONObject("scope")),
        HealthProfileStamp.from(j.getJSONObject("stamp"))) }
}

internal object HealthCareProfilePolicy {
    fun snapshot(link: HealthCareProfileLink, context: HealthProfileContext, measuredAt: Long): JSONObject {
        require(context.stamp == link.stamp && context.fields.keys == link.scope.fields &&
            context.entries.all { it.id in link.scope.entries })
        val at = Instant.ofEpochMilli(measuredAt).atZone(ZoneOffset.UTC).toLocalDate()
        val fields = JSONObject()
        context.fields.toSortedMap(compareBy { it.name }).forEach { (field, value) ->
            val item = JSONObject().put("state", if (value == null) "UNKNOWN" else "KNOWN")
                .put("updated_at", context.fieldUpdatedAt[field] ?: JSONObject.NULL)
            if (field == HealthProfileField.BIRTH_DATE) {
                val birth = value?.text?.let(LocalDate::parse)
                item.put("age_on_measurement_date", if (birth != null && !birth.isAfter(at))
                    Period.between(birth, at).years else JSONObject.NULL).put("as_of_utc_date", at.toString())
                fields.put("AGE_AT_MEASUREMENT", item)
            } else fields.put(field.name, item.put("value", value?.json() ?: JSONObject.NULL))
        }
        return JSONObject().put("source", "saved_self_reported_profile").put("scope", "explicitly_selected_fields_and_entries")
            .put("fields", fields).put("entries", JSONArray(context.entries.map { it.json() }))
            .put("unavailable_selected_entries", JSONArray((link.scope.entries - context.entries.map { it.id }.toSet()).sorted()))
            .put("complete_medical_history", false).put("unselected_means_absent", false)
            .put("drafts_included", false).put("current_symptoms_assessed", false)
    }

    fun refreshed(issue: HealthCareConcern, stamp: HealthProfileStamp): HealthCareConcern {
        val link = requireNotNull(issue.profileLink)
        val next = HealthCareProfileLink(link.scope, stamp)
        if (next == link) return issue
        return issue.copy(profileLink = next, stage = if (issue.stage in setOf(HealthCareStage.CLOSED, HealthCareStage.PAUSED))
            issue.stage else HealthCareStage.REASSESS)
    }
}
