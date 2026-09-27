package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ScreenAssistantPagePolicyTest {
    private fun node(path: String, text: String = "", bounds: String = "0,0,100,200", scroll: Boolean = false) =
        PhoneUiNode(path, text, "", "", "TextView", bounds, false, false, false, scroll, true, null, false)
    private fun snapshot(vararg nodes: PhoneUiNode) = PhoneUiSnapshot(12, "test.app", "revision", nodes.toList(), false)
    @Test fun selectsLargestEnabledScrollingArea() {
        val small = node("0/1", scroll = true, bounds = "0,0,20,20")
        val large = node("0/2", scroll = true)
        assertEquals(large, ScreenAssistantPagePolicy.scrollNode(snapshot(small, large, large.copy(enabled = false))))
    }
    @Test fun excludesHeadersOffscreenNodesPasswordsAndEditors() {
        val scroll = node("0/1", scroll = true)
        val value = snapshot(scroll, node("0/2", "header"), node("0/1/0", "article"),
            node("0/1/1", "offscreen", "0,220,100,240"), node("0/1/2", "secret").copy(password = true),
            node("0/1/3", "draft").copy(editable = true))
        assertEquals(listOf("article"), ScreenAssistantPagePolicy.text(value, scroll))
    }
    @Test fun removesOnlyAdjacentViewportOverlap() {
        assertEquals(listOf("d", "a"), ScreenAssistantPagePolicy.append(listOf("a", "b", "c"), listOf("b", "c", "d", "a")))
    }
    @Test fun repeatedSentenceElsewhereIsRetained() {
        assertEquals(listOf("repeat", "new"), ScreenAssistantPagePolicy.append(listOf("repeat", "end"), listOf("repeat", "new")))
    }
    @Test fun fullyOverlappingViewportAddsNoText() {
        assertTrue(ScreenAssistantPagePolicy.append(listOf("a", "b"), listOf("a", "b")).isEmpty())
    }
    @Test fun escapesUntrustedMarkup() {
        assertEquals("&lt;script&gt;&amp;&quot;&#39;", ScreenAssistantPagePolicy.escape("<script>&\"'"))
    }
    @Test fun distinguishesWindowAndAddressChanges() {
        val address = node("0/1", "https://a.test").copy(viewId = "chrome:id/url_bar")
        val value = snapshot(address)
        assertFalse(ScreenAssistantPagePolicy.sameTarget(value, value.copy(windowId = 13)))
        assertFalse(ScreenAssistantPagePolicy.sameTarget(value, snapshot(address.copy(text = "https://b.test"))))
        assertTrue(ScreenAssistantPagePolicy.sameTarget(value, value.copy(revision = "new-revision")))
    }
    @Test fun emptyStructureStillHasStableFingerprint() {
        assertEquals(64, ScreenAssistantPagePolicy.fingerprint(emptyList()).length)
        assertNotEquals(ScreenAssistantPagePolicy.fingerprint(listOf("a")), ScreenAssistantPagePolicy.fingerprint(listOf("b")))
    }
}
