package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentCapabilityCatalogTest {
    @Test
    fun catalogIdsAreStableAndUnique() {
        val mcp = AgentDefaultCapabilityCatalog.mcpEntries
        val skills = AgentDefaultCapabilityCatalog.skillEntries

        assertTrue(mcp.size >= 4)
        assertTrue(skills.size >= 5)
        assertEquals(mcp.size, mcp.map { it.id }.distinct().size)
        assertEquals(skills.size, skills.map { it.id }.distinct().size)
        assertTrue(mcp.any { it.requiresPackage })
        assertTrue(skills.any { it.requiredMcpCatalogIds.isNotEmpty() })
    }

    @Test
    fun marketplaceUnifiesBuiltInToolsMcpAndAutomationState() {
        val nativeTool = AgentNativeToolDescriptor(
            id = AgentMcpNativeTools.CALL_TOOL,
            version = "1.0.0",
            title = "Call MCP tool",
            description = "Calls one explicitly configured MCP tool",
            location = AgentNativeToolLocation.APPLICATION,
            inputSchema = AgentNativeJsonSchema.objectSchema(),
            outputSchema = AgentNativeJsonSchema.objectSchema(),
            risk = AgentNativeToolRisk.MEDIUM
        )
        val registry = AgentMcpRegistry(InMemoryAgentMcpStore()) { 1_000L }

        val initial = AgentDefaultCapabilityCatalog.marketplaceItems(
            listOf(nativeTool),
            registry.list(),
            emptyList(),
            1_000L
        )

        assertEquals(
            AgentMarketplaceInstallState.BUILT_IN,
            initial.single { it.id == AgentMcpNativeTools.CALL_TOOL }.installState
        )
        assertEquals(
            AgentMarketplaceInstallState.AVAILABLE,
            initial.single { it.id == "galaxyssi.mcp.github" }.installState
        )
        assertTrue(
            initial.single { it.id == "galaxyssi.mcp.github" }
                .permissionDiff.requiresApproval
        )
        assertTrue(
            initial.single { it.id == "galaxyssi.mcp.github" }
                .capabilities.contains("github.repositories")
        )
        assertEquals(
            AgentMarketplaceInstallState.NEEDS_SETUP,
            initial.single { it.id == "galaxyssi.catalog.github-triage" }.installState
        )

        registry.addRemote(
            "GitHub",
            "https://api.githubcopilot.com/mcp/",
            AgentMcpAuthProfile(AgentMcpAuthMethod.NONE),
            catalogId = "galaxyssi.mcp.github",
            id = "github"
        )
        val ready = AgentDefaultCapabilityCatalog.marketplaceItems(
            listOf(nativeTool),
            registry.list(),
            emptyList(),
            1_000L
        )

        assertEquals(
            AgentMarketplaceInstallState.INSTALLED,
            ready.single { it.id == "galaxyssi.mcp.github" }.installState
        )
        assertTrue(ready.single { it.id == "galaxyssi.mcp.github" }.revocable)
        assertFalse(
            ready.single { it.id == "galaxyssi.mcp.github" }
                .permissionDiff.requiresApproval
        )
        assertEquals(
            AgentMarketplaceInstallState.AVAILABLE,
            ready.single { it.id == "galaxyssi.catalog.github-triage" }.installState
        )
    }

    @Test
    fun marketplaceReportsAutomationRollbackVersionsAndPermissionChanges() {
        val entry = AgentDefaultCapabilityCatalog.skillEntries
            .single { it.id == "galaxyssi.catalog.device-health" }
        val previous = AgentSkillInstallation(
            entry.manifest.copy(
                version = "0.9.0",
                permissions = emptySet(),
                nativeTools = entry.manifest.nativeTools - AgentHardwareNativeTools.NETWORK_STATUS
            ),
            enabled = false
        )
        val current = AgentSkillInstallation(entry.manifest, enabled = true)

        val item = AgentDefaultCapabilityCatalog.marketplaceItems(
            nativeTools = emptyList(),
            installedMcp = emptyList(),
            installedAutomations = listOf(previous, current)
        ).single { it.id == entry.id }

        assertEquals("1.0.0", item.installedVersion)
        assertEquals(listOf("0.9.0"), item.rollbackVersions)
        assertTrue(item.revocable)
        assertFalse(item.permissionDiff.requiresApproval)
    }

    @Test
    fun dynamicAuthenticationAdvancesStepsAndExpiresWithoutLosingRefreshWindow() {
        var now = 1_000L
        val store = InMemoryAgentMcpStore()
        val registry = AgentMcpRegistry(store) { now }
        val profile = AgentMcpAuthProfile(
            method = AgentMcpAuthMethod.DYNAMIC,
            steps = AgentMcpAuthProfile.defaultSteps(AgentMcpAuthMethod.DYNAMIC),
            accessTokenTtlMillis = 10_000L,
            refreshLeadMillis = 2_000L,
            supportsRefresh = true
        )
        val connection = registry.addRemote("Relay", "https://relay.example/mcp", profile, id = "relay-1")

        assertEquals(AgentMcpAuthState.NOT_CONFIGURED, connection.authState)
        assertEquals("credentials", registry.beginAuthentication(connection.id)?.id)
        assertThrows(IllegalArgumentException::class.java) {
            registry.submitAuthenticationStep(connection.id, mapOf("username" to "operator"))
        }

        val challenge = registry.submitAuthenticationStep(
            connection.id,
            mapOf("username" to "operator", "password" to "secret")
        )
        assertEquals(AgentMcpAuthState.CHALLENGE_REQUIRED, challenge.authState)
        assertEquals("verification", challenge.currentAuthStep?.id)

        val authenticated = registry.submitAuthenticationStep(
            connection.id,
            mapOf("otp" to "123456", "access_token" to "session-token")
        )
        assertEquals(AgentMcpAuthState.AUTHENTICATED, authenticated.authState)
        assertEquals("Bearer session-token", registry.requestHeaders(connection.id)["Authorization"])
        assertTrue(authenticated.isCallable(now))

        now = authenticated.refreshAtMillis
        assertEquals(AgentMcpAuthState.REFRESHING, registry.get(connection.id)?.effectiveAuthState(now))
        assertTrue(registry.get(connection.id)!!.isCallable(now))

        now = authenticated.expiresAtMillis
        assertEquals(AgentMcpAuthState.REAUTHENTICATION_REQUIRED, registry.get(connection.id)?.effectiveAuthState(now))
        assertFalse(registry.get(connection.id)!!.isCallable(now))
    }

    @Test
    fun connectionCodecPreservesDynamicExchangeWithoutSecrets() {
        val exchange = AgentMcpAuthExchangeSpec(
            method = "POST",
            pathTemplate = "/api/login",
            bodyTemplate = "{\"username\":{{field.username}}}",
            responseMappings = mapOf("access_token" to "$.token"),
            acceptedStatusCodes = setOf(200, 201)
        )
        val connection = AgentMcpConnection(
            id = "codec-1",
            displayName = "Codec",
            endpoint = "https://codec.example/mcp",
            distribution = AgentMcpDistribution.LOCAL_PACKAGE,
            transport = AgentMcpTransportKind.DECLARATIVE_HTTP,
            authProfile = AgentMcpAuthProfile(
                AgentMcpAuthMethod.DYNAMIC,
                steps = listOf(
                    AgentMcpAuthStepSpec(
                        "login",
                        "Sign in",
                        fields = listOf(AgentMcpAuthFieldSpec("username", "Username", AgentMcpAuthFieldType.TEXT)),
                        exchange = exchange
                    )
                )
            ),
            authState = AgentMcpAuthState.CHALLENGE_REQUIRED,
            permissionMode = AgentMcpPermissionMode.READ_ONLY
        )

        val decoded = AgentMcpConnectionCodec.decode(AgentMcpConnectionCodec.encode(listOf(connection))).single()

        assertEquals(connection.id, decoded.id)
        assertEquals("/api/login", decoded.currentAuthStep?.exchange?.pathTemplate)
        assertEquals("$.token", decoded.currentAuthStep?.exchange?.responseMappings?.get("access_token"))
        assertEquals(setOf(200, 201), decoded.currentAuthStep?.exchange?.acceptedStatusCodes)
        assertEquals(AgentMcpPermissionMode.READ_ONLY, decoded.permissionMode)
        assertFalse(AgentMcpConnectionCodec.encode(listOf(connection)).contains("session-token"))
    }

    @Test
    fun skillDependencyResolverRequiresReadyMcpAndNativeTools() {
        val skill = AgentDefaultCapabilityCatalog.skill("galaxyssi.catalog.github-triage")!!
        val registry = AgentMcpRegistry(InMemoryAgentMcpStore()) { 1_000L }
        val missing = AgentCapabilityDependencyResolver.resolve(
            skill,
            registry.list(),
            setOf(AgentMcpNativeTools.CALL_TOOL),
            1_000L
        )
        assertFalse(missing.available)
        assertEquals(setOf("galaxyssi.mcp.github"), missing.missingMcpCatalogIds)

        val connection = registry.addRemote(
            "GitHub",
            "https://api.githubcopilot.com/mcp/",
            AgentMcpAuthProfile(AgentMcpAuthMethod.NONE),
            catalogId = "galaxyssi.mcp.github",
            id = "github"
        )
        assertNotNull(connection)
        val ready = AgentCapabilityDependencyResolver.resolve(
            skill,
            registry.list(),
            setOf(AgentMcpNativeTools.CALL_TOOL),
            1_000L
        )
        assertTrue(ready.available)
    }

    @Test
    fun endpointPolicyRejectsEmbeddedCredentialsAndUnsupportedSchemes() {
        assertEquals("https://example.com/mcp", AgentMcpEndpointPolicy.normalize(" https://example.com/mcp "))
        assertThrows(IllegalArgumentException::class.java) {
            AgentMcpEndpointPolicy.normalize("https://user:password@example.com/mcp")
        }
        assertThrows(IllegalArgumentException::class.java) {
            AgentMcpEndpointPolicy.normalize("file:///tmp/server")
        }
    }
}
