package com.galaxyssi.chat

import java.util.Base64
import org.junit.Assert.*
import org.junit.Test

class AgentToolDiscoveryToolsTest {
    private fun descriptor(id: String) = AgentNativeToolDescriptor(id, "1.0.0", "Public browser tool",
        "Inspect a public browser page", AgentNativeToolLocation.APPLICATION,
        AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW,
        effect = AgentNativeToolEffect.READ_ONLY)
    private val fixture = (1..103).map { descriptor("public.browser.${it.toString().padStart(3, '0')}") }

    @Test fun paginatesTheEntireSearchInStableOrderWithoutTruncatingTheTail() {
        var input: AgentNativeJsonObject = mapOf("query" to "browser", "limit" to 17)
        val ids = mutableListOf<String>()
        do {
            val result = AgentToolDiscoveryTools.page(fixture.reversed(), input)
            assertTrue(result.isSuccess)
            val page = result.output["tools"] as List<*>
            assertTrue(page.size <= 17)
            ids += page.map { (it as Map<*, *>)["id"].toString() }
            input = result.output["next_cursor"]?.let { mapOf("query" to "browser", "limit" to 17, "cursor" to it) }
                ?: emptyMap()
        } while (input.isNotEmpty())
        assertEquals(fixture.map { it.id }, ids)
        assertEquals(ids.size, ids.toSet().size)
    }

    @Test fun unavailableToolsRemainDiscoverableWithoutExecutionOrAutomaticInstallation() {
        var executions = 0
        val target = descriptor("public.browser.target").copy(availability = AgentNativeToolAvailability(
            AgentNativeToolAvailabilityStatus.REQUIRES_SETUP, "Public browser pack is absent"))
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(target,
            AgentNativeToolExecutor { executions++; AgentNativeToolExecutionResult.success() }))
            .register(AgentToolDiscoveryTools.definition()).register(AgentToolInspectionTools.definition())
        assertTrue(registry.availableCatalog().descriptors.none { it.id == target.id })
        val result = registry.invoke(AgentToolDiscoveryTools.ID, mapOf("query" to "browser"))
        assertTrue(result.toJson(), result.isSuccess)
        val item = (result.output["tools"] as List<*>).single() as Map<*, *>
        assertEquals(target.id, item["id"])
        assertEquals("requires_setup", (item["availability"] as Map<*, *>)["status"])
        assertEquals(false, result.output["target_executed"])
        assertEquals(0, executions)
        val blocked = registry.invoke(target.id, emptyMap())
        assertEquals("tool_unavailable", blocked.error?.code)
        assertEquals(false, blocked.error?.details?.get("goal_terminal"))
        assertEquals(false, blocked.error?.details?.get("executed"))
    }

    @Test fun excludedToolsAreNotDiscoverableEvenWhenTheOriginalRegistryKnowsThem() {
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(fixture.first(),
            AgentNativeToolExecutor { error("Discovery must not execute the target") }))
            .register(AgentToolDiscoveryTools.definition())
        val restricted = registry.subset { it.id == AgentToolDiscoveryTools.ID }
        val result = restricted.invoke(AgentToolDiscoveryTools.ID, mapOf("query" to "public.browser"))
        assertTrue(result.isSuccess)
        assertEquals(emptyList<Any>(), result.output["tools"])
    }

    @Test fun timestampsDoNotInvalidatePaginationButContractAndAvailabilityChangesDo() {
        val first = AgentToolDiscoveryTools.page(fixture, mapOf("limit" to 1))
        val input = mapOf("limit" to 1, "cursor" to first.output["next_cursor"])
        val timestamps = fixture.map { it.copy(availability = it.availability.copy(checkedAtEpochMillis = 999)) }
        assertTrue(AgentToolDiscoveryTools.page(timestamps, input).isSuccess)
        for (changed in listOf(fixture.drop(1), fixture.map { it.copy(version = "2.0.0") },
            fixture.map { it.copy(availability = AgentNativeToolAvailability(AgentNativeToolAvailabilityStatus.UNAVAILABLE)) })) {
            assertEquals("tool_catalog_changed", AgentToolDiscoveryTools.page(changed, input).error?.code)
        }
    }

    @Test fun explicitDiscoveryRefreshesAvailabilityRatherThanReusingThePromptCatalogCache() {
        var ready = false
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(fixture.first(),
            AgentNativeToolExecutor { error("Metadata only") }, availabilityProvider = AgentNativeToolAvailabilityProvider {
                if (ready) AgentNativeToolAvailability.AVAILABLE else AgentNativeToolAvailability(
                    AgentNativeToolAvailabilityStatus.REQUIRES_SETUP)
            })).register(AgentToolDiscoveryTools.definition())
        fun status(): Any? {
            val result = registry.invoke(AgentToolDiscoveryTools.ID, mapOf("query" to "public.browser"))
            return (((result.output["tools"] as List<*>).single() as Map<*, *>)["availability"] as Map<*, *>)["status"]
        }
        assertEquals("requires_setup", status())
        ready = true
        assertEquals("available", status())
    }

    @Test fun malformedChangedQueryAndForeignViewCursorsReturnRecoverableDiagnostics() {
        val first = AgentToolDiscoveryTools.page(fixture, mapOf("limit" to 1))
        val cursor = first.output["next_cursor"]
        assertEquals("tool_discovery_cursor_invalid", AgentToolDiscoveryTools.page(fixture,
            mapOf("cursor" to cursor, "query" to "changed")).error?.code)
        assertEquals("tool_catalog_changed", AgentToolDiscoveryTools.page(fixture.take(2),
            mapOf("cursor" to cursor)).error?.code)
        for (bad in listOf("invalid", Base64.getUrlEncoder().encodeToString("{}".toByteArray()), "a".repeat(1025))) {
            val result = AgentToolDiscoveryTools.page(fixture, mapOf("cursor" to bad))
            assertEquals("tool_discovery_cursor_invalid", result.error?.code)
            assertEquals(false, result.error?.details?.get("goal_terminal"))
        }
    }

    @Test fun unicodeQueryProducesABoundedCursorAndEmptySearchIsComplete() {
        val query = "\u6d4b".repeat(256)
        val catalog = fixture.take(2).map { it.copy(description = query.repeat(3)) }
        val first = AgentToolDiscoveryTools.page(catalog, mapOf("query" to query, "limit" to 1))
        val cursor = first.output["next_cursor"].toString()
        assertTrue(cursor.length <= 1024)
        assertTrue(AgentToolDiscoveryTools.page(catalog, mapOf("query" to query, "cursor" to cursor)).isSuccess)
        val empty = AgentToolDiscoveryTools.page(fixture, mapOf("query" to "not-present"))
        assertEquals(0, empty.output["total_matches"])
        assertFalse(empty.output.containsKey("next_cursor"))
        assertTrue(((first.output["tools"] as List<*>).single() as Map<*, *>)["description_truncated"] as Boolean)
    }

    @Test fun discoveryIsReadOnlyAndIncludedInBothOrdinaryPhoneExecutionModes() {
        assertFalse(AgentToolDiscoveryTools.definition().descriptor.requiresEffectClaim)
        assertTrue(AgentToolDiscoveryTools.ID in LocalModelAgentToolPolicy.toolIds)
        assertTrue(AgentPhoneDevelopmentPolicy.isPhoneDevelopmentTool(AgentToolDiscoveryTools.ID))
        assertTrue(PhoneAssistantToolPolicy.allowsRemotePhoneTool(AgentToolDiscoveryTools.ID))
    }
}
