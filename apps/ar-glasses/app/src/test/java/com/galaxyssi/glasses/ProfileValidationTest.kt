package com.galaxyssi.glasses

import org.junit.Assert.*
import org.junit.Test

class ProfileValidationTest {
    private val valid = Profile("https://example.test/v1/chat/completions", "model", "test-key", "openai")

    private fun rejected(profile: Profile, resource: Int) {
        val failure = runCatching { profile.validated { "localized:$it" } }.exceptionOrNull()
        assertTrue(failure is IllegalArgumentException)
        assertEquals("localized:$resource", failure?.message)
        assertFalse(failure?.message.orEmpty().contains(profile.key))
    }

    @Test fun acceptsOnlySupportedSecureProviderEndpoints() {
        listOf(valid, valid.copy(endpoint = "https://example.test/v1/messages", style = "anthropic"),
            valid.copy(endpoint = "https://example.test/v1/models/m:generateContent", style = "gemini"))
            .forEach { assertSame(it, it.validated { error("No error copy should be read") }) }
    }

    @Test fun rejectsUnsafeAddressesWithoutRelaxingValidation() {
        for (url in listOf("http://example.test/v1/chat/completions",
            "https://user@example.test/v1/chat/completions", "https://example.test/v1/chat/completions?key=x",
            "https://example.test/v1/chat/completions#fragment")) {
            rejected(valid.copy(endpoint = url), R.string.glasses_copy_only_https_addresses_without_parameters_are_supported)
        }
    }

    @Test fun preservesProviderAndModelValidationMessages() {
        rejected(valid.copy(style = "unknown"), R.string.glasses_copy_unsupported_api_type)
        rejected(valid.copy(style = "anthropic"), R.string.glasses_copy_api_address_does_not_match_its_type)
        rejected(valid.copy(model = ""), R.string.glasses_copy_invalid_model_or_key)
        rejected(valid.copy(key = "bad\nkey"), R.string.glasses_copy_invalid_model_or_key)
    }
}
