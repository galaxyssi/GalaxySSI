package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CloudConversationTextPolicyTest {
    @Test fun managedResponsesBufferEvenBeforeAnyToolEvidenceExists() {
        val policy = CloudConversationTextPolicy(managedCollaboration = true)
        assertTrue(policy.bufferRound(hasEvidence = false))
        assertTrue(policy.bufferRound(hasEvidence = true))
        assertFalse(policy.citationPreview(requested = true, hasEvidence = false))
        assertFalse(policy.citationPreview(requested = true, hasEvidence = true))
        assertEquals("", policy.artifactSuffix("\n```galaxyssi-rich\n[]\n```"))
    }

    @Test fun ordinaryChatKeepsStreamingAndExistingCitationAndImageBehavior() {
        val policy = CloudConversationTextPolicy(managedCollaboration = false)
        assertFalse(policy.bufferRound(hasEvidence = false))
        assertTrue(policy.bufferRound(hasEvidence = true))
        assertFalse(policy.citationPreview(requested = true, hasEvidence = false))
        assertFalse(policy.citationPreview(requested = false, hasEvidence = true))
        assertTrue(policy.citationPreview(requested = true, hasEvidence = true))
        val suffix = "\n```galaxyssi-rich\n[]\n```"
        assertEquals(suffix, policy.artifactSuffix(suffix))
    }
}
