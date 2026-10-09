package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Exact, scoped record facts; no automatic relabeling, retry strategy or permission change. */
internal object CollaborationRecordValidation {
    const val DETAIL = "record_validation"

    private fun check(ok: Boolean, code: String, path: String, expected: Any, actual: Any?, ref: JSONObject? = null) {
        if (ok) return
        val problem = CollaborationToolFeedback.problem(code, path, expected, actual)
            .put("component", "WorkspaceRecordValidator")
        ref?.let { problem.put("reference", JSONObject().apply {
            listOf("object_id", "revision", "sha256").forEach { key ->
                val value = it.opt(key)
                put(key, if (value is String) value.take(64) else if (value is Number) value else JSONObject.NULL)
            }
        }) }
        throw CollaborationToolFeedback.Invalid(problem, "$code at $path: expected $expected; actual ${actual ?: "unavailable"}")
    }

    fun body(kind: String, body: JSONObject): JSONObject {
        val value = body.optJSONObject(kind)
        check(value != null, "typed_body_required", "/body/$kind", "object matching workspace.kind=$kind",
            when { !body.has(kind) -> "absent"; body.isNull(kind) -> "null"; else -> "not an object" })
        return value!!
    }

    fun exact(ref: JSONObject, kinds: Set<String>, read: (String, Int) -> JSONObject?,
              current: ((String, Int) -> Boolean)? = null): JSONObject {
        val revision = ref.opt("revision")
        check(revision is Int && revision > 0, "record_revision_invalid", "/reference/revision", "positive integer",
            if (revision is Number) revision else "missing or not an integer", ref)
        val id = ref.optString("object_id")
        val record = read(id, revision as Int)
        check(record != null, "record_unavailable", "/reference", "accessible saved record",
            "missing or isolated", ref)
        record!!
        check(record.optString("object_id") == id && record.optInt("revision") == revision,
            "record_identity_mismatch", "/reference", "exact requested identity", "different identity", ref)
        check(record.optString("sha256") == ref.optString("sha256") && ref.optString("sha256").isNotBlank(),
            "record_digest_mismatch", "/reference/sha256", record.getString("sha256"), ref.optString("sha256").take(64), ref)
        check(record.getString("kind") in kinds, "record_kind_mismatch", "/reference/kind",
            JSONArray(kinds.sorted()), record.getString("kind"), ref)
        check(current == null || current(id, revision), "record_not_current", "/reference/revision",
            "current version not being changed", revision, ref)
        return record
    }

    fun notice(record: JSONObject): JSONObject? {
        val body = record.getJSONObject("body")
        val fields = CollaborationExecutableTool.KINDS.filter { it != record.getString("kind") && body.has(it) }.sorted()
        if (fields.isEmpty()) return null
        return JSONObject().put("code", "typed_payload_not_registered").put("payload_fields", JSONArray(fields))
            .put("actual_kind", record.getString("kind")).put("executable_registration", false)
            .put("guidance", "Saved as this record kind only. A typed body does not register that capability. " +
                "Read collaboration_recall mode=evolution_rules topic=tools and publish a new matching kind/body record if intended; preserve this original.")
    }
}
