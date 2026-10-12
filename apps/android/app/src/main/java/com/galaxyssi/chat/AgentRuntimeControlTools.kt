package com.galaxyssi.chat

import android.content.Context

internal class AgentRuntimeControlFailure(val code: String) : IllegalStateException(code)

internal data class AgentRuntimeControlObservation(
    val instance: String,
    val engineRunning: Boolean?,
    val health: AgentRuntimeBridgeHealth?,
    val lifecycle: AgentRuntimeLifecycleSnapshot,
    val observedAtMillis: Long,
    val runtime: AgentOnDeviceRuntimeStatus? = null
) {
    fun output(): AgentNativeJsonObject = (runtime?.let(AgentOnDeviceRuntimeTools::runtimeStatusOutput) ?: emptyMap()) + mapOf(
        "runtime_instance" to instance, "observed_at_epoch_ms" to observedAtMillis,
        "engine_running" to engineRunning, "pack_integrity" to "cached_not_rehashed",
        "health_observation" to mapOf("confirmed" to (health?.observationConfirmed == true),
            "ready" to (health?.ready == true && health.observationConfirmed),
            "reason" to health?.reason.orEmpty(), "guest_api_version" to health?.guestApiVersion,
            "guest_version" to health?.guestVersion, "capabilities" to health?.capabilities.orEmpty()),
        "lifecycle" to mapOf("phase" to lifecycle.phase.wireValue, "reason" to lifecycle.reason,
            "consecutive_failures" to lifecycle.consecutiveFailures,
            "next_attempt_at_millis" to lifecycle.nextAttemptAtMillis))
}

/** Diagnostics observe, lifecycle tools execute only the model's explicit choice. */
internal object AgentRuntimeControlTools {
    const val DIAGNOSE = "galaxyssi.runtime.diagnose"
    const val CONTROL = "galaxyssi.runtime.control"
    val toolIds = setOf(DIAGNOSE, CONTROL)

    fun definitions(context: Context): List<AgentNativeToolDefinition> {
        val app = context.applicationContext
        val observe = { observe(app) }
        return definitions(observe, { operation, expected ->
            AgentOnDeviceRuntimeLifecycle.controlIfCurrent(app, operation, expected)
            observe()
        }, { block -> AgentRuntimePackMountState.tryWithMaintenance(block) })
    }

    internal fun observe(context: Context): AgentRuntimeControlObservation {
        val before = AgentOnDeviceRuntimeLifecycle.instanceIdentity()
        val status = AgentOnDeviceRuntimeManager(context).cachedStatus()
        val bridge = AgentOnDeviceRuntimeBridgeRegistry.current() ?: AgentOnDeviceRuntimeSupervisor.discover(context)
        var health = bridge?.let { candidate -> runCatching(candidate::refreshHealth).getOrElse {
            AgentRuntimeBridgeHealth(false, reason = "Guest health response was not observed", observationConfirmed = false)
        } } ?: AgentRuntimeBridgeHealth(false,
            reason = "No fresh guest health response was observed", observationConfirmed = false)
        val running = runCatching { AgentRuntimeEngineControllerRegistry.currentOrInstall(context).isRunning() }.getOrNull()
        val instance = AgentOnDeviceRuntimeLifecycle.instanceIdentity()
        if (before != instance) health = AgentRuntimeBridgeHealth(false,
            reason = "Runtime instance changed during observation; inspect again", observationConfirmed = false)
        val ready = health?.ready == true && health.observationConfirmed
        val cached = AgentOnDeviceRuntimeLifecycle.cached(context)
        val lifecycle = cached.copy(phase = when {
            status.backend == AgentOnDeviceRuntimeBackend.NONE -> AgentRuntimeLifecyclePhase.BLOCKED
            ready -> AgentRuntimeLifecyclePhase.READY
            running == false -> AgentRuntimeLifecyclePhase.STOPPED
            else -> AgentRuntimeLifecyclePhase.DEGRADED
        }, reason = when {
            status.backend == AgentOnDeviceRuntimeBackend.NONE -> status.reason
            ready -> "Guest readiness confirmed by a fresh health response"
            running == false -> "Runtime engine is stopped"
            else -> AgentRuntimeProbePolicy.unavailableReason(health)
        })
        return AgentRuntimeControlObservation(instance, running, health, lifecycle, System.currentTimeMillis(),
            status.copy(backendReady = ready && status.backend != AgentOnDeviceRuntimeBackend.NONE,
                reason = lifecycle.reason, lifecyclePhase = lifecycle.phase, lifecycleReason = lifecycle.reason))
    }

    internal fun definitions(observe: () -> AgentRuntimeControlObservation,
        control: (String, String) -> AgentRuntimeControlObservation,
        maintenance: (() -> AgentRuntimeControlObservation) -> AgentRuntimeControlObservation? = { it() }
    ): List<AgentNativeToolDefinition> = listOf(
        AgentNativeToolDefinition(AgentNativeToolDescriptor(DIAGNOSE, "1.0.0", "Diagnose the phone Linux runtime",
            "Observe a fresh guest health response, engine state and runtime_instance without starting or restarting Linux. " +
                "An unconfirmed health response is not proof of a stopped guest. Pack metadata is cached, not integrity-rehashed. " +
                "Use the observation to choose the next action; this tool does not perform a repair.",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(additionalProperties = false),
            AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW, timeoutMillis = 60_000,
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
            concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY, effect = AgentNativeToolEffect.READ_ONLY),
            AgentNativeToolExecutor { invocation ->
                invocation.checkpoint()
                invocation.reportProgress("runtime.diagnose", "Observing the phone Linux runtime")
                AgentNativeToolExecutionResult.success(observe().output(), "Runtime observation received; no repair performed")
            }, executorId = "galaxyssi.runtime_lifecycle"),
        AgentNativeToolDefinition(AgentNativeToolDescriptor(CONTROL, "1.0.0", "Control the phone Linux runtime",
            "Execute an explicit start or restart using runtime_instance from a current runtime.diagnose observation. " +
                "start never replaces a running guest, even when health is unconfirmed. restart affects the shared guest and " +
                "can lose all live browser sessions, user authentication and background process state; persistent files remain. " +
                "It does not reset the system disk or replay interrupted commands. Inspect unknown side effects before continuing. " +
                "Active commands prevent maintenance; stale instance observations must be refreshed. Choose whether restart is appropriate from evidence.",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(properties = mapOf(
                "operation" to AgentNativeJsonSchema.string(enumValues = listOf("start", "restart")),
                "expected_instance" to AgentNativeJsonSchema.string(minLength = 64, maxLength = 64)),
                required = setOf("operation", "expected_instance"), additionalProperties = false),
            AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.HIGH, timeoutMillis = 180_000,
            idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT, effect = AgentNativeToolEffect.MUTATION),
            AgentNativeToolExecutor { invocation ->
                invocation.checkpoint()
                val operation = invocation.input["operation"] as String
                val expected = invocation.input["expected_instance"] as String
                invocation.reportProgress("runtime.$operation", "Applying the selected phone Linux lifecycle operation")
                val result = try { maintenance {
                    invocation.checkpoint()
                    control(operation, expected)
                } } catch (error: AgentRuntimeControlFailure) {
                    return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(error.code,
                        if (error.code == "runtime_instance_changed")
                            "Runtime instance changed; obtain a fresh diagnosis before another lifecycle operation."
                        else "Unsupported runtime lifecycle operation; inspect the tool input contract.",
                        details = mapOf("executed" to false, "goal_terminal" to false, "diagnostic_tool" to DIAGNOSE))
                } catch (error: Exception) {
                    if (error is AgentNativeToolCancelledException || error is AgentNativeToolTimeoutException) throw error
                    return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("runtime_control_outcome_unknown",
                        "The lifecycle operation did not yield a confirmed outcome. Diagnose before choosing another action.",
                        details = mapOf("outcome_unknown" to true, "goal_terminal" to false,
                            "side_effects_replayed" to false, "diagnostic_tool" to DIAGNOSE))
                }
                if (result == null) return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure("runtime_maintenance_busy",
                    "Commands are still using this guest; no lifecycle operation was performed.",
                    details = mapOf("executed" to false, "goal_terminal" to false))
                val output = result.output() + mapOf("operation" to operation, "side_effects_replayed" to false,
                    "live_state_may_be_lost" to (operation == "restart" && result.instance != expected),
                    "workspace_files_reset" to false, "requires_observation" to true)
                if (result.health?.ready == true && result.health.observationConfirmed) {
                    AgentNativeToolExecutionResult.success(output, "Lifecycle operation observed; verify the original blocked task")
                } else AgentNativeToolExecutionResult.failure("runtime_not_ready",
                    "The guest is not confirmed ready. Diagnose the observation and choose the next action.",
                    details = mapOf("goal_terminal" to false, "diagnostic_tool" to DIAGNOSE)).copy(output = output)
            }, executorId = "galaxyssi.runtime_lifecycle"))
}
