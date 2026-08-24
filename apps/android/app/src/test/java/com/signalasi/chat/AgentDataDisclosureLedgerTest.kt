package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentDataDisclosureLedgerTest {
    @Test
    fun textClassifierSeparatesPromptHistorySystemAndToolData() {
        val kinds = AgentDataDisclosureClassifier.classifyText(
            text = "Use current screen_context with recalled memory and device status",
            includeHistory = true,
            includeSystemInstructions = true,
            includeToolOutput = true
        )

        assertTrue(AgentDisclosedDataKind.MESSAGE_TEXT in kinds)
        assertTrue(AgentDisclosedDataKind.CONVERSATION_HISTORY in kinds)
        assertTrue(AgentDisclosedDataKind.SYSTEM_INSTRUCTIONS in kinds)
        assertTrue(AgentDisclosedDataKind.TOOL_OUTPUT in kinds)
        assertTrue(AgentDisclosedDataKind.SCREEN_CONTEXT in kinds)
        assertTrue(AgentDisclosedDataKind.MEMORY_CONTEXT in kinds)
        assertTrue(AgentDisclosedDataKind.DEVICE_CONTEXT in kinds)
    }

    @Test
    fun textSummaryStreamsModelMessagesWithoutJoiningTheirContent() {
        val summary = AgentDataDisclosureClassifier.summarizeTextFragments(
            fragments = sequenceOf(
                "Use current screen_context",
                "Read recalled memory",
                "Inspect device status"
            ),
            includeHistory = true,
            includeSystemInstructions = true,
            includeToolOutput = true
        )

        assertEquals(
            "Use current screen_context\nRead recalled memory\nInspect device status".length,
            summary.textCharacters
        )
        assertTrue(AgentDisclosedDataKind.MESSAGE_TEXT in summary.dataKinds)
        assertTrue(AgentDisclosedDataKind.CONVERSATION_HISTORY in summary.dataKinds)
        assertTrue(AgentDisclosedDataKind.SYSTEM_INSTRUCTIONS in summary.dataKinds)
        assertTrue(AgentDisclosedDataKind.TOOL_OUTPUT in summary.dataKinds)
        assertTrue(AgentDisclosedDataKind.SCREEN_CONTEXT in summary.dataKinds)
        assertTrue(AgentDisclosedDataKind.MEMORY_CONTEXT in summary.dataKinds)
        assertTrue(AgentDisclosedDataKind.DEVICE_CONTEXT in summary.dataKinds)
    }

    @Test
    fun attachmentClassifierCoversMediaDocumentsAndUnknownFiles() {
        assertEquals(
            AgentDisclosedDataKind.IMAGE,
            AgentDataDisclosureClassifier.attachmentKind("image/jpeg", "photo.jpg")
        )
        assertEquals(
            AgentDisclosedDataKind.AUDIO,
            AgentDataDisclosureClassifier.attachmentKind("audio/m4a", "voice.m4a")
        )
        assertEquals(
            AgentDisclosedDataKind.VIDEO,
            AgentDataDisclosureClassifier.attachmentKind("video/mp4", "clip.mp4")
        )
        assertEquals(
            AgentDisclosedDataKind.DOCUMENT,
            AgentDataDisclosureClassifier.attachmentKind("application/octet-stream", "report.xlsx")
        )
        assertEquals(
            AgentDisclosedDataKind.OTHER_FILE,
            AgentDataDisclosureClassifier.attachmentKind("application/octet-stream", "archive.bin")
        )
    }

    @Test
    fun storeUpdatesReceiptWithoutRetainingRequestContent() {
        val store = InMemoryAgentDataDisclosureStore()
        val record = record(destinationId = "deepseek", textCharacters = 1_240)

        store.append(record)
        store.update(record.eventId, AgentDisclosureStatus.SENT)

        val stored = store.find(record.eventId)
        assertEquals(AgentDisclosureStatus.SENT, stored?.status)
        assertEquals(1_240, stored?.textCharacters)
        assertEquals(setOf(AgentDisclosedDataKind.MESSAGE_TEXT), stored?.dataKinds)
        assertTrue(stored?.failureReason.isNullOrBlank())
    }

    @Test
    fun destinationBlockSurvivesHistoryClear() {
        val store = InMemoryAgentDataDisclosureStore()
        val record = record(destinationId = "desktop-codex")
        store.append(record)
        store.setDestinationBlocked(record.destinationId, true)

        store.clearHistory()

        assertTrue(record.destinationId in store.blockedDestinationIds())
        assertTrue(store.list().isEmpty())
        assertNull(store.find(record.eventId))
        store.setDestinationBlocked(record.destinationId, false)
        assertFalse(record.destinationId in store.blockedDestinationIds())
    }

    @Test
    fun summaryDistinguishesCloudDesktopAndBlockedFlows() {
        val records = listOf(
            record(
                destinationId = "cloud-openai",
                location = AgentResourceLocation.CLOUD,
                status = AgentDisclosureStatus.SENT
            ),
            record(
                destinationId = "desktop-codex",
                location = AgentResourceLocation.TRUSTED_DESKTOP,
                status = AgentDisclosureStatus.SENT
            ),
            record(
                destinationId = "cloud-openai",
                location = AgentResourceLocation.CLOUD,
                status = AgentDisclosureStatus.BLOCKED
            )
        )

        val summary = AgentDataDisclosureLedger.summary(records)

        assertEquals(3, summary.total)
        assertEquals(2, summary.cloud)
        assertEquals(1, summary.trustedDesktop)
        assertEquals(1, summary.blocked)
        assertEquals(2, summary.destinations)
    }

    @Test
    fun disclosureIndexUpdatesOneRecordWithoutGrowingPastItsLimit() {
        val update = AgentDisclosureRecordIndex.append(
            currentIds = listOf("one", "two", "three"),
            eventId = "four",
            maxRecords = 3
        )

        assertEquals(listOf("two", "three", "four"), update.recordIds)
        assertEquals(listOf("one"), update.evictedIds)
    }

    @Test
    fun disclosureIndexMovesAnExistingRecordToTheNewestPosition() {
        val update = AgentDisclosureRecordIndex.append(
            currentIds = listOf("one", "two", "three"),
            eventId = "two",
            maxRecords = 3
        )

        assertEquals(listOf("one", "three", "two"), update.recordIds)
        assertTrue(update.evictedIds.isEmpty())
    }

    private fun record(
        destinationId: String,
        location: AgentResourceLocation = AgentResourceLocation.CLOUD,
        status: AgentDisclosureStatus = AgentDisclosureStatus.PREPARING,
        textCharacters: Int = 10
    ) = AgentDataDisclosureRecord(
        destinationId = destinationId,
        destinationTitle = destinationId,
        location = location,
        trust = if (location == AgentResourceLocation.TRUSTED_DESKTOP) {
            AgentResourceTrust.VERIFIED_PAIRED
        } else {
            AgentResourceTrust.CLOUD_CONFIGURED
        },
        protection = if (location == AgentResourceLocation.TRUSTED_DESKTOP) {
            AgentDisclosureProtection.SIGNAL_E2EE
        } else {
            AgentDisclosureProtection.TLS
        },
        purpose = "Test",
        dataKinds = setOf(AgentDisclosedDataKind.MESSAGE_TEXT),
        textCharacters = textCharacters,
        status = status
    )
}
