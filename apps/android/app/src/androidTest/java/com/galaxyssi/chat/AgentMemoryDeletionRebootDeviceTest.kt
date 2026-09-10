package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentMemoryDeletionRebootDeviceTest {
    private fun arguments(): Pair<String, String> {
        val args = InstrumentationRegistry.getArguments()
        val case = args.getString("memory_reboot_case").orEmpty()
        val bootId = args.getString("memory_boot_id").orEmpty()
        assumeTrue("An explicit persistent fixture and observed boot ID are required", case.isNotBlank() && bootId.isNotBlank())
        require(case.matches(Regex("[A-Za-z0-9_-]{1,80}")))
        require(bootId.matches(Regex("[a-f0-9-]{36}")))
        return case to bootId
    }

    private fun originals() = (0 until 2_501).map { index ->
        deletionMemory(index, if (index < 1_501) "\u5220\u9664\u76ee\u6807-$index" else "\u4fdd\u7559-$index")
    }

    @Test fun preparePersistentDeletionFixture() {
        val (case, bootId) = arguments()
        val fixture = MemoryDeletionDeviceFixture(case)
        check(!fixture.store.database.contains(AgentMemoryStorage.ITEMS) &&
            !fixture.store.database.contains(AgentPersonalMemoryRows.META)) { "Do not overwrite an existing reboot fixture" }
        fixture.store.saveItems(originals())
        assertEquals(1_501, fixture.store.delete("\u5220\u9664\u76ee\u6807"))
        val extra = JSONArray().apply {
            (10_000 until 12_105).forEach { index ->
                put(AgentMemoryCausalDeletionPolicy.encode(
                    AgentMemoryCausalDeletionPolicy.tombstone(listOf(deletionMemory(index)), 2)!!))
            }
        }
        fixture.ledger.mergeBackup(extra)
        assertEquals(2_106, fixture.ledger.snapshot().size)
        assertEquals(1_000, fixture.store.count())
        fixture.store.database.writeString(META, JSONObject().put("case", case).put("boot_id", bootId).toString())
    }

    @Test fun verifyPersistentDeletionAfterDeviceReboot() {
        val (case, bootId) = arguments()
        val fixture = MemoryDeletionDeviceFixture(case)
        val metadata = JSONObject(fixture.store.database.readString(META, ""))
        assertEquals(case, metadata.getString("case"))
        assertNotEquals("A real device reboot is required", metadata.getString("boot_id"), bootId)
        assertEquals(originals().drop(1_501).toSet(), fixture.store.snapshot().activeItems.toSet())
        assertEquals(2_106, fixture.ledger.snapshot().size)
        val input = JSONArray().apply {
            (originals() + deletionMemory(10_000)).forEach { put(fixture.store.encodeMemoryItem(it)) }
        }
        val filtered = fixture.ledger.filterBackupItems(input)
        assertEquals(1_000, filtered.length())
        assertEquals(originals().drop(1_501).map { it.id }.toSet(),
            (0 until filtered.length()).map { filtered.getJSONObject(it).getString("id") }.toSet())
        fixture.ledger.restoreState(input, null)
        assertEquals(originals().drop(1_501).toSet(), fixture.reopen().snapshot().activeItems.toSet())
    }

    companion object { private const val META = "test:memory-deletion:reboot" }
}
