package com.galaxyssi.chat.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentComposerUiPolicyTest {
    @Test
    fun idleToTypingToBackSwapsVoiceAndMoreInOneSlot() {
        val idle = AgentComposerUiPolicy.resolve(false, false, false, true)
        val typing = AgentComposerUiPolicy.resolve(false, true, false, true)
        val afterBack = AgentComposerUiPolicy.resolve(false, false, false, true)
        assertTrue(idle.showVoiceButton)
        assertFalse(idle.showMoreButton)
        assertTrue(typing.showMoreButton)
        assertFalse(typing.showVoiceButton)
        assertTrue(afterBack.showVoiceButton)
        assertFalse(afterBack.showMoreButton)
        assertTrue(listOf(idle, typing, afterBack).all { it.showPrimaryActionSlot })
    }

    @Test
    fun allComposerStatesShowAtMostOneAction() {
        for (hasInput in listOf(false, true)) {
            for (textMode in listOf(false, true)) {
                for (tray in listOf(false, true)) {
                    for (voice in listOf(false, true)) {
                        val state = AgentComposerUiPolicy.resolve(hasInput, textMode, tray, voice)
                        val visible = listOf(state.showMoreButton, state.showSendButton, state.showVoiceButton).count { it }
                        assertTrue(visible <= 1)
                        assertTrue(state.showPrimaryActionSlot == (visible == 1))
                        if (hasInput) assertTrue(state.showSendButton)
                    }
                }
            }
        }
    }

    @Test
    fun expandedMoreTrayHidesVoiceUntilClosed() {
        val open = AgentComposerUiPolicy.resolve(false, false, true, true)
        val closed = AgentComposerUiPolicy.resolve(false, false, false, true)
        assertTrue(open.showMoreButton)
        assertTrue(open.showActionTray)
        assertFalse(open.showVoiceButton)
        assertTrue(closed.showVoiceButton)
        assertFalse(closed.showActionTray)
    }

    @Test
    fun draftKeepsSendVisibleAfterKeyboardIsDismissed() {
        val state = AgentComposerUiPolicy.resolve(true, false, false, true)
        assertTrue(state.showSendButton)
        assertFalse(state.showVoiceButton)
        assertFalse(state.showMoreButton)
    }

    @Test
    fun defaultComposerHidesPrimaryAction() {
        val state = AgentComposerUiPolicy.resolve(
            hasInput = false,
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
            textModeActive = false,
            actionTrayRequested = true
        )
        val populated = AgentComposerUiPolicy.resolve(
            hasInput = true,
            textModeActive = true,
            actionTrayRequested = true
        )

        assertTrue(empty.showMoreButton)
        assertTrue(empty.showActionTray)
        assertFalse(empty.showSendButton)
        assertFalse(populated.showActionTray)
        assertTrue(populated.showSendButton)
    }

    @Test
    fun sendButtonRequiresActualInput() {
        listOf(false, true).forEach { textModeActive ->
            listOf(false, true).forEach { actionTrayRequested ->
                val state = AgentComposerUiPolicy.resolve(
                    hasInput = false,
                    textModeActive = textModeActive,
                    actionTrayRequested = actionTrayRequested
                )

                assertFalse(state.showSendButton)
            }
        }
    }
}
