package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

class CollaborationOrganizationRuntimeTest {
    @Test fun runtimeRetainsObservedCompletionsAndReactivatesTheSameMembers(): Unit = runBlocking {
        withTimeout(20_000) {
            val fixture = OrganizationRuntimeFixture()
            val store = InMemoryAgentTeamExecutionStore()
            val checkpoint = fixture.seed(store)
            fixture.validate(checkpoint)
            val records = store.records()
            assertEquals(2, CollaborationTeamOrganizationProjection.current(records.single()).finishedWork.size)
            assertTrue(checkpoint.definition.members.all { it.context.keys.all(::isPersistedAgentTeamContextKey) })
            fixture.recover(store)
            assertTrue(fixture.calls.none { it in setOf("build", "review") })
        }
    }
}
