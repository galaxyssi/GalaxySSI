package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationCoordinatorJournalTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var fail = false
        override fun read(key: String) = data[key]
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        override fun commit(values: Map<String, String>) { check(!fail) { "disk unavailable" }; data.putAll(values) }
    }
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "planner", "lead")
    private fun item(index: Int) = JSONObject().put("token", index.toString()).put("grants", JSONArray().put("grant-$index"))

    @Test fun replayPagesAreImmutableAndTailCanBePolledAfterReopening() {
        val rows = Rows()
        val journal = CollaborationCoordinatorJournal(rows, access)
        val initial = journal.page("") { emptyList() }
        assertTrue(initial.getBoolean("caught_up_at_read"))
        assertTrue(rows.data.isEmpty())
        val page = journal.page(initial.getString("next_cursor")) { listOf(item(1)) }
        assertFalse(page.getJSONArray("milestones").getJSONObject(0).has("grants"))
        val reopened = CollaborationCoordinatorJournal(rows, access)
        assertEquals(page.toString(), reopened.page("") { error("Retry must not advance") }.toString())
        val tail = reopened.page(page.getString("next_cursor")) { known ->
            assertEquals(setOf("1"), known); emptyList()
        }
        assertEquals(page.getString("next_cursor"), tail.getString("next_cursor"))
        val newer = reopened.page(tail.getString("next_cursor")) { listOf(item(2)) }
        assertEquals("2", newer.getJSONArray("milestones").getJSONObject(0).getString("token"))
        assertEquals(page.toString(), reopened.page("") { error("Stable replay") }.toString())
        assertEquals(2, reopened.offered().size)
    }

    @Test fun foreignAndFutureCursorsCannotReadAnotherDispatch() {
        val rows = Rows(); val journal = CollaborationCoordinatorJournal(rows, access)
        val page = journal.page("") { listOf(item(1)) }
        val cursor = page.getString("next_cursor")
        val scopes = listOf(access.copy(groupId = "other"), access.copy(runId = "other"), access.copy(turnId = "other"),
            access.copy(round = 2), access.copy(nodeId = "other"), access.copy(personId = "other"),
            access.copy(dependencyNodes = setOf("x")), access.copy(pinnedReads = setOf("x")))
        scopes.forEach { other ->
            val changed = CollaborationCoordinatorJournal(rows, other)
            assertTrue(changed.offered().isEmpty())
            assertThrows(IllegalArgumentException::class.java) { changed.page(cursor) { emptyList() } }
        }
        for (suffix in listOf("2", "-1", "01", "+1", "x", "2147483648")) assertThrows(IllegalArgumentException::class.java) {
            journal.page(cursor.substringBefore(':') + ":$suffix") { emptyList() }
        }
    }

    @Test fun failedCommitCannotGrantAReadAndSuccessfulRetryDoesNotDuplicate() {
        val rows = Rows(); val journal = CollaborationCoordinatorJournal(rows, access)
        rows.fail = true
        assertThrows(IllegalStateException::class.java) { journal.page("") { listOf(item(1)) } }
        assertTrue(journal.offered().isEmpty())
        rows.fail = false
        val first = journal.page("") { listOf(item(1)) }
        assertThrows(IllegalArgumentException::class.java) { journal.page(first.getString("next_cursor")) { listOf(item(1)) } }
        assertEquals(1, journal.offered().size)
        assertEquals(first.toString(), journal.page("") { emptyList() }.toString())
    }

    @Test fun paginationDoesNotImposeATotalVersionLimit() {
        val journal = CollaborationCoordinatorJournal(Rows(), access)
        var cursor = ""
        repeat(70) { index ->
            val result = journal.page(cursor) { known ->
                assertEquals(index * 16, known.size)
                (index * 16 until (index + 1) * 16).map(::item)
            }
            cursor = result.getString("next_cursor")
        }
        assertEquals(1120, journal.offered().size)
    }
}
