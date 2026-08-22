package com.signalasi.chat

import java.lang.reflect.Modifier
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTranscriptStoreConcurrencyTest {
    @Test
    fun databaseBackedReadsDoNotHoldTheStoreMonitor() {
        val readMethods = setOf(
            "list",
            "taskEntries",
            "page",
            "entriesAfter",
            "entriesForTurn",
            "entriesForTask",
            "fullEntry",
            "textChunkPage",
            "conversationIdForTurn",
            "conversationIdForTask",
            "turnIdForTask",
            "taskIds"
        )

        val methodsByName = AgentTranscriptStore::class.java.declaredMethods
            .filter { method -> method.name.substringBefore('$') in readMethods }
            .groupBy { method -> method.name.substringBefore('$') }

        readMethods.forEach { name ->
            val methods = methodsByName[name].orEmpty()
            check(methods.isNotEmpty()) { "Missing transcript read method: $name" }
            methods.forEach { method ->
                assertFalse(
                    "$name must not block the UI on the AgentTranscriptStore monitor",
                    Modifier.isSynchronized(method.modifiers)
                )
            }
        }
    }

    @Test
    fun conversationMutationRemainsSerialized() {
        val createConversation = AgentTranscriptStore::class.java.declaredMethods
            .first { method -> method.name == "createConversation" }

        assertTrue(Modifier.isSynchronized(createConversation.modifiers))
    }
}
