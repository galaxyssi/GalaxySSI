package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentMemoryLookupIdentityTest {
    private val item = AgentMemoryItem(AgentMemoryKind.PREFERENCE, "hello", id = "one", key = "",
        scope = AgentMemoryScope.CONVERSATION, scopeId = "chat")

    @Test fun caseInsensitiveValuesShareLookupIdentityWithoutExpansion() {
        val equivalent = listOf("Hello" to "HELLO", "I" to "\u0131", "i" to "\u0130", "\u03c2" to "\u03c3",
            "\u017f" to "s", "\u1e9e" to "\u00df", "\u212a" to "k", "\ud801\udc00" to "\ud801\udc28")
        equivalent.forEach { (a, b) ->
            assertTrue("Expected ignore-case equality", a.equals(b, ignoreCase = true))
            assertEquals(AgentMemoryLookupIdentity.material(item.copy(value = a)), AgentMemoryLookupIdentity.material(item.copy(value = b)))
        }
        assertNotEquals(AgentMemoryLookupIdentity.material(item.copy(value = "\u00df")), AgentMemoryLookupIdentity.material(item.copy(value = "ss")))
        assertNotEquals(AgentMemoryLookupIdentity.material(item.copy(value = "\u00e9")), AgentMemoryLookupIdentity.material(item.copy(value = "e\u0301")))
    }

    @Test fun keyNamespacesRemainExactAndLengthDelimited() {
        assertNotEquals(AgentMemoryLookupIdentity.material(item.copy(scopeId = "a:b", key = "c")),
            AgentMemoryLookupIdentity.material(item.copy(scopeId = "a", key = "b:c")))
        assertNotEquals(AgentMemoryLookupIdentity.material(item.copy(scopeId = "CHAT")), AgentMemoryLookupIdentity.material(item))
        assertNotEquals(AgentMemoryLookupIdentity.material(item.copy(kind = AgentMemoryKind.KNOWLEDGE)), AgentMemoryLookupIdentity.material(item))
    }

    @Test fun keyedValuesShareCandidateBucketButUnkeyedValuesDoNot() {
        assertEquals(AgentMemoryLookupIdentity.material(item.copy(key = "language")), AgentMemoryLookupIdentity.material(item.copy(key = "language", value = "different")))
        assertNotEquals(AgentMemoryLookupIdentity.material(item), AgentMemoryLookupIdentity.material(item.copy(value = "different")))
    }
}
