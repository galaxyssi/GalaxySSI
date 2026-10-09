package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Original workspace revisions for an observer, not reads performed by a model. */
internal object CollaborationPilotHistorySnapshot {
    fun capture(workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess): JSONObject {
        val originals = JSONArray()
        val seen = mutableSetOf<String>()
        var cursor = ""
        do {
            val page = workspace.browse(access, cursor, 100)
            for (head in page.revisions) {
                val id = head.getString("object_id")
                require(seen.add(id)) { "Workspace archive repeated an object" }
                for (revision in 1..head.getInt("revision")) {
                    workspace.read(access, id, revision)?.let { originals.put(it) }
                }
            }
            val next = page.next
            require(next == null || next != cursor) { "Workspace archive cursor did not advance" }
            cursor = next.orEmpty()
        } while (cursor.isNotEmpty())
        return JSONObject().put("format", "galaxyssi.pilot-workspace-history.v1")
            .put("capture_role", "test_observer_not_agent").put("group_id", access.groupId)
            .put("agent_read_proven", false).put("capability_gain_proven", false)
            .put("coverage", "visible_workspace_revisions_not_all_tool_receipts_or_archive_records")
            .put("originals", originals)
    }
}
