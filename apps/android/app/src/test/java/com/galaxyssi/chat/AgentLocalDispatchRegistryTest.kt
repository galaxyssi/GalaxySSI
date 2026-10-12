package com.galaxyssi.chat

import java.util.UUID
import java.util.concurrent.Executor
import org.junit.Assert.*
import org.junit.Test

class AgentLocalDispatchRegistryTest {
    @Test fun exactStopDoesNotCancelOtherMembersSharingATaskOrSetAGlobalTaskStop() = fixture { identity ->
        val sibling = identity.copy(sourceMessageId = identity.sourceMessageId + 1, actionId = "other-action")
        AgentLocalDispatchRegistry.register(identity).use { first ->
            AgentLocalDispatchRegistry.register(sibling).use { other ->
                assertTrue(AgentLocalDispatchRegistry.cancelExact(identity))
                assertTrue(first.token.isCancellationRequested)
                assertFalse(other.token.isCancellationRequested)
                assertFalse(PhoneExecutionAuthority.isCancelled(identity.taskId))
                assertFalse(AgentLocalDispatchRegistry.cancelExact(identity))
            }
        }
    }

    @Test fun everyIdentityComponentMustMatch() = fixture { identity ->
        AgentLocalDispatchRegistry.register(identity).use { lease ->
            listOf(identity.copy(sourceMessageId = identity.sourceMessageId + 1),
                identity.copy(contactId = "other"), identity.copy(conversationId = "other"),
                identity.copy(turnId = "other"), identity.copy(taskId = "other"),
                identity.copy(actionId = "other")).forEach { assertFalse(AgentLocalDispatchRegistry.cancelExact(it)) }
            assertFalse(lease.token.isCancellationRequested)
        }
    }

    @Test fun upstreamTurnStopIsObservedBeforeQueueingWithoutWaitingForTheWorker() = fixture { identity ->
        val cancellation = AgentNativeToolCancellationSource()
        cancellation.cancel()
        var stops = 0
        AgentLocalDispatchRegistry.register(identity, cancellation.token).execute<String>(
            { fail("Already stopped turn cannot start inference"); "" },
            { fail("Already stopped turn cannot deliver") }, { stops++ })
        assertEquals(1, stops)
        assertFalse(AgentLocalDispatchRegistry.cancelExact(identity))
        assertEquals(0, PhoneExecutionAuthority.cancellationListenerCount(identity.taskId))
    }

    @Test fun duplicateRegistrationDoesNotLeakOrReplaceTheOriginalLease() = fixture { identity ->
        AgentLocalDispatchRegistry.register(identity).use { first ->
            assertThrows(IllegalStateException::class.java) { AgentLocalDispatchRegistry.register(identity) }
            assertEquals(1, PhoneExecutionAuthority.cancellationListenerCount(identity.taskId))
            assertTrue(AgentLocalDispatchRegistry.cancelExact(identity))
            assertTrue(first.token.isCancellationRequested)
        }
    }

    @Test fun rejectedQueueAndThrowingDeliveryBothRetireExactRegistration() = fixture { identity ->
        assertThrows(java.util.concurrent.RejectedExecutionException::class.java) {
            AgentLocalDispatchRegistry.register(identity).enqueue(
                Executor { throw java.util.concurrent.RejectedExecutionException() }, { "reply" }, {})
        }
        assertFalse(AgentLocalDispatchRegistry.cancelExact(identity))
        assertThrows(IllegalStateException::class.java) {
            AgentLocalDispatchRegistry.register(identity).execute({ "reply" }, { error("Public delivery failure") })
        }
        assertFalse(AgentLocalDispatchRegistry.cancelExact(identity))
        assertEquals(0, PhoneExecutionAuthority.cancellationListenerCount(identity.taskId))
    }

    @Test fun completionWinsBeforeLateStopEvenWhileDeliveryIsRunning() = fixture { identity ->
        AgentLocalDispatchRegistry.register(identity).execute({ "reply" }, {
            assertFalse(AgentLocalDispatchRegistry.cancelExact(identity))
            assertEquals("reply", it.getOrThrow())
        }, { fail("Late stop must not reclaim completion") })
        assertFalse(AgentLocalDispatchRegistry.cancelExact(identity))
    }

    @Test fun finishedLeaseUnsubscribesUpstreamCancellation() = fixture { identity ->
        val cancellation = AgentNativeToolCancellationSource()
        val lease = AgentLocalDispatchRegistry.register(identity, cancellation.token)
        lease.close()
        cancellation.cancel()
        assertFalse(lease.token.isCancellationRequested)
    }

    private fun fixture(test: (AgentLocalDispatchIdentity) -> Unit) {
        val before = AgentLocalDispatchRegistry.activeCount()
        val id = "public-local-registry-${UUID.randomUUID()}"
        test(AgentLocalDispatchIdentity(1L, "local-llm", "$id-conversation", "$id-turn", "$id-task", "$id-action"))
        assertEquals(before, AgentLocalDispatchRegistry.activeCount())
    }
}
