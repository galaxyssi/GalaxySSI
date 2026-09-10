package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentMemoryRetractionRebootDeviceTest {
    private fun arguments(): Pair<String, String> {
        val args = InstrumentationRegistry.getArguments()
        val case = args.getString("retraction_reboot_case").orEmpty()
        val boot = args.getString("retraction_boot_id").orEmpty()
        assumeTrue("Explicit persistent fixture and observed boot ID are required", case.isNotEmpty() && boot.isNotEmpty())
        require(case.matches(Regex("[A-Za-z0-9_-]{1,80}")))
        require(boot.matches(Regex("[a-f0-9-]{36}")))
        return case to boot
    }

    @Test fun preparePendingRetractionsBeforeReboot() {
        val (case, boot) = arguments()
        val f = MemoryDeletionDeviceFixture(case)
        check(!f.store.database.contains(AgentMemoryStorage.ITEMS) &&
            !f.store.database.contains(AgentPersonalMemoryRows.META)) { "Do not overwrite the original fixture" }
        val items = (0 until 200).map { deletionMemory(it, "\u64a4\u56de\u6d4b\u8bd5-$it") }
        f.store.saveItems(items)
        assertEquals(200, f.store.delete("\u64a4\u56de\u6d4b\u8bd5"))
        val pending = f.ledger.pendingRetractions(250)
        assertTrue(pending.size > 1)
        // Simulate the application-level gap after a persisted idempotent effect;
        // the harness subsequently performs a real physical reboot.
        assertNotNull(runCatching {
            f.ledger.commitRetractionProjection(setOf(pending.first().id)) {
                f.store.database.writeString(EFFECT_PREFIX + pending.first().id, "1")
                error("stop before acknowledgment")
            }
        }.exceptionOrNull())
        f.store.database.writeString(META, JSONObject().put("case", case).put("boot_id", boot)
            .put("pending", pending.size).put("first_event", pending.first().id).toString())
    }

    @Test fun recoverOriginalPendingRetractionsAfterReboot() {
        val (case, boot) = arguments()
        val f = MemoryDeletionDeviceFixture(case)
        val metadata = JSONObject(f.store.database.readString(META, ""))
        assertEquals(case, metadata.getString("case"))
        assertNotEquals("A real device reboot is required", metadata.getString("boot_id"), boot)
        val expected = AgentMemoryCausalDeletionPolicy.retractionEvents(f.ledger.snapshot().single()).map { it.id }.toSet()
        assertEquals(metadata.getInt("pending"), expected.size)
        assertEquals(expected, f.ledger.pendingRetractions(250).map { it.id }.toSet())
        assertEquals("1", f.store.database.readString(EFFECT_PREFIX + metadata.getString("first_event"), ""))
        f.ledger.commitRetractionProjection(expected) {
            expected.forEach { id ->
                if (!f.store.database.contains(EFFECT_PREFIX + id)) f.store.database.writeString(EFFECT_PREFIX + id, "1")
            }
        }
        assertTrue(f.reopen().deletionIndex.pendingRetractions().isEmpty())
        assertEquals(0, f.reopen().count())
        assertEquals(1, f.ledger.snapshot().size)
        expected.forEach { assertEquals("1", f.store.database.readString(EFFECT_PREFIX + it, "")) }
    }

    companion object {
        private const val META = "test:retraction-reboot"
        private const val EFFECT_PREFIX = "test:retraction-effect:"
    }
}
