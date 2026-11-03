package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentDeviceOperationCheckpointTest {
    private fun checkpoint() = AgentRunControlEvent(
        conversationId = "conversation", messageId = "", taskId = AgentDeviceOperationCheckpoint.runId("conversation"),
        runId = AgentDeviceOperationCheckpoint.runId("conversation"), agentId = "phone-operation", deviceId = "local",
        type = AgentRunControlEventType.CHECKPOINT_SAVED, sequence = 1,
        payload = mapOf("snapshot_kind" to "device_operation", "operation_id" to "operation")
    )

    private fun legacyFailure() = checkpoint().copy(type = AgentRunControlEventType.RUN_FAILED,
        payload = checkpoint().payload + mapOf("replay_safe" to false,
            "reason" to "interrupted_run_cannot_be_replayed_safely"))

    @Test fun recognizesOldSnapshotsWithoutRecoveryFlag() {
        assertTrue(AgentDeviceOperationCheckpoint.isSnapshot(checkpoint()))
    }

    @Test fun recognizesNewObservationOnlySnapshots() {
        assertTrue(AgentDeviceOperationCheckpoint.isSnapshot(checkpoint().copy(
            payload = checkpoint().payload + ("recovery_mode" to "observation_only"))))
    }

    @Test fun repairsOnlyTheGenericRecoveryMisclassification() {
        assertTrue(AgentDeviceOperationCheckpoint.isMisclassifiedFailure(legacyFailure()))
        assertFalse(AgentDeviceOperationCheckpoint.isMisclassifiedFailure(checkpoint()))
    }

    @Test fun rejectsCrossConversationOrExecutorSnapshots() {
        val valid = checkpoint()
        listOf(valid.copy(conversationId = "other"), valid.copy(agentId = "codex"), valid.copy(deviceId = "remote"),
            valid.copy(taskId = "other"), valid.copy(runId = "other"), valid.copy(messageId = "message"))
            .forEach { assertFalse(AgentDeviceOperationCheckpoint.isSnapshot(it)) }
    }

    @Test fun rejectsMissingOperationIdentityAndOtherSnapshotTypes() {
        assertFalse(AgentDeviceOperationCheckpoint.isSnapshot(checkpoint().copy(payload = emptyMap())))
        assertFalse(AgentDeviceOperationCheckpoint.isSnapshot(checkpoint().copy(
            payload = checkpoint().payload + ("snapshot_kind" to "native_effect"))))
    }

    @Test fun neverRevivesUserCancellationOrCompletion() {
        listOf(AgentRunControlEventType.RUN_CANCELLED, AgentRunControlEventType.RUN_COMPLETED).forEach {
            assertFalse(AgentDeviceOperationCheckpoint.isMisclassifiedFailure(legacyFailure().copy(type = it)))
        }
    }

    @Test fun neverRepairsAnUnrelatedFailure() {
        assertFalse(AgentDeviceOperationCheckpoint.isMisclassifiedFailure(legacyFailure().copy(
            payload = legacyFailure().payload + ("reason" to "disk_full"))))
        assertFalse(AgentDeviceOperationCheckpoint.isMisclassifiedFailure(legacyFailure().copy(
            payload = legacyFailure().payload - "replay_safe")))
    }
}
