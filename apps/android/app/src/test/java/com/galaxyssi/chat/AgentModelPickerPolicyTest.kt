package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentModelPickerPolicyTest {
    @Test fun activeOlderModelStaysVisibleWithoutExpandingTheOtherOlderModels() {
        val codex = target("desktop:codex", "gpt-6.2-astra", "gpt-6.2-sol", "gpt-6-astra", "gpt-5.6-sol")
        val (visible, folded) = AgentModelPickerPolicy.modelGroups(codex, "gpt-6-astra")
        assertEquals(listOf("gpt-6.2-astra", "gpt-6.2-sol", "gpt-6-astra"), visible.map { it.id })
        assertEquals(listOf("gpt-5.6-sol"), folded.map { it.id })
    }

    @Test fun oldOnlyCatalogRemainsFullyVisibleAndNewIdsNeedNoAppUpdate() {
        val older = target("desktop:codex", "gpt-6-astra", "gpt-5.6-sol")
        val (all, none) = AgentModelPickerPolicy.modelGroups(older, "")
        assertEquals(older.invocationProfile.models, all)
        assertTrue(none.isEmpty())
        val future = target("desktop:codex", "gpt-future", "gpt-6-astra")
        assertEquals("gpt-future", AgentModelPickerPolicy.modelGroups(future, "").first.single().id)
    }

    @Test fun desktopGroupingDoesNotCollapseDifferentComputers() {
        val a = target("desktop_a:codex")
        val b = target("desktop_b:codex")
        val claude = target("desktop_a:claude")
        val generic = target("codex")
        assertEquals(listOf(b, a, claude), AgentModelPickerPolicy.desktopTargets(listOf(claude, a, generic, b), b.id))
        assertEquals(listOf(claude, a, b), AgentModelPickerPolicy.desktopTargets(listOf(a, claude, b), claude.id))
    }

    @Test fun aliasedSelectionAndDesktopLabelAreOnlyPresentationChanges() {
        val claude = target("desktop_a:claude", "claude-opus-5-5", "claude-opus-5").let {
            it.copy(invocationProfile = it.invocationProfile.copy(modelAliases = mapOf("old-opus" to "claude-opus-5")))
        }
        assertEquals(claude.invocationProfile.models, AgentModelPickerPolicy.modelGroups(claude, "old-opus").first)
        assertEquals("Codex Agent" to "Desktop-T14", AgentModelPickerPolicy.desktopLabel("Codex Agent \u00b7 Desktop-T14"))
        assertEquals("GPT-6.2 Astra", AgentModelPickerPolicy.modelLabel("gpt-6.2-astra"))
        assertEquals("GPT-6.2 Sol", AgentModelPickerPolicy.modelLabel("gpt-6.2-sol"))
    }

    private fun target(id: String, vararg models: String) = AgentCallableTarget(
        id, id, AgentConnectorKind.AGENT, AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.CHAT),
        invocationProfile = AgentInvocationProfile(models = models.map { AgentModelOption(it) })
    )
}
