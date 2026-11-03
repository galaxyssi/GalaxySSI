package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentNativeToolContractCatalogTest {
    private val descriptor = AgentNativeToolDescriptor("public.browser.read", "1.0.0", "Public browser",
        "Read a public page", AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(),
        AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW,
        idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
        concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY, effect = AgentNativeToolEffect.READ_ONLY)

    private fun registry(value: AgentNativeToolDescriptor = descriptor,
        availability: AgentNativeToolAvailabilityProvider = AgentNativeToolAvailabilityProvider { value.availability }) =
        AgentNativeToolRegistry(descriptorCacheTtlMillis = 0).register(AgentNativeToolDefinition(value,
            AgentNativeToolExecutor { error("Contract binding must not execute tools") }, availabilityProvider = availability))

    @Test fun setupStatusReasonAndTimestampAreObservationsNotContractChanges() {
        val missing = AgentNativeToolAvailability(AgentNativeToolAvailabilityStatus.REQUIRES_SETUP, "Install fixture", 1)
        val before = registry(descriptor.copy(availability = missing))
        val after = registry(descriptor.copy(availability = AgentNativeToolAvailability(
            AgentNativeToolAvailabilityStatus.AVAILABLE, "Fixture ready", 99)))
        assertNotEquals(before.availableCatalog().manifest.sha256, after.availableCatalog().manifest.sha256)
        assertEquals(before.registeredContractCatalog().manifest, after.registeredContractCatalog().manifest)
        val tool = JSONObject(before.registeredContractCatalog().manifest.json).getJSONArray("tools").getJSONObject(0)
        assertFalse(tool.has("availability"))
        assertEquals("READ_ONLY", tool.getString("effect"))
        assertFalse(tool.getBoolean("requires_effect_claim"))
    }

    @Test fun bindingDoesNotRunAvailabilityProvidersOrInventReadiness() {
        var probes = 0
        val registry = registry(availability = AgentNativeToolAvailabilityProvider {
            probes++
            AgentNativeToolAvailability(AgentNativeToolAvailabilityStatus.UNAVAILABLE, "Fixture offline")
        })
        repeat(3) { registry.registeredContractCatalog() }
        assertEquals(0, probes)
        assertTrue(registry.availableCatalog().descriptors.isEmpty())
        assertEquals(1, probes)
        val blocked = registry.invoke(descriptor.id, emptyMap())
        assertEquals("tool_unavailable", blocked.error?.code)
        assertEquals(false, blocked.error?.details?.get("executed"))
    }

    @Test fun everyExecutableContractDimensionRemainsBound() {
        val original = registry().registeredContractCatalog().manifest.sha256
        val changes = listOf(
            descriptor.copy(version = "2.0.0"), descriptor.copy(title = "Changed title"),
            descriptor.copy(description = "Changed meaning"), descriptor.copy(location = AgentNativeToolLocation.DESKTOP),
            descriptor.copy(inputSchema = AgentNativeJsonSchema.objectSchema(mapOf("url" to AgentNativeJsonSchema.string()))),
            descriptor.copy(outputSchema = AgentNativeJsonSchema.objectSchema(mapOf("text" to AgentNativeJsonSchema.string()))),
            descriptor.copy(risk = AgentNativeToolRisk.MEDIUM, concurrency = AgentNativeToolConcurrency.SERIAL),
            descriptor.copy(capabilities = setOf("different-capability")),
            descriptor.copy(requiredPermissions = listOf(AgentNativePermissionRequirement("fixture-permission"))),
            descriptor.copy(requiredConsents = listOf(AgentNativeConsentRequirement("fixture-consent"))),
            descriptor.copy(timeoutMillis = descriptor.timeoutMillis + 1),
            descriptor.copy(timeoutPolicy = AgentNativeToolTimeoutPolicy.PROGRESS_AWARE),
            descriptor.copy(idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT,
                concurrency = AgentNativeToolConcurrency.SERIAL),
            descriptor.copy(concurrency = AgentNativeToolConcurrency.SERIAL),
            descriptor.copy(effect = AgentNativeToolEffect.MUTATION, concurrency = AgentNativeToolConcurrency.SERIAL))
        for (changed in changes) assertNotEquals(changed.toString(), original,
            registry(changed).registeredContractCatalog().manifest.sha256)
    }

    @Test fun fullRegisteredViewIsBoundButRegistrationOrderIsNot() {
        val first = AgentNativeToolDefinition(descriptor, AgentNativeToolExecutor { error("No execution") })
        val second = AgentNativeToolDefinition(descriptor.copy(id = "public.browser.second"),
            AgentNativeToolExecutor { error("No execution") })
        val complete = AgentNativeToolRegistry().registerAll(listOf(first, second))
        assertEquals(complete.registeredContractCatalog().manifest,
            AgentNativeToolRegistry().registerAll(listOf(second, first)).registeredContractCatalog().manifest)
        assertNotEquals(complete.registeredContractCatalog().manifest.sha256,
            complete.subset { it.id == first.descriptor.id }.registeredContractCatalog().manifest.sha256)
    }
}
