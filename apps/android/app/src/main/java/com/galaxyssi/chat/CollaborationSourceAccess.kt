package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Availability of direct immutable references, never a transitive grant or a read receipt. */
internal object CollaborationSourceAccess {
    const val MODE = "source_access"
    const val INSTRUCTIONS = "Use mode=source_access with exact workspace object_id/revision/sha256 and optional cursor " +
        "to inspect its direct parent and tool-evidence availability. Follow next_cursor with the same root. " +
        "Available means readable now, not read or verified. Read relevant originals; for unavailable sources, " +
        "coordinate explicit input changes or report the evidence gap rather than repeating the unchanged request. " +
        "This does not grant access or choose which evidence is sufficient."
    private const val PAGE_SIZE = 20
    private val fields = setOf("mode", "object_id", "revision", "sha256", "cursor")
    private val hash = Regex("[a-f0-9]{64}")

    fun read(input: Map<String, Any?>, access: CollaborationWorkspaceAccess,
             workspace: (String, Int) -> JSONObject?, evidence: (JSONObject) -> JSONObject?): JSONObject {
        require(input["mode"] == MODE && input.keys.all { it in fields }) {
            "Source access accepts exact workspace object_id/revision/sha256 and optional cursor only"
        }
        val id = input["object_id"] as? String
        val digest = input["sha256"] as? String
        val revision = input["revision"]
        require(id != null && hash.matches(id) && digest != null && hash.matches(digest) &&
            revision is Number && revision.toInt() > 0 && revision.toDouble() == revision.toInt().toDouble()) {
            "Source access requires a 64-character object ID and sha256, and a positive integer revision"
        }
        val root = requireNotNull(workspace(id, revision.toInt())) { "Source owner is missing, changed or isolated" }
        val reference = JSONObject().put("object_id", id).put("revision", revision.toInt()).put("sha256", digest)
        require(access.canRead(root) && matches(root, reference, "workspace")) { "Source owner is missing, changed or isolated" }
        val parents = root.getJSONArray("parents")
        val observations = root.getJSONArray("host_observations")
        val total = parents.length() + observations.length()
        val scope = AgentNativeJsonCodec.sha256(listOf(MODE, access.groupId, access.runId, access.turnId, access.round,
            access.nodeId, access.personId, access.dependencyNodes.sorted(), access.pinnedReads.sorted(), id, revision.toInt(), digest))
        val cursor = if (input.containsKey("cursor")) input["cursor"] else ""
        require(cursor is String && cursor.length <= 512) { "Invalid source access cursor" }
        val offset = if (cursor.isEmpty()) 0 else {
            val parts = cursor.split(':')
            val position = parts.getOrNull(1)?.toIntOrNull()
            require(parts.size == 2 && parts[0] == scope && position != null && position > 0 && position < total) {
                "Source access cursor is invalid or belongs to another root or assignment; restart without cursor"
            }
            position
        }
        val end = minOf(total, offset + PAGE_SIZE)
        val result = JSONArray()
        for (index in offset until end) {
            val isParent = index < parents.length()
            val kind = if (isParent) "workspace" else "evidence"
            val field = if (isParent) "parents" else "host_observations"
            val sourceIndex = if (isParent) index else index - parents.length()
            val original = (if (isParent) parents else observations).getJSONObject(sourceIndex)
            val ref = exactReference(original, kind)
            val saved = if (isParent) workspace(ref.getString("object_id"), ref.getInt("revision")) else evidence(ref)
            val available = saved != null && access.canRead(saved) && matches(saved, ref, kind)
            result.put(JSONObject().put("kind", kind).put("source_field", field).put("source_index", sourceIndex)
                .put("reference", ref).put("status", if (available) "available" else "missing_changed_or_out_of_scope")
                .apply { if (available) put("read_original", JSONObject(ref.toString()).put("mode", kind).put("offset", 0)) })
        }
        return JSONObject().put("source_reference", reference).put("references", result).put("total_references", total)
            .put("next_cursor", if (end < total) "$scope:$end" else JSONObject.NULL)
            .put("availability_snapshot", false).put("scope", "direct_declared_references_only")
            .put("trust", "current_access_not_read_coverage_or_verification").put("guidance", INSTRUCTIONS)
    }

    private fun exactReference(saved: JSONObject, kind: String): JSONObject {
        val id = if (kind == "workspace") "object_id" else "evidence_id"
        require(saved.opt(id) is String && hash.matches(saved.getString(id)) &&
            saved.opt("sha256") is String && hash.matches(saved.getString("sha256"))) { "Invalid saved source reference" }
        return JSONObject().put(id, saved.getString(id)).put("sha256", saved.getString("sha256")).apply {
            if (kind == "workspace") {
                val revision = saved.opt("revision")
                require(revision is Number && revision.toInt() > 0 && revision.toDouble() == revision.toInt().toDouble()) {
                    "Invalid saved source revision"
                }
                put("revision", revision.toInt())
            }
        }
    }

    private fun matches(saved: JSONObject, ref: JSONObject, kind: String): Boolean {
        val id = if (kind == "workspace") "object_id" else "evidence_id"
        return saved.opt(id) == ref.opt(id) && saved.opt("sha256") == ref.opt("sha256") &&
            (kind != "workspace" || saved.opt("revision") == ref.opt("revision"))
    }
}
