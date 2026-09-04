package com.galaxyssi.chat

import android.content.Context

object AgentSelfEvolutionService {
    @Volatile
    private var manager: AgentSelfEvolutionManager? = null

    fun manager(context: Context): AgentSelfEvolutionManager {
        manager?.let { return it }
        return synchronized(this) {
            manager ?: context.applicationContext.let { appContext ->
                val taskStore = EncryptedAgentSelfEvolutionStore(appContext)
                val releaseStore = AgentShadowReleaseStore(appContext)
                AgentSelfEvolutionManager(
                    store = taskStore,
                    runtime = AndroidAgentSelfEvolutionRuntime(appContext),
                    eventSink = AgentSelfEvolutionEventSink { event ->
                        val eventName = event["event"]?.toString().orEmpty()
                        val taskId = (event["task"] as? Map<*, *>)?.get("task_id")?.toString().orEmpty()
                        val task = taskId.takeIf(String::isNotBlank)?.let(taskStore::get)
                            ?: return@AgentSelfEvolutionEventSink
                        when (eventName) {
                            "candidate_ready" -> if (AgentEvalOpsStore(appContext).settings().shadowReleaseEnabled) {
                                releaseStore.create(task)
                            }
                            "rolled_back", "cancelled" -> releaseStore.forEvolutionTask(task.taskId)
                                .filter { release -> release.stage !in setOf(
                                    AgentShadowReleaseStage.RELEASED,
                                    AgentShadowReleaseStage.ROLLED_BACK,
                                    AgentShadowReleaseStage.FAILED
                                ) }
                                .forEach { release ->
                                    releaseStore.update(release.id) {
                                        it.copy(
                                            stage = AgentShadowReleaseStage.ROLLED_BACK,
                                            rollbackReason = "Evolution candidate was $eventName"
                                        )
                                    }
                                }
                        }
                    }
                )
            }.also { manager = it }
        }
    }
}

object AgentSelfEvolutionNativeTools {
    const val STATUS = "galaxyssi.evolution.status"
    const val LIST = "galaxyssi.evolution.tasks.list"
    const val CREATE = "galaxyssi.evolution.tasks.create"
    const val PREPARE = "galaxyssi.evolution.candidate.prepare"
    const val APPLY_PATCH = "galaxyssi.evolution.candidate.patch"
    const val ROLLBACK = "galaxyssi.evolution.candidate.rollback"
    const val CONSENT = "galaxyssi.consent.self_evolution"

    val toolIds = setOf(STATUS, LIST, CREATE, PREPARE, APPLY_PATCH, ROLLBACK)

    fun definitions(context: Context): List<AgentNativeToolDefinition> {
        val appContext = context.applicationContext
        val manager = AgentSelfEvolutionService.manager(appContext)
        return listOf(
            definition(
                id = STATUS,
                title = "Inspect local self-evolution",
                description = "Reports Android-local evolution tasks, candidate state, and runtime readiness.",
                risk = AgentNativeToolRisk.LOW,
                input = AgentNativeJsonSchema.objectSchema(additionalProperties = false),
                execute = {
                    val runtime = AgentOnDeviceRuntimeManager(appContext).status()
                    val health = manager.health()
                    AgentNativeToolExecutionResult.success(
                        mapOf(
                            "execution_target" to "android",
                            "runtime_ready" to runtime.backendReady,
                            "runtime_reason" to runtime.reason,
                            "task_count" to health.totalTasks,
                            "active_tasks" to health.activeTasks,
                            "health" to health.publicValue()
                        ),
                        "Android-local self-evolution inspected"
                    )
                }
            ),
            definition(
                id = LIST,
                title = "List local evolution tasks",
                description = "Lists bounded Android-local evolution tasks and their immutable quality-gate receipts.",
                risk = AgentNativeToolRisk.LOW,
                input = AgentNativeJsonSchema.objectSchema(
                    properties = mapOf("limit" to AgentNativeJsonSchema.integer(1, 500)),
                    additionalProperties = false
                ),
                execute = { invocation ->
                    val limit = (invocation.input["limit"] as? Number)?.toInt()?.coerceIn(1, 500) ?: 100
                    val tasks = manager.list(limit)
                    AgentNativeToolExecutionResult.success(
                        mapOf(
                            "tasks" to tasks.map(AgentSelfEvolutionTask::publicValue),
                            "health" to manager.health().publicValue()
                        ),
                        "Android-local evolution tasks listed"
                    )
                }
            ),
            definition(
                id = CREATE,
                title = "Create a local evolution task",
                description = "Creates a scoped self-improvement task without changing source or the running app.",
                risk = AgentNativeToolRisk.LOW,
                input = AgentNativeJsonSchema.objectSchema(
                    properties = mapOf(
                        "problem" to AgentNativeJsonSchema.string(minLength = 4, maxLength = 4_000),
                        "scope" to stringArray(1, 64, 512),
                        "acceptance" to stringArray(1, 40, 1_000),
                        "reproduction_steps" to stringArray(0, 20, 1_000),
                        "risk_level" to AgentNativeJsonSchema.string(
                            enumValues = AgentSelfEvolutionRisk.entries.map { it.wireValue }
                        ),
                        "max_attempts" to AgentNativeJsonSchema.integer(1, 5)
                    ),
                    required = setOf("problem", "scope", "acceptance"),
                    additionalProperties = false
                ),
                execute = { invocation ->
                    val riskValue = invocation.input["risk_level"]?.toString().orEmpty()
                    val risk = AgentSelfEvolutionRisk.entries.firstOrNull { it.wireValue == riskValue }
                        ?: AgentSelfEvolutionRisk.MEDIUM
                    val task = manager.create(
                        problem = invocation.input["problem"]?.toString().orEmpty(),
                        scope = invocation.input.stringList("scope"),
                        acceptance = invocation.input.stringList("acceptance"),
                        reproductionSteps = invocation.input.stringList("reproduction_steps"),
                        risk = risk,
                        maxAttempts = (invocation.input["max_attempts"] as? Number)?.toInt() ?: 3
                    )
                    AgentNativeToolExecutionResult.success(task.internalToolValue(), "Evolution task created")
                }
            ),
            definition(
                id = PREPARE,
                title = "Prepare an isolated local candidate",
                description = "Clones the official source into a disposable Android-local Linux workspace and pins its base commit.",
                risk = AgentNativeToolRisk.MEDIUM,
                input = taskIdSchema(),
                timeoutMillis = 15 * 60_000L,
                requireConsent = true,
                availabilityProvider = { runtimeAvailability(appContext) },
                execute = { invocation ->
                    runEvolution(invocation, "Evolution candidate prepared") {
                        manager.prepare(
                            invocation.input["task_id"]?.toString().orEmpty(),
                            invocation.cancellationToken
                        )
                    }
                }
            ),
            definition(
                id = APPLY_PATCH,
                title = "Apply and validate a local evolution patch",
                description = "Applies one model-generated unified diff in the disposable candidate, enforces scope, runs immutable tests and builds, and produces a review-only candidate.",
                risk = AgentNativeToolRisk.HIGH,
                input = AgentNativeJsonSchema.objectSchema(
                    properties = mapOf(
                        "task_id" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 96),
                        "unified_diff" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 160 * 1024)
                    ),
                    required = setOf("task_id", "unified_diff"),
                    additionalProperties = false
                ),
                timeoutMillis = 30 * 60_000L,
                requireConsent = true,
                availabilityProvider = { runtimeAvailability(appContext) },
                execute = { invocation ->
                    runEvolution(invocation, "Evolution candidate validated") {
                        manager.applyPatchAndValidate(
                            invocation.input["task_id"]?.toString().orEmpty(),
                            invocation.input["unified_diff"]?.toString().orEmpty(),
                            invocation.cancellationToken
                        )
                    }
                }
            ),
            definition(
                id = ROLLBACK,
                title = "Discard a local evolution candidate",
                description = "Deletes only the disposable Android-local candidate and preserves the running app and stable source.",
                risk = AgentNativeToolRisk.MEDIUM,
                input = taskIdSchema(),
                requireConsent = true,
                execute = { invocation ->
                    runEvolution(invocation, "Evolution candidate rolled back") {
                        manager.rollback(invocation.input["task_id"]?.toString().orEmpty())
                    }
                }
            )
        )
    }

    private fun definition(
        id: String,
        title: String,
        description: String,
        risk: AgentNativeToolRisk,
        input: AgentNativeJsonSchema,
        timeoutMillis: Long = 30_000L,
        requireConsent: Boolean = false,
        availabilityProvider: (() -> AgentNativeToolAvailability)? = null,
        execute: (AgentNativeToolInvocation) -> AgentNativeToolExecutionResult
    ): AgentNativeToolDefinition {
        val availability = availabilityProvider?.invoke() ?: AgentNativeToolAvailability.AVAILABLE
        return AgentNativeToolDefinition(
            descriptor = AgentNativeToolDescriptor(
                id = id,
                version = "1.0.0",
                title = title,
                description = description,
                location = AgentNativeToolLocation.APPLICATION,
                inputSchema = input,
                outputSchema = AgentNativeJsonSchema.any(),
                risk = risk,
                capabilities = setOf(
                    "evolution.self",
                    "evolution.worktree",
                    "evolution.quality_gates",
                    "runtime.android_local"
                ),
                requiredConsents = if (requireConsent) listOf(
                    AgentNativeConsentRequirement(
                        id = CONSENT,
                        title = "Modify an isolated GalaxySSI candidate",
                        description = "Allows source changes only inside a disposable candidate workspace."
                    )
                ) else emptyList(),
                timeoutMillis = timeoutMillis,
                idempotency = if (risk == AgentNativeToolRisk.HIGH) {
                    AgentNativeToolIdempotency.IDEMPOTENCY_KEY_REQUIRED
                } else AgentNativeToolIdempotency.NON_IDEMPOTENT,
                availability = availability
            ),
            executor = AgentNativeToolExecutor(execute),
            executorId = "galaxyssi.android_self_evolution",
            provenanceMetadata = mapOf(
                "execution_target" to "android",
                "isolation" to "qemu_git_candidate",
                "production_mutation" to "disabled"
            ),
            availabilityProvider = AgentNativeToolAvailabilityProvider {
                availabilityProvider?.invoke() ?: availability
            }
        )
    }

    private fun taskIdSchema(): AgentNativeJsonSchema = AgentNativeJsonSchema.objectSchema(
        properties = mapOf(
            "task_id" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 96)
        ),
        required = setOf("task_id"),
        additionalProperties = false
    )

    private fun stringArray(minItems: Int, maxItems: Int, maxLength: Int): AgentNativeJsonSchema =
        AgentNativeJsonSchema.array(
            AgentNativeJsonSchema.string(minLength = 1, maxLength = maxLength),
            minItems = minItems,
            maxItems = maxItems
        )

    private fun runtimeAvailability(context: Context): AgentNativeToolAvailability {
        val status = AgentOnDeviceRuntimeManager(context).status()
        return if (status.backendReady && status.languageReady(AgentRuntimeLanguage.SHELL)) {
            AgentNativeToolAvailability.AVAILABLE
        } else AgentNativeToolAvailability(
            AgentNativeToolAvailabilityStatus.REQUIRES_SETUP,
            status.reason,
            System.currentTimeMillis()
        )
    }

    private fun runEvolution(
        invocation: AgentNativeToolInvocation,
        successMessage: String,
        action: () -> AgentSelfEvolutionTask
    ): AgentNativeToolExecutionResult = runCatching {
        invocation.reportProgress("evolution", successMessage.substringBeforeLast(' '))
        action()
    }.fold(
        onSuccess = { task ->
            AgentNativeToolExecutionResult.success(task.internalToolValue(), successMessage)
        },
        onFailure = { error ->
            AgentNativeToolExecutionResult.failure(
                (error as? AgentSelfEvolutionException)?.code ?: "self_evolution_failed",
                error.message ?: "Self-evolution failed"
            )
        }
    )

    private fun AgentSelfEvolutionTask.internalToolValue(): AgentNativeJsonObject = linkedMapOf(
        "task" to publicValue(),
        "candidate_workspace_id" to attempts.lastOrNull()?.workspaceId.orEmpty(),
        "candidate_source_root" to attempts.lastOrNull()?.let { "source" }.orEmpty()
    )

    private fun Map<String, Any?>.stringList(key: String): List<String> =
        (this[key] as? Iterable<*>)?.mapNotNull { it?.toString() }.orEmpty()
}
