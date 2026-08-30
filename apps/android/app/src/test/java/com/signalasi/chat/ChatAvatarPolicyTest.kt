package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatAvatarPolicyTest {
    @Test
    fun geminiCliUsesGeminiProviderLogo() {
        val contact = Contact("desktop_t14:gemini", "Gemini CLI", "")

        assertEquals(R.drawable.logo_provider_gemini, contactAvatarRes(contact))
        assertFalse(contactUsesGeneratedAvatar(contact))
    }

    @Test
    fun unknownContactUsesStableGeneratedContactAvatar() {
        assertTrue(contactUsesGeneratedAvatar(Contact("unknown-contact", "New contact", "")))
    }

    @Test
    fun knownAgentsKeepTheirDedicatedAvatars() {
        assertFalse(contactUsesGeneratedAvatar(Contact("desktop_t14:codex", "Codex", "")))
        assertFalse(contactUsesGeneratedAvatar(Contact("desktop_t14:claude", "Claude Code", "")))
    }
}
