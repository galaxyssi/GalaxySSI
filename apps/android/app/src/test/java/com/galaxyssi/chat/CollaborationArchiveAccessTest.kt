package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationArchiveAccessTest {
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 3, "reviewer", "person", setOf("author"))
    private fun record() = JSONObject().put("group_id", "group").put("run_id", "run")
        .put("turn_id", "turn").put("goal_round", 3).put("node_id", "author")

    @Test fun originalHandoffsAreReadableOnlyByBoundDependencyOrAuthor() {
        assertTrue(CollaborationResearchArchive.visibleToAssignment(record(), access))
        assertTrue(CollaborationResearchArchive.visibleToAssignment(record().put("node_id", "reviewer"), access))
        assertFalse(CollaborationResearchArchive.visibleToAssignment(record().put("node_id", "independent"), access))
        assertFalse(CollaborationResearchArchive.visibleToAssignment(record().put("group_id", "other"), access))
        assertFalse(CollaborationResearchArchive.visibleToAssignment(record().put("run_id", "other"), access))
        assertFalse(CollaborationResearchArchive.visibleToAssignment(record().put("goal_round", 4), access))
        assertFalse(CollaborationResearchArchive.visibleToAssignment(record(), access.copy(personId = "")))
        assertTrue(CollaborationResearchArchive.visibleToAssignment(record().put("goal_round", 2), access))
    }
}
