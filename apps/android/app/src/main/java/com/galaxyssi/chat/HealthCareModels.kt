package com.galaxyssi.chat

import java.math.BigDecimal
import java.net.URI
import org.json.JSONArray
import org.json.JSONObject

internal enum class HealthCareStage { VERIFY_CONTEXT, REVIEW_EVIDENCE, REVIEW_PLAN, WAITING_RESULTS, REASSESS, MAINTENANCE, PAUSED, CLOSED }
internal enum class HealthCareSignal { REPORT_LOW, REPORT_HIGH, GLUCOSE_CONTEXT, GUIDELINE_SCOPE, GUIDELINE_REVIEW, RISING_SERIES, FALLING_SERIES, RESULT_NOT_EXACT, SOURCE_REMOVED }
internal enum class HealthCareTruth { UNKNOWN, YES, NO }
internal enum class HealthCareSpecimen { UNKNOWN, LAB_PLASMA, HOME_CAPILLARY, INTERSTITIAL }
internal enum class HealthCareActionKind { LIFESTYLE, CLINICIAN_DISCUSSION, RECHECK, CONTEXT }
internal enum class HealthCareActionState { PROPOSED, CONFIRMED, DONE, DECLINED }

internal data class HealthCareRecordRef(val id: String, val revision: Int) {
    init { require(HealthProfilePolicy.uuid(id) && revision > 0) }
    fun json() = JSONObject().put("id", id).put("revision", revision)
    companion object { fun from(j: JSONObject) = HealthCareRecordRef(j.getString("id"), j.getInt("revision")) }
}

/** Measurement context belongs to a particular revision, not every future reading of this metric. */
internal data class HealthCareContext(
    val record: HealthCareRecordRef, val adult: HealthCareTruth = HealthCareTruth.UNKNOWN,
    val pregnant: HealthCareTruth = HealthCareTruth.UNKNOWN, val diagnosedDiabetes: HealthCareTruth = HealthCareTruth.UNKNOWN,
    val specimen: HealthCareSpecimen = HealthCareSpecimen.UNKNOWN, val fastingHours: Int? = null,
    val illnessOrMedication: HealthCareTruth = HealthCareTruth.UNKNOWN, val confirmedAt: Long
) {
    init { require(confirmedAt > 0 && (fastingHours == null || fastingHours in 0..72)) }
    val screeningFpgApplicable get() = adult == HealthCareTruth.YES && pregnant == HealthCareTruth.NO &&
        diagnosedDiabetes == HealthCareTruth.NO && specimen == HealthCareSpecimen.LAB_PLASMA &&
        fastingHours != null && fastingHours >= 8
    val excludesScreeningFpg get() = adult == HealthCareTruth.NO || pregnant == HealthCareTruth.YES ||
        diagnosedDiabetes == HealthCareTruth.YES || specimen in setOf(HealthCareSpecimen.HOME_CAPILLARY, HealthCareSpecimen.INTERSTITIAL) ||
        fastingHours != null && fastingHours < 8
    fun json() = JSONObject().put("record", record.json()).put("adult", adult.name).put("pregnant", pregnant.name)
        .put("diabetes", diagnosedDiabetes.name).put("specimen", specimen.name).put("fasting", fastingHours ?: JSONObject.NULL)
        .put("illness_medication", illnessOrMedication.name).put("confirmed_at", confirmedAt)
    companion object {
        fun from(j: JSONObject) = HealthCareContext(HealthCareRecordRef.from(j.getJSONObject("record")),
            HealthCareTruth.valueOf(j.getString("adult")), HealthCareTruth.valueOf(j.getString("pregnant")),
            HealthCareTruth.valueOf(j.getString("diabetes")), HealthCareSpecimen.valueOf(j.getString("specimen")),
            if (j.isNull("fasting")) null else j.getInt("fasting"), HealthCareTruth.valueOf(j.getString("illness_medication")), j.getLong("confirmed_at"))
    }
}

internal data class HealthCareGuideline(val id: String, val title: String, val url: String, val version: String,
    val applicability: String, val statement: String, val checkedAt: Long) {
    init {
        require(id.isNotBlank() && id.length <= 120 && title.isNotBlank() && title.length <= 300)
        val uri = URI(url)
        require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null && url.length <= 2048)
        require(version.isNotBlank() && version.length <= 80 && applicability.isNotBlank() && applicability.length <= 2000)
        require(statement.isNotBlank() && statement.length <= 4000 && checkedAt > 0)
    }
    fun json() = JSONObject().put("id", id).put("title", title).put("url", url).put("version", version)
        .put("applicability", applicability).put("statement", statement).put("checked_at", checkedAt)
    companion object { fun from(j: JSONObject) = HealthCareGuideline(j.getString("id"), j.getString("title"), j.getString("url"),
        j.getString("version"), j.getString("applicability"), j.getString("statement"), j.getLong("checked_at")) }
}

internal data class HealthCareBaseline(val refs: List<HealthCareRecordRef>, val unit: String, val low: String,
    val high: String, val from: Long, val until: Long) {
    init {
        require(refs.size in 2..30 && refs.distinct().size == refs.size && from > 0 && until > from)
        require(low.length in 1..128 && high.length in 1..128)
        require(BigDecimal(low) <= BigDecimal(high) && unit.length <= 32)
    }
    fun json() = JSONObject().put("records", JSONArray(refs.map { it.json() })).put("unit", unit).put("low", low)
        .put("high", high).put("from", from).put("until", until)
    companion object { fun from(j: JSONObject) = HealthCareBaseline(j.getJSONArray("records").let { a ->
        (0 until a.length()).map { HealthCareRecordRef.from(a.getJSONObject(it)) } }, j.getString("unit"),
        j.getString("low"), j.getString("high"), j.getLong("from"), j.getLong("until")) }
}

internal data class HealthCareTarget(val field: String, val low: String?, val high: String?, val unit: String,
    val rationale: String, val source: String, val confirmedBy: String, val confirmedAt: Long) {
    init {
        require(field.isNotBlank() && field.length <= 80 && unit.length <= 32 && (low != null || high != null))
        require((low == null || low.length in 1..128) && (high == null || high.length in 1..128))
        val lower = low?.let(::BigDecimal); val upper = high?.let(::BigDecimal)
        require(lower == null || upper == null || lower <= upper)
        require(rationale.isNotBlank() && rationale.length <= 2000 && source.isNotBlank() && source.length <= 2048)
        require(confirmedBy.isNotBlank() && confirmedBy.length <= 200 && confirmedAt > 0)
    }
    fun json() = JSONObject().put("field", field).put("low", low ?: JSONObject.NULL).put("high", high ?: JSONObject.NULL)
        .put("unit", unit).put("rationale", rationale).put("source", source).put("confirmed_by", confirmedBy).put("confirmed_at", confirmedAt)
    companion object { fun from(j: JSONObject) = HealthCareTarget(j.getString("field"), if (j.isNull("low")) null else j.getString("low"),
        if (j.isNull("high")) null else j.getString("high"), j.getString("unit"), j.getString("rationale"), j.getString("source"),
        j.getString("confirmed_by"), j.getLong("confirmed_at")) }
}

/** These are different evidence bases. Neither a reference interval nor a historical baseline is a target. */
internal data class HealthCareAssessment(val record: HealthCareRecordRef?, val measuredAt: Long, val value: String,
    val unit: String, val reportReference: String, val signals: Set<HealthCareSignal>,
    val guideline: HealthCareGuideline? = null, val baseline: HealthCareBaseline? = null) {
    init {
        require(measuredAt >= 0 && value.length <= 1000 && unit.length <= 32 && reportReference.length <= 200)
        require(record != null || signals == setOf(HealthCareSignal.SOURCE_REMOVED))
        require(guideline != null || HealthCareSignal.GUIDELINE_REVIEW !in signals)
    }
    fun json() = JSONObject().put("record", record?.json() ?: JSONObject.NULL).put("measured_at", measuredAt)
        .put("value", value).put("unit", unit).put("reference", reportReference).put("signals", JSONArray(signals.map { it.name }))
        .put("guideline", guideline?.json() ?: JSONObject.NULL).put("baseline", baseline?.json() ?: JSONObject.NULL)
    companion object { fun from(j: JSONObject) = HealthCareAssessment(if (j.isNull("record")) null else HealthCareRecordRef.from(j.getJSONObject("record")),
        j.getLong("measured_at"), j.getString("value"), j.getString("unit"), j.getString("reference"),
        j.getJSONArray("signals").let { a -> (0 until a.length()).map { HealthCareSignal.valueOf(a.getString(it)) }.toSet() },
        if (j.isNull("guideline")) null else HealthCareGuideline.from(j.getJSONObject("guideline")),
        if (j.isNull("baseline")) null else HealthCareBaseline.from(j.getJSONObject("baseline"))) }
}

internal data class HealthCareAction(val id: String, val kind: HealthCareActionKind, val description: String,
    val rationale: String, val source: String, val state: HealthCareActionState = HealthCareActionState.PROPOSED,
    val dueFrom: Long? = null, val dueUntil: Long? = null, val confirmedAt: Long? = null, val outcome: String = "", val basis: String = "") {
    init {
        require(HealthProfilePolicy.uuid(id) && description.isNotBlank() && description.length <= 1000)
        require(rationale.isNotBlank() && rationale.length <= 2000 && source.isNotBlank() && source.length <= 2048)
        require((dueFrom == null) == (dueUntil == null) && (dueFrom == null || dueFrom > 0 && dueUntil!! >= dueFrom))
        require(state !in setOf(HealthCareActionState.CONFIRMED, HealthCareActionState.DONE) || confirmedAt != null && confirmedAt > 0)
        require(outcome.length <= 2000 && (state != HealthCareActionState.DONE || outcome.isNotBlank()))
        require(basis.isEmpty() || basis.matches(Regex("[0-9a-f]{64}")))
    }
    fun json() = JSONObject().put("id", id).put("kind", kind.name).put("description", description).put("rationale", rationale)
        .put("source", source).put("state", state.name).put("from", dueFrom ?: JSONObject.NULL).put("until", dueUntil ?: JSONObject.NULL)
        .put("confirmed_at", confirmedAt ?: JSONObject.NULL).put("outcome", outcome).put("basis", basis)
    companion object { fun from(j: JSONObject) = HealthCareAction(j.getString("id"), HealthCareActionKind.valueOf(j.getString("kind")),
        j.getString("description"), j.getString("rationale"), j.getString("source"), HealthCareActionState.valueOf(j.getString("state")),
        if (j.isNull("from")) null else j.getLong("from"), if (j.isNull("until")) null else j.getLong("until"),
        if (j.isNull("confirmed_at")) null else j.getLong("confirmed_at"), j.getString("outcome"), j.optString("basis", "")) }
}

internal data class HealthCareConcern(val id: String, val metric: HealthMetric, val revision: Int, val createdAt: Long,
    val updatedAt: Long, val inputVersion: String, val assessment: HealthCareAssessment,
    val stage: HealthCareStage = HealthCareStage.VERIFY_CONTEXT, val context: HealthCareContext? = null,
    val target: HealthCareTarget? = null, val actions: List<HealthCareAction> = emptyList(),
    val reviewNote: String = "", val reviewedBy: String = "", val conversationId: String = "", val profileId: String = "self") {
    init {
        require(HealthProfilePolicy.uuid(id) && revision > 0 && createdAt > 0 && updatedAt >= createdAt && profileId == "self")
        require(inputVersion.length <= 256 && actions.size <= 30 && actions.map { it.id }.distinct().size == actions.size)
        require(reviewNote.length <= 4000 && reviewedBy.length <= 200 && conversationId.length <= 256)
        require(target == null || target.field in metric.fields && target.unit in metric.units)
        require(stage !in setOf(HealthCareStage.MAINTENANCE, HealthCareStage.CLOSED) || reviewNote.isNotBlank() && reviewedBy.isNotBlank())
    }
    val open get() = stage != HealthCareStage.CLOSED
    val nextDue get() = if (stage in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED)) null else actions
        .filter { it.state == HealthCareActionState.CONFIRMED }.mapNotNull { it.dueFrom }.minOrNull()
    fun json() = JSONObject().put("schema", 1).put("id", id).put("metric", metric.name).put("revision", revision)
        .put("created_at", createdAt).put("updated_at", updatedAt).put("input_version", inputVersion).put("assessment", assessment.json())
        .put("stage", stage.name).put("context", context?.json() ?: JSONObject.NULL).put("target", target?.json() ?: JSONObject.NULL)
        .put("actions", JSONArray(actions.map { it.json() })).put("review_note", reviewNote).put("reviewed_by", reviewedBy)
        .put("conversation", conversationId).put("profile", profileId)
    companion object {
        fun from(j: JSONObject): HealthCareConcern {
            require(j.getInt("schema") == 1)
            return HealthCareConcern(j.getString("id"), HealthMetric.valueOf(j.getString("metric")), j.getInt("revision"),
                j.getLong("created_at"), j.getLong("updated_at"), j.getString("input_version"), HealthCareAssessment.from(j.getJSONObject("assessment")),
                HealthCareStage.valueOf(j.getString("stage")), if (j.isNull("context")) null else HealthCareContext.from(j.getJSONObject("context")),
                if (j.isNull("target")) null else HealthCareTarget.from(j.getJSONObject("target")),
                j.getJSONArray("actions").let { a -> (0 until a.length()).map { HealthCareAction.from(a.getJSONObject(it)) } },
                j.getString("review_note"), j.getString("reviewed_by"), j.getString("conversation"), j.getString("profile"))
        }
    }
}

internal data class HealthCareSettings(val enabled: Boolean = false, val version: String = "")
internal data class HealthCareCursor(val updatedAt: Long, val id: String)
internal data class HealthCarePage(val items: List<HealthCareConcern>, val next: HealthCareCursor?)
internal class HealthCareConflict : IllegalStateException("Health care state changed; reload before applying this change")
