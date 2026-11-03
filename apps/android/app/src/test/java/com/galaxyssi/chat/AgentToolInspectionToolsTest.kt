package com.galaxyssi.chat

import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class AgentToolInspectionToolsTest {
    private val executions = AtomicInteger()
    private val schema = AgentNativeJsonSchema.objectSchema(properties = mapOf(
        "source" to AgentNativeJsonSchema.string(minLength = 1, description = "Code to execute")),
        required = setOf("source"), additionalProperties = false)

    @Test fun describesTheCompleteInputContractWithoutExecutingTheTarget() {
        val result = registry().invoke(AgentToolInspectionTools.DESCRIBE, mapOf("tool_id" to "test.execute"))
        assertTrue(result.toJson(), result.isSuccess)
        assertEquals(schema.document, result.output["definition"])
        assertEquals(0, executions.get())
    }

    @Test fun canReadFieldInstructionsOrUsageDescription() {
        val registry = registry()
        val field = registry.invoke(AgentToolInspectionTools.DESCRIBE,
            mapOf("tool_id" to "test.execute", "schema_path" to "/input_schema/properties/source/description"))
        assertTrue(field.isSuccess)
        assertEquals("Code to execute", field.output["definition"])
        val usage = registry.invoke(AgentToolInspectionTools.DESCRIBE,
            mapOf("tool_id" to "test.execute", "schema_path" to "/description"))
        assertEquals("Execute test code", usage.output["definition"])
    }

    @Test fun restrictedRegistryCannotDescribeAnExcludedTool() {
        val restricted = registry().subset { it.id == AgentToolInspectionTools.DESCRIBE }
        val result = restricted.invoke(AgentToolInspectionTools.DESCRIBE, mapOf("tool_id" to "test.execute"))
        assertEquals("tool_not_disclosed", result.error?.code)
        assertTrue(result.output.isEmpty())
        assertEquals(0, executions.get())
    }

    @Test fun missingToolsStayHiddenButUnavailableRegisteredContractsSupportDiagnosis() {
        val registry = registry(AgentNativeToolAvailability(AgentNativeToolAvailabilityStatus.UNAVAILABLE, "Not ready"))
        val missing = registry.invoke(AgentToolInspectionTools.DESCRIBE, mapOf("tool_id" to "test.missing"))
        val unavailable = registry.invoke(AgentToolInspectionTools.DESCRIBE, mapOf("tool_id" to "test.execute"))
        assertEquals("tool_not_disclosed", missing.error?.code)
        assertTrue(unavailable.isSuccess)
        assertEquals(schema.document, unavailable.output["definition"])
        assertEquals(false, unavailable.output["target_executed"])
        assertEquals("unavailable", (unavailable.output["availability"] as Map<*, *>)["status"])
        assertEquals(0, executions.get())
        assertEquals("tool_unavailable", registry.invoke("test.execute", mapOf("source" to "public")).error?.code)
        assertEquals(0, executions.get())
    }

    @Test fun invalidPointersProduceDiagnosticFailures() {
        for (path in listOf("source", "/input_schema/missing", "/input_schema/~2bad")) {
            val result = registry().invoke(AgentToolInspectionTools.DESCRIBE,
                mapOf("tool_id" to "test.execute", "schema_path" to path))
            assertEquals(path, "schema_path_not_found", result.error?.code)
        }
    }

    @Test fun jsonPointersSupportEscapedKeysAndArrayEntries() {
        val document = mapOf("a/b" to mapOf("~key" to listOf("first", "second")))
        assertEquals("second", AgentToolInspectionTools.select(document, "/a~1b/~0key/1"))
        assertEquals(document, AgentToolInspectionTools.select(document, ""))
        for (path in listOf("/a~1b/~0key/-1", "/a~1b/~0key/01", "/a~1b/~0key/9")) {
            assertThrows(Exception::class.java) { AgentToolInspectionTools.select(document, path) }
        }
    }

    @Test fun inspectionIsReadOnlyAndAllowedInBothPhonePlanningModes() {
        val tool = AgentToolInspectionTools.definition().descriptor
        assertFalse(tool.requiresEffectClaim)
        assertTrue(AgentPhoneDevelopmentPolicy.isPhoneDevelopmentTool(tool.id))
        assertTrue(PhoneAssistantToolPolicy.allowsRemotePhoneTool(tool.id))
    }

    private fun registry(availability: AgentNativeToolAvailability = AgentNativeToolAvailability.AVAILABLE) =
        AgentNativeToolRegistry().register(AgentNativeToolDefinition(
            AgentNativeToolDescriptor("test.execute", "1.0.0", "Execute test", "Execute test code",
                AgentNativeToolLocation.APPLICATION, schema, AgentNativeJsonSchema.objectSchema(),
                AgentNativeToolRisk.LOW, availability = availability),
            AgentNativeToolExecutor { executions.incrementAndGet(); AgentNativeToolExecutionResult.success() }))
            .register(AgentToolInspectionTools.definition())
}
