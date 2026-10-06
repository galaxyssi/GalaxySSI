package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationAdaptivePilotVerdictTest {
    private fun report(): JSONObject {
        val content = "Synthetic host-accepted result; not a scientific conclusion"
        return JSONObject().put("status", "host_goal_accepted").put("finished", true)
            .put("cleanup_confirmed", true).put("pending_remote_owners", JSONArray())
            .put("active_conversation_preserved", true)
            .put("phone_dispatches", JSONArray().put(JSONObject().put("node_id", "coordinator")))
            .put("worker_results", JSONArray().put(JSONObject().put("node_id", "coordinator")
                .put("content", content).put("content_sha256", CollaborationRemotePilotDispatch.sha256(content.toByteArray(Charsets.UTF_8)))))
            .put("rounds", JSONArray().put(JSONObject().put("goal_disposition", "achieved")))
            .put("goal_verified_by_external_evaluator", false).put("scientific_capability_gain_proven", false)
    }

    private fun reject(value: JSONObject): CollaborationAdaptivePilotVerdict {
        val verdict = CollaborationAdaptivePilotVerdict.evaluate(JSONObject(value.toString()))
        assertFalse(verdict.passed)
        assertTrue(runCatching { verdict.requirePassed() }.exceptionOrNull() is AssertionError)
        return verdict
    }

    @Test fun acceptedDispatchAndResultPassWithoutClaimingScientificSuccess() {
        val value = report()
        CollaborationAdaptivePilotVerdict.evaluate(value).requirePassed()
        assertFalse(value.getBoolean("goal_verified_by_external_evaluator"))
        assertFalse(value.getBoolean("scientific_capability_gain_proven"))
    }

    @Test fun allUnsuccessfulRunnerOutcomesFailEvenWhenCleanupSucceeded() {
        for (status in listOf("preparing", "running", "interrupted_or_failed", "phone_dispatch_envelope_reached",
            "observable_blocker", "unverified_history_not_goal_acceptance", "execution_settled_without_goal_acceptance", "unknown")) {
            reject(report().put("status", status))
        }
    }

    @Test fun disconnectedNeverDispatchedTrialCannotPass() {
        reject(report().put("phone_dispatches", JSONArray()).put("worker_results", JSONArray()))
    }

    @Test fun reservationWithoutRemoteReplyCannotPass() {
        reject(report().put("worker_results", JSONArray()))
    }

    @Test fun resultFromAnotherNodeCannotPass() {
        val value = report()
        value.getJSONArray("worker_results").getJSONObject(0).put("node_id", "other-run-node")
        reject(value)
    }

    @Test fun emptyOrCorruptReplyCannotPass() {
        for (content in listOf("", "altered")) {
            val value = report()
            value.getJSONArray("worker_results").getJSONObject(0).put("content", content)
            reject(value)
        }
    }

    @Test fun acceptedLabelWithoutAcceptedCheckpointCannotPass() {
        reject(report().put("rounds", JSONArray()))
        reject(report().put("rounds", JSONArray().put(JSONObject().put("goal_disposition", "continue"))))
    }

    @Test fun exceptionAndTimeoutRemainFailuresWithOriginalCause() {
        val cause = IllegalStateException("Synthetic network interruption")
        val verdict = reject(report().put("failure_type", cause.javaClass.simpleName).put("failure", cause.message))
        val thrown = runCatching { verdict.requirePassed(cause) }.exceptionOrNull()
        assertSame(cause, thrown?.cause)
    }

    @Test fun unfinishedOrUnconfirmedCleanupCannotPass() {
        for (field in listOf("finished", "cleanup_confirmed", "active_conversation_preserved")) {
            reject(report().put(field, false))
            reject(report().put(field, "true"))
        }
        reject(report().put("cleanup_failure", "Synthetic failure"))
        reject(report().put("pending_remote_owners", JSONArray().put("pending-task")))
    }

    @Test fun incompleteOrMalformedReportsFailClosed() {
        reject(JSONObject())
        for (key in listOf("status", "finished", "cleanup_confirmed", "pending_remote_owners", "active_conversation_preserved",
            "phone_dispatches", "worker_results", "rounds")) {
            reject(report().also { it.remove(key) })
        }
        reject(report().put("phone_dispatches", JSONArray().put("not-an-object")))
        reject(report().put("worker_results", JSONArray().put("not-an-object")))
    }

    @Test fun outcomeCheckingDoesNotRewriteOriginalEvidence() {
        val value = report().put("status", "interrupted_or_failed")
        val original = value.toString()
        reject(value)
        assertEquals(original, value.toString())
    }
}
