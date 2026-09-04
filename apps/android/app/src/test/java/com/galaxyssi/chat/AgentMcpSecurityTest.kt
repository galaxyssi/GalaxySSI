package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentMcpSecurityTest {
    @Test
    fun annotationsAndNamesProduceConservativeRiskAndPermissions() {
        val read = AgentMcpToolSecurityPolicy.assess(
            tool("get_weather", readOnly = true),
            mapOf("city" to "Shanghai"),
            AgentMcpTransportKind.STREAMABLE_HTTP
        )
        assertEquals(AgentMcpToolRisk.LOW, read.risk)
        assertTrue("mcp.network.connect" in read.permissions)

        val destructive = AgentMcpToolSecurityPolicy.assess(
            tool("delete_project", destructive = true),
            mapOf("project_path" to "/work", "api_token" to "secret-value"),
            AgentMcpTransportKind.LOCAL_STDIO
        )
        assertEquals(AgentMcpToolRisk.HIGH, destructive.risk)
        assertTrue("mcp.destructive" in destructive.permissions)
        assertTrue("mcp.files.access" in destructive.permissions)
        assertTrue("mcp.secrets.use" in destructive.permissions)
        assertEquals("[REDACTED]", destructive.parameterPreview["api_token"])
    }

    @Test
    fun permissionMatrixDoesNotGateHighRiskCalls() {
        val high = AgentMcpToolSecurityPolicy.assess(
            tool("delete_account", destructive = true),
            emptyMap(),
            AgentMcpTransportKind.STREAMABLE_HTTP
        )
        assertTrue(AgentMcpToolSecurityPolicy.decide(
            AgentMcpPermissionMode.ASK_FOR_CHANGES, high, explicitlyApproved = false
        ).allowed)
        assertTrue(AgentMcpToolSecurityPolicy.decide(
            AgentMcpPermissionMode.ASK_FOR_CHANGES, high, explicitlyApproved = true
        ).allowed)
        assertTrue(AgentMcpToolSecurityPolicy.decide(
            AgentMcpPermissionMode.TRUSTED, high, explicitlyApproved = false
        ).allowed)
        assertTrue(AgentMcpToolSecurityPolicy.decide(
            AgentMcpPermissionMode.TRUSTED, high, explicitlyApproved = true
        ).allowed)
    }

    @Test
    fun permissionModesDoNotGateMediumChanges() {
        val medium = AgentMcpToolSecurityPolicy.assess(
            tool("update_document", readOnly = false),
            mapOf("content" to "updated"),
            AgentMcpTransportKind.STREAMABLE_HTTP
        )
        assertTrue(AgentMcpToolSecurityPolicy.decide(
            AgentMcpPermissionMode.ASK_FOR_CHANGES, medium, explicitlyApproved = false
        ).allowed)
        assertTrue(AgentMcpToolSecurityPolicy.decide(
            AgentMcpPermissionMode.ASK_FOR_CHANGES, medium, explicitlyApproved = true
        ).allowed)
        assertTrue(AgentMcpToolSecurityPolicy.decide(
            AgentMcpPermissionMode.TRUSTED, medium, explicitlyApproved = false
        ).allowed)
        assertTrue(AgentMcpToolSecurityPolicy.decide(
            AgentMcpPermissionMode.READ_ONLY, medium, explicitlyApproved = true
        ).allowed)
    }

    @Test
    fun parameterPreviewRedactsNestedInlineAndUrlSecrets() {
        val sanitized = AgentMcpParameterRedactor.sanitize(mapOf(
            "password" to "secret-value",
            "nested" to mapOf(
                "authorization" to "Bearer abcdefghijklmnop",
                "url" to "https://example.test/action?token=secret#fragment",
                "note" to "token=inline-secret"
            )
        ))
        val serialized = AgentNativeJsonCodec.stringify(sanitized)
        assertFalse(serialized.contains("secret-value"))
        assertFalse(serialized.contains("abcdefghijklmnop"))
        assertFalse(serialized.contains("inline-secret"))
        assertFalse(serialized.contains("fragment"))
        val error = AgentMcpParameterRedactor.sanitizeText(
            "token=inline-secret at https://example.test/mcp?api_key=secret"
        )
        assertFalse(error.contains("inline-secret"))
        assertFalse(error.contains("api_key=secret"))
    }

    @Test
    fun inMemoryAuditIsBoundedFilteredAndNewestFirst() {
        val store = InMemoryAgentMcpAuditStore()
        repeat(3) { index ->
            store.append(record(
                auditId = "audit-$index",
                connectionId = if (index < 2) "one" else "two",
                timestampMillis = index.toLong()
            ))
        }
        assertEquals(listOf("audit-1", "audit-0"), store.list("one").map(AgentMcpAuditRecord::auditId))
        assertEquals("audit-2", store.list(limit = 1).single().auditId)
        assertEquals(2, store.clear("one"))
        assertEquals(1, store.list().size)
    }

    @Test
    fun provisionalRiskKeepsPlannerConservative() {
        assertEquals(AgentMcpToolRisk.LOW, AgentMcpToolSecurityPolicy.provisionalRisk("get_status"))
        assertEquals(AgentMcpToolRisk.MEDIUM, AgentMcpToolSecurityPolicy.provisionalRisk("control_relay"))
        assertEquals(AgentMcpToolRisk.HIGH, AgentMcpToolSecurityPolicy.provisionalRisk("delete_device"))
    }

    private fun tool(
        name: String,
        readOnly: Boolean? = null,
        destructive: Boolean? = null
    ) = AgentMcpTool(
        name = name,
        title = null,
        description = null,
        inputSchema = McpJsonObject.of(),
        outputSchema = null,
        annotations = McpJsonObject.of(
            "readOnlyHint" to readOnly,
            "destructiveHint" to destructive
        ),
        raw = McpJsonObject.of("name" to name)
    )

    private fun record(
        auditId: String,
        connectionId: String,
        timestampMillis: Long
    ) = AgentMcpAuditRecord(
        auditId = auditId,
        timestampMillis = timestampMillis,
        connectionId = connectionId,
        connectionName = "Connection",
        toolName = "get_status",
        transport = "streamable_http",
        source = "android-mcp:$connectionId",
        callerId = "test",
        taskId = "task",
        conversationId = "conversation",
        risk = "low",
        permissions = listOf("mcp.data.read"),
        permissionMode = "read_only",
        permissionDecision = "allowed_read_only",
        parameterPreview = emptyMap(),
        inputSha256 = "a".repeat(64),
        status = "succeeded",
        durationMillis = 1L
    )
}
