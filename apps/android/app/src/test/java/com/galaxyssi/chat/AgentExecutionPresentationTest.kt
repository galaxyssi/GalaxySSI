package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentExecutionPresentationTest {
    @Test
    fun desktopTargetSeparatesExecutorFromComputer() {
        val presentation = AgentExecutionPresentationPolicy.local(
            routeKind = AgentRouteKind.DESKTOP_AGENT,
            targetTitle = "Codex \u00b7 WORKSTATION",
            selectedAgentOrModel = "",
            phase = AgentPhase.EXECUTING,
            currentStep = "Reading files",
            startedAtMillis = 1_000L
        )

        assertEquals("Codex", presentation.executorLabel)
        assertEquals("WORKSTATION", presentation.locationLabelHint)
        assertEquals(AgentExecutionLocationKind.DESKTOP, presentation.locationKind)
        assertTrue(presentation.cancellable)
    }

    @Test
    fun localAndCloudLocationsRemainDistinct() {
        val phone = AgentExecutionPresentationPolicy.local(
            AgentRouteKind.LOCAL_SYSTEM,
            "",
            "",
            AgentPhase.EXECUTING,
            "Reading battery",
            1_000L
        )
        val cloud = AgentExecutionPresentationPolicy.local(
            AgentRouteKind.CLOUD_MODEL,
            "DeepSeek",
            "",
            AgentPhase.WAITING_RESPONSE,
            "Waiting for model",
            1_000L
        )

        assertEquals(AgentExecutionLocationKind.PHONE, phone.locationKind)
        assertEquals("GalaxySSI", phone.executorLabel)
        assertEquals(AgentExecutionLocationKind.PHONE, cloud.locationKind)
        assertEquals(AgentExecutionRuntimeKind.PHONE_CLOUD_API, cloud.runtimeKind)
        assertEquals("DeepSeek", cloud.executorLabel)
    }

    @Test
    fun phoneCloudApiRemainsPhoneHosted() {
        val presentation = AgentExecutionPresentationPolicy.local(
            route = AgentRoute(
                kind = AgentRouteKind.CLOUD_MODEL,
                targetId = "deepseek",
                targetTitle = "DeepSeek",
                deliveryMode = "mobile_cloud_api",
                executionLocationKind = AgentExecutionLocationKind.PHONE,
                executionRuntimeKind = AgentExecutionRuntimeKind.PHONE_CLOUD_API
            ),
            action = AgentAction(
                id = "cloud",
                kind = AgentActionKind.CALL_CONNECTOR,
                target = "DeepSeek",
                risk = AgentRisk.LOW,
                status = AgentActionStatus.WAITING_RESPONSE,
                description = "Ask DeepSeek"
            ),
            selectedAgentOrModel = "DeepSeek",
            phase = AgentPhase.WAITING_RESPONSE,
            currentStep = "Waiting for model",
            startedAtMillis = 1_000L
        )

        assertEquals(AgentExecutionLocationKind.PHONE, presentation.locationKind)
        assertEquals(AgentExecutionRuntimeKind.PHONE_CLOUD_API, presentation.runtimeKind)
    }

    @Test
    fun supervisedModelPlanningIsPresentedAsPhoneExecution() {
        val action = AgentAction(
            id = "supervise-phone-project",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.WAITING_RESPONSE,
            description = "Plan phone workspace actions",
            parameters = mapOf(
                "connector_id" to "codex",
                "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE
            )
        )

        val location = AgentExecutionPresentationPolicy.location(
            route = AgentRoute(
                kind = AgentRouteKind.DESKTOP_AGENT,
                targetId = "codex",
                targetTitle = "Codex \u00b7 WORKSTATION"
            ),
            action = action
        )

        assertEquals(AgentExecutionLocationKind.PHONE, location.locationKind)
        assertEquals(AgentExecutionRuntimeKind.PHONE_NATIVE, location.runtimeKind)
        assertEquals("galaxyssi-supervised-project", location.runtimeId)
    }

    @Test
    fun phoneLinuxIsDerivedFromValidatedToolIdentity() {
        val location = AgentExecutionPresentationPolicy.location(
            route = AgentRoute(kind = AgentRouteKind.LOCAL_SYSTEM),
            action = AgentAction(
                id = "runtime",
                kind = AgentActionKind.CALL_NATIVE_TOOL,
                target = "Phone Linux",
                risk = AgentRisk.MEDIUM,
                status = AgentActionStatus.RUNNING,
                description = "Run Python",
                parameters = mapOf("tool_id" to AgentOnDeviceRuntimeTools.EXECUTE)
            )
        )

        assertEquals(AgentExecutionLocationKind.PHONE, location.locationKind)
        assertEquals(AgentExecutionRuntimeKind.PHONE_LINUX, location.runtimeKind)
        assertEquals(AgentOnDeviceRuntimeTools.EXECUTE, location.runtimeId)
    }

    @Test
    fun phoneNativeToolRemainsPhoneHostedWhenDesktopAgentProvidesReasoning() {
        val location = AgentExecutionPresentationPolicy.location(
            route = AgentRoute(
                kind = AgentRouteKind.DESKTOP_AGENT,
                targetId = "codex",
                targetTitle = "Codex \u00b7 WORKSTATION"
            ),
            action = AgentAction(
                id = "inspect-phone-runtime",
                kind = AgentActionKind.CALL_NATIVE_TOOL,
                target = "Phone runtime",
                risk = AgentRisk.LOW,
                status = AgentActionStatus.RUNNING,
                description = "Inspect the phone runtime",
                parameters = mapOf("tool_id" to "galaxyssi.runtime.inspect")
            )
        )

        assertEquals(AgentExecutionLocationKind.PHONE, location.locationKind)
        assertEquals(AgentExecutionRuntimeKind.PHONE_NATIVE, location.runtimeKind)
        assertEquals("galaxyssi.runtime.inspect", location.runtimeId)
    }

    @Test
    fun desktopNativeToolUsesDesktopExecutionHost() {
        val route = AgentRouteResolver.resolve(
            action = AgentAction(
                id = "desktop-file",
                kind = AgentActionKind.CALL_NATIVE_TOOL,
                target = "Read Desktop workspace text",
                risk = AgentRisk.LOW,
                status = AgentActionStatus.RUNNING,
                description = "Read a Desktop file",
                parameters = mapOf(
                    "tool_id" to AgentDesktopRemoteNativeTools.FILE_READ_TEXT,
                    "_galaxyssi_native_tool_location" to AgentNativeToolLocation.DESKTOP.wireValue,
                    "_galaxyssi_execution_device_id" to "desktop-1"
                )
            ),
            targets = emptyList()
        )

        assertEquals(AgentRouteKind.LOCAL_SYSTEM, route.kind)
        assertEquals(AgentExecutionLocationKind.DESKTOP, route.executionLocationKind)
        assertEquals(AgentExecutionRuntimeKind.DESKTOP_TOOL, route.executionRuntimeKind)
        assertEquals("desktop-1", route.executionDeviceId)
    }

    @Test
    fun pairedDesktopContractProducesTrustedDesktopLocation() {
        val presentation = AgentExecutionPresentationPolicy.remote(
            executorId = "codex",
            executorLabel = "Codex",
            locationKind = "desktop",
            locationId = "desktop-1",
            locationName = "WORKSTATION",
            runtimeKind = "desktop_agent",
            runtimeId = "codex",
            contract = AgentExecutionLocationContract.VERSION,
            status = "running",
            currentStep = "Reading files",
            startedAtMillis = 1_000L,
            completedAtMillis = 0L,
            advertisedCancellable = true
        )

        assertEquals(AgentExecutionLocationKind.DESKTOP, presentation.locationKind)
        assertEquals(AgentExecutionRuntimeKind.DESKTOP_AGENT, presentation.runtimeKind)
        assertEquals("codex", presentation.runtimeId)
        assertTrue(presentation.locationTrusted)
    }

    @Test
    fun remotePayloadCannotClaimPhoneExecution() {
        val presentation = AgentExecutionPresentationPolicy.remote(
            executorId = "codex",
            executorLabel = "Codex",
            locationKind = "phone",
            locationId = "phone-1",
            locationName = "This phone",
            runtimeKind = "phone_native",
            contract = AgentExecutionLocationContract.VERSION,
            status = "running",
            currentStep = "Running",
            startedAtMillis = 1_000L,
            completedAtMillis = 0L,
            advertisedCancellable = true
        )

        assertEquals(AgentExecutionLocationKind.DESKTOP, presentation.locationKind)
        assertEquals(AgentExecutionRuntimeKind.DESKTOP_AGENT, presentation.runtimeKind)
        assertFalse(presentation.locationTrusted)
    }

    @Test
    fun desktopLocalModelUsesDesktopExecutionHost() {
        val route = AgentRouteResolver.resolve(
            action = AgentAction(
                id = "local-model",
                kind = AgentActionKind.CALL_CONNECTOR,
                target = "Local LLM",
                risk = AgentRisk.LOW,
                status = AgentActionStatus.WAITING_RESPONSE,
                description = "Ask local model",
                parameters = mapOf("connector_id" to "local-llm")
            ),
            targets = listOf(
                AgentCallableTarget(
                    id = "local-llm",
                    title = "Local LLM",
                    kind = AgentConnectorKind.MODEL,
                    status = AgentConnectorStatus.AVAILABLE,
                    capabilities = listOf(AgentCapability.LOCAL_INFERENCE),
                    failureDomain = "desktop-1"
                )
            )
        )

        assertEquals(AgentRouteKind.LOCAL_MODEL, route.kind)
        assertEquals(AgentExecutionLocationKind.DESKTOP, route.executionLocationKind)
        assertEquals(AgentExecutionRuntimeKind.DESKTOP_AGENT, route.executionRuntimeKind)
        assertEquals("desktop-1", route.executionDeviceId)
    }

    @Test
    fun remoteTerminalStateCannotAdvertiseCancellation() {
        val completed = AgentExecutionPresentationPolicy.remote(
            executorId = "codex",
            executorLabel = "Codex",
            locationKind = "desktop",
            locationName = "WORKSTATION",
            status = "completed",
            currentStep = "",
            startedAtMillis = 1_000L,
            completedAtMillis = 2_000L,
            advertisedCancellable = true
        )

        assertFalse(completed.cancellable)
        assertEquals(AgentPhase.COMPLETED, completed.phase)
    }
}
