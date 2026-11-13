package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Explicitly selected self-profile measurements, never another conversation's transcript or care plan. */
internal object HealthCareRelatedContext {
    fun basis(value: HealthCareRelatedMeasurement?): String = AgentNativeJsonCodec.sha256(JSONObject()
        .put("input_version", value?.inputVersion ?: JSONObject.NULL)
        .put("available", value?.available == true).put("context", value?.context?.json() ?: JSONObject.NULL).toString())

    fun capture(care: HealthCareStore, metrics: Set<HealthMetric>): Map<HealthMetric, String> =
        metrics.sortedBy { it.name }.associateWith { basis(care.relatedMeasurement(it)) }

    fun current(care: HealthCareStore, grant: HealthCareDiscussionGrant) =
        care.concern(grant.concernId)?.metric !in grant.related.keys && capture(care, grant.related.keys) == grant.related

    fun sourceCurrent(context: Context, names: HealthOverviewDatabases, grant: HealthCareDiscussionGrant): Boolean {
        if (grant.related.isEmpty()) return true
        return HealthCareStore(context, names.care).use careScope@{ care ->
            if (!current(care, grant) || care.settings().version != grant.settingsVersion) return@careScope false
            HealthPrivacyStore(context, names.privacy).use privacyScope@{ privacy ->
                val permission = privacy.policy()
                if (!permission.metrics || !permission.profile || permission.version != grant.privacyVersion) return@privacyScope false
                HealthRecordStore(context, names.records).use { records ->
                    grant.related.keys.all { metric ->
                        val issue = care.relatedMeasurement(metric)
                        val clock = records.metricVersion(metric)
                        if (issue == null) clock.isBlank() else
                            issue.inputVersion == HealthCareEngine.inputVersion(grant.settingsVersion, grant.privacyVersion, clock)
                    }
                }
            }
        }
    }

    fun snapshot(care: HealthCareStore, selected: Map<HealthMetric, String>): JSONObject {
        if (capture(care, selected.keys) != selected) throw HealthCareConflict()
        return JSONObject().put("selected", JSONArray(selected.keys.sortedBy { it.name }.map { metric ->
            val issue = care.relatedMeasurement(metric)
            val usable = issue?.available == true
            JSONObject().put("metric", metric.name).put("basis", selected.getValue(metric)).put("available", usable)
                .put("input_version", if (usable) issue!!.inputVersion else JSONObject.NULL)
                .put("sample", if (usable) issue!!.assessment!!.sample!!.modelJson() else JSONObject.NULL)
                .put("confirmed_context", if (usable) issue!!.context?.takeIf { it.record == issue.assessment?.record }?.json() ?: JSONObject.NULL else JSONObject.NULL)
        })).put("history_tool", HealthCareHistoryTool.ID).put("complete_health_archive", false)
            .put("scope", "Only explicitly selected self-profile measurements and their measurement context. No other conversation, question ledger, profile entries or care actions are included.")
    }

    fun options(care: HealthCareStore, primary: HealthMetric): List<HealthCareRelatedOption> = HealthMetric.entries
        .filter { it != primary && care.relatedMeasurement(it)?.available == true }.map { metric ->
            val selected = capture(care, setOf(metric))
            HealthCareRelatedOption(metric, selected.getValue(metric), snapshot(care, selected).getJSONArray("selected").getJSONObject(0).toString())
        }
}

internal data class HealthCareRelatedOption(val metric: HealthMetric, val basis: String, val snapshot: String)

internal data class HealthCareRelatedMeasurement(val metric: HealthMetric, val inputVersion: String,
    val assessment: HealthCareAssessment?, val context: HealthCareContext?, val available: Boolean) {
    companion object {
        fun of(issue: HealthCareConcern) = HealthCareRelatedMeasurement(issue.metric, issue.inputVersion, issue.assessment,
            issue.context, HealthCareResearchPolicy.eligible(issue) && issue.assessment.sample != null)
    }
}
