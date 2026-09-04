package com.galaxyssi.chat

import android.content.Context
import java.util.concurrent.TimeUnit

data class AgentBenchmarkHarnessCapabilities(
    val planningAndTools: Boolean,
    val androidWorld: Boolean,
    val recoveryController: Boolean,
    val multiAgent: Boolean,
    val availableToolIds: Set<String> = emptySet(),
    val availableAndroidWorldTaskIds: Set<String> = emptySet()
)

object AgentBenchmarkHarnessCapabilityProbe {
    fun current(context: Context): AgentBenchmarkHarnessCapabilities {
        val app = context.applicationContext
        val registry = runCatching {
            val screen = AndroidScreenPerceptionProvider(app)
            AgentPhoneNativeToolCatalog.defaultRegistry(app, screenProvider = { screen.capture() })
        }.getOrNull()
        val availableTools = registry?.descriptors().orEmpty()
            .filter { it.availability.status == AgentNativeToolAvailabilityStatus.AVAILABLE }
            .mapTo(linkedSetOf(), AgentNativeToolDescriptor::id)
        val androidWorldTaskIds = AgentAndroidWorldStore(app).tasks(100)
            .mapTo(linkedSetOf(), AgentAndroidWorldTask::id)
        val multiAgentReady = runCatching {
            AgentBenchmarkAllocationPolicy.codexDeepSeek90To10(
                AgentEvalBenchmarkCatalog.standard,
                AgentEvolutionLabRuntimeRegistry.get(app).availableAgents()
            ).resources.size == 2
        }.getOrDefault(false)
        return AgentBenchmarkHarnessCapabilities(
            planningAndTools = registry != null,
            androidWorld = androidWorldTaskIds.isNotEmpty(),
            recoveryController = AgentEvalFaultControllerStore(app).activeLease() != null,
            multiAgent = multiAgentReady,
            availableToolIds = availableTools,
            availableAndroidWorldTaskIds = androidWorldTaskIds
        )
    }
}

object AgentBenchmarkPreflight {
    fun assess(
        context: Context,
        suite: AgentBenchmarkSuite,
        capabilities: AgentBenchmarkHarnessCapabilities = AgentBenchmarkHarnessCapabilityProbe.current(context),
        nowMillis: Long = System.currentTimeMillis()
    ): Map<String, AgentBenchmarkCaseReadiness> = assess(
        suite = suite,
        capabilities = capabilities,
        memories = EncryptedAgentMemoryStore(context.applicationContext).snapshot().activeItems,
        nowMillis = nowMillis
    )

    internal fun assess(
        suite: AgentBenchmarkSuite,
        capabilities: AgentBenchmarkHarnessCapabilities,
        memories: List<AgentMemoryItem>,
        nowMillis: Long
    ): Map<String, AgentBenchmarkCaseReadiness> {
        return suite.cases.associate { case ->
            val readiness = when (case.dimension) {
                AgentBenchmarkDimension.TASK_QUALITY -> ready(case)
                AgentBenchmarkDimension.PLANNING_AND_TOOLS -> planningReadiness(case, capabilities)
                AgentBenchmarkDimension.ANDROID_WORLD -> androidWorldReadiness(case, capabilities)
                AgentBenchmarkDimension.IMMEDIATE_MEMORY -> memoryReadiness(
                    case,
                    memories,
                    nowMillis
                )
                AgentBenchmarkDimension.LONG_TERM_MEMORY -> memoryReadiness(
                    case,
                    memories,
                    nowMillis
                )
                AgentBenchmarkDimension.RECOVERY -> if (capabilities.recoveryController) {
                    ready(case)
                } else {
                    waiting(case, "external_fault_controller_required")
                }
                AgentBenchmarkDimension.MULTI_AGENT -> capability(
                    case,
                    capabilities.multiAgent,
                    "multi_agent_harness_unavailable"
                )
            }
            case.id to readiness
        }
    }

    private fun planningReadiness(
        case: AgentBenchmarkCase,
        capabilities: AgentBenchmarkHarnessCapabilities
    ): AgentBenchmarkCaseReadiness {
        if (!capabilities.planningAndTools) {
            return blocked(case, "planning_tool_harness_unavailable")
        }
        val required = AgentBenchmarkHarnessProtocol.toolsFor(case, "preflight").mapTo(linkedSetOf()) { it.id }
        val missing = required - capabilities.availableToolIds
        return if (missing.isEmpty()) ready(case) else blocked(
            case,
            "required_tool_unavailable:${missing.sorted().joinToString(",")}"
        )
    }

    private fun androidWorldReadiness(
        case: AgentBenchmarkCase,
        capabilities: AgentBenchmarkHarnessCapabilities
    ): AgentBenchmarkCaseReadiness = when {
        !capabilities.androidWorld -> blocked(case, "android_world_harness_unavailable")
        case.expectation.androidWorldTaskId !in capabilities.availableAndroidWorldTaskIds -> blocked(
            case,
            "android_world_task_unavailable:${case.expectation.androidWorldTaskId}"
        )
        else -> ready(case)
    }

    private fun memoryReadiness(
        case: AgentBenchmarkCase,
        memories: List<AgentMemoryItem>,
        nowMillis: Long
    ): AgentBenchmarkCaseReadiness {
        val requiredDays = case.expectation.memoryHorizonDays
        val fixtureId = fixtureId(case.id)
        val fixtureKey = if (case.dimension == AgentBenchmarkDimension.IMMEDIATE_MEMORY) {
            "evalops.immediate.${fixtureId.lowercase()}"
        } else {
            "evalops.fixture.${fixtureId.lowercase()}"
        }
        val requiredSources = if (case.dimension == AgentBenchmarkDimension.IMMEDIATE_MEMORY) {
            setOf("evalops_immediate_fixture", "memory_edit")
        } else {
            setOf("evalops_fixture")
        }
        val memory = memories.firstOrNull { item ->
            item.source in requiredSources && item.key == fixtureKey &&
                item.value.startsWith("$fixtureId =", ignoreCase = true)
        }
        val requiredAgeMillis = TimeUnit.DAYS.toMillis(requiredDays.toLong())
        val eligibleAt = memory?.timestampMillis?.plus(requiredAgeMillis) ?: 0L
        return if (memory != null && requiredDays == 0) {
            ready(case)
        } else if (memory != null && requiredDays > 0 && eligibleAt <= nowMillis) {
            ready(case)
        } else {
            waiting(case, "memory_horizon_not_reached", eligibleAt)
        }
    }

    private fun fixtureId(caseId: String): String {
        Regex("^immediate-memory-(\\d{2})$").matchEntire(caseId)?.let { match ->
            return if (match.groupValues[1] == "09") "IM-09-B" else "IM-${match.groupValues[1]}"
        }
        val match = Regex("^memory-(30|90)-(\\d{2})$").matchEntire(caseId)
            ?: return caseId
        return "M${match.groupValues[1]}-${match.groupValues[2]}"
    }

    private fun capability(
        case: AgentBenchmarkCase,
        available: Boolean,
        reason: String
    ): AgentBenchmarkCaseReadiness = if (available) ready(case) else blocked(case, reason)

    private fun ready(case: AgentBenchmarkCase) = AgentBenchmarkCaseReadiness(
        case.id,
        AgentBenchmarkReadinessStatus.READY
    )

    private fun waiting(case: AgentBenchmarkCase, reason: String, eligibleAtMillis: Long = 0L) =
        AgentBenchmarkCaseReadiness(
            case.id,
            AgentBenchmarkReadinessStatus.WAITING,
            reason,
            eligibleAtMillis
        )

    private fun blocked(case: AgentBenchmarkCase, reason: String) = AgentBenchmarkCaseReadiness(
        case.id,
        AgentBenchmarkReadinessStatus.BLOCKED,
        reason
    )
}
