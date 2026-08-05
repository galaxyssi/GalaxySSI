package com.signalasi.chat.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentComposerUiPolicyTest {
    @Test
    fun defaultComposerHidesPrimaryAction() {
        val state = AgentComposerUiPolicy.resolve(
            hasInput = false,
            hasPendingPrimaryAction = false,
            textModeActive = false,
            actionTrayRequested = false
        )

        assertFalse(state.showPrimaryActionSlot)
        assertFalse(state.showMoreButton)
        assertFalse(state.showSendButton)
        assertFalse(state.showActionTray)
    }

    @Test
    fun textModeShowsMoreButton() {
        val state = AgentComposerUiPolicy.resolve(
            hasInput = false,
            hasPendingPrimaryAction = false,
            textModeActive = true,
            actionTrayRequested = false
        )

        assertTrue(state.showPrimaryActionSlot)
        assertTrue(state.showMoreButton)
        assertFalse(state.showSendButton)
    }

    @Test
    fun requestedTrayOnlyOpensForEmptyComposer() {
        val empty = AgentComposerUiPolicy.resolve(
            hasInput = false,
            hasPendingPrimaryAction = false,
            textModeActive = false,
            actionTrayRequested = true
        )
        val populated = AgentComposerUiPolicy.resolve(
            hasInput = true,
            hasPendingPrimaryAction = false,
            textModeActive = true,
            actionTrayRequested = true
        )

        assertTrue(empty.showMoreButton)
        assertTrue(empty.showActionTray)
        assertFalse(populated.showActionTray)
        assertTrue(populated.showSendButton)
    }

    @Test
    fun pendingAgentActionKeepsPrimaryActionAvailable() {
        val state = AgentComposerUiPolicy.resolve(
            hasInput = false,
            hasPendingPrimaryAction = true,
            textModeActive = false,
            actionTrayRequested = true
        )

        assertFalse(state.showMoreButton)
        assertTrue(state.showSendButton)
        assertFalse(state.showActionTray)
    }
}
