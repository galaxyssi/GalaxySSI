package com.signalasi.chat

import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

internal const val AGENT_TEAM_SPEC_PARAMETER = "_signalasi_agent_team_spec"
internal const val AGENT_TEAM_RUN_PARAMETER = "_signalasi_agent_team_run_id"
internal const val AGENT_TEAM_SOURCE_PARAMETER = "_signalasi_agent_team_source_id"

internal data class AgentTeamDispatchSpec(
    val definition: AgentTeamDefinition,
    val supervisorRunId: String
) {
    val sourceMessageId: Long
        get() = AgentTeamDispatchIds.sourceMessageId(supervisorRunId)

    val responseContactId: String
        get() = AgentTeamDispatchIds.responseContactId(definition.teamId)
}

/**
 * Converts a locally validated Agent dependency graph into one supervised host Run.
 * The model may propose tasks, but the host chooses the responder, roles, identity,
 * dependency graph, and delivery boundary.
 */
internal object AgentTeamPlanCompiler {
    fun compile(
        plan: AgentPlan,
        targets: List<AgentCallableTarget>,
        enabled: Boolean,
        registrations: Collection<AgentRegistration> = emptyList(),
        requestedMembers: List<AgentRequestedMember> = emptyList(),
        reputation: AgentReputationSnapshotProvider = AgentReputationSnapshotProvider.NONE
    ): AgentPlan {
        if (!plan.validation.valid || plan.isSupervisedProjectPlan()) return plan
        val availableResources = targets
            .filter {
                it.kind in setOf(AgentConnectorKind.AGENT, AgentConnectorKind.MODEL) &&
                    it.status == AgentConnectorStatus.AVAILABLE
            }
            .associateBy(AgentCallableTarget::id)
        if (requestedMembers.isNotEmpty()) {
            return compileRequestedSelection(
                plan = plan,
                requestedMembers = requestedMembers,
                availableAgents = availableResources,
                registrations = registrations,
                reputation = reputation
            )
        }
        if (!enabled) return plan
        val availableAgents = availableResources.filterValues {
            it.kind == AgentConnectorKind.AGENT
        }
        val candidates = plan.actions.mapNotNull { action ->
            if (action.kind != AgentActionKind.CALL_CONNECTOR) return@mapNotNull null
            val connectorId = action.parameters["connector_id"].orEmpty().trim()
            val target = availableAgents[connectorId] ?: return@mapNotNull null
            Candidate(action, target)
        }
        if (candidates.size == 1 &&
            plan.actions.count { it.kind == AgentActionKind.CALL_CONNECTOR } == 1 &&
            registrations.isNotEmpty()
        ) {
            compileDynamicTeam(
                plan = plan,
                candidate = candidates.single(),
                availableAgents = availableAgents,
                registrations = registrations,
                reputation = reputation
            )?.let { return it }
        }
        if (candidates.size < MIN_TEAM_MEMBERS || candidates.size > MAX_TEAM_MEMBERS) return plan
        val candidateCounts = candidates.groupingBy { it.target.id }.eachCount()
        val duplicatedAgentIds = candidateCounts.filterValues { it > 1 }
        if (duplicatedAgentIds.isNotEmpty()) {
            if (registrations.isEmpty()) return plan
            val registrationById = registrations.associateBy(AgentRegistration::agentId)
            if (duplicatedAgentIds.any { (agentId, count) ->
                    val registration = registrationById[agentId] ?: return@any true
                    count > (registration.maxParallelRuns - registration.activeRuns).coerceAtLeast(0)
                }
            ) return plan
        }

        val candidateIds = candidates.mapTo(linkedSetOf()) { it.action.id }
        if (candidates.any { candidate ->
                candidate.action.dependencyIds().any { it !in candidateIds } ||
                    candidate.action.outputSourceIds().any { it !in candidate.action.dependencyIds() }
            }
        ) return plan

        val dependencyTargets = candidates
            .flatMapTo(linkedSetOf()) { it.action.dependencyIds() }
        val sinks = candidates.filter { it.action.id !in dependencyTargets }
        if (sinks.size != 1) return plan
        val primary = sinks.single()
        if (transitiveDependencies(primary.action.id, candidates) + primary.action.id != candidateIds) return plan

        val memberIdByAction = candidates.associate { candidate ->
            candidate.action.id to if (candidateCounts.getValue(candidate.target.id) == 1) {
                candidate.target.id
            } else {
                instanceId(candidate.target.id, candidate.action.id)
            }
        }
        val members = candidates.map { candidate ->
            val isPrimary = candidate.action.id == primary.action.id
            AgentTeamMember(
                agentId = candidate.target.id,
                deliveryMode = if (isPrimary) AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                requiredCapabilities = candidate.target.capabilities.toSet(),
                role = roleFor(candidate.target, isPrimary),
                objective = candidate.action.parameters["prompt"].orEmpty()
                    .ifBlank { candidate.action.description }
                    .take(MAX_MEMBER_OBJECTIVE_CHARACTERS),
                dependsOnAgentIds = candidate.action.dependencyIds()
                    .mapNotNullTo(linkedSetOf(), memberIdByAction::get),
                context = mapOf(
                    AGENT_KNOWLEDGE_CONTEXT_KEY to candidate.action.parameters[AGENT_KNOWLEDGE_CONTEXT_KEY]
                        .orEmpty()
                        .take(MAX_MEMBER_KNOWLEDGE_CHARACTERS)
                ),
                instanceId = memberIdByAction.getValue(candidate.action.id)
            )
        }
        val teamId = AgentTeamDispatchIds.teamId(plan, candidates.map { it.action })
        val runId = AgentTeamDispatchIds.supervisorRunId(teamId)
        val definition = AgentTeamDefinition(
            teamId = teamId,
            primaryAgentId = primary.target.id,
            primaryInstanceId = memberIdByAction.getValue(primary.action.id),
            members = members,
            visibilityMode = AgentTeamVisibilityMode.BACKGROUND
        )
        val spec = AgentTeamDispatchSpec(definition, runId)
        val syntheticId = "agent-team-${teamId.take(12)}"
        val risk = candidates.maxByOrNull { it.action.risk.weight }?.action?.risk ?: AgentRisk.MEDIUM
        val synthetic = primary.action.copy(
            id = syntheticId,
            target = "Agent team: ${primary.target.title}",
            risk = risk,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Coordinate ${members.size} specialist Agents",
            parameters = primary.action.parameters + mapOf(
                "connector_id" to primary.target.id,
                "original_goal" to plan.goal,
                "node_ref" to "agent_team",
                "depends_on" to "",
                "use_outputs_from" to "",
                AGENT_TEAM_SPEC_PARAMETER to AgentTeamDispatchSpecCodec.encode(spec),
                AGENT_TEAM_RUN_PARAMETER to runId,
                AGENT_TEAM_SOURCE_PARAMETER to spec.sourceMessageId.toString()
            ),
            requiresConfirmation = candidates.any { it.action.requiresConfirmation }
        )
        val idMap = plan.actions.associate { action ->
            action.id to if (action.id in candidateIds) syntheticId else action.id
        }
        var inserted = false
        val actions = buildList {
            plan.actions.forEach { action ->
                if (action.id in candidateIds) {
                    if (!inserted) {
                        add(synthetic)
                        inserted = true
                    }
                } else {
                    add(action.remapToolGraphIds(action.id, idMap))
                }
            }
        }
        val compiled = plan.copy(
            actions = actions,
            selectedAgentOrModel = "Agent team: ${primary.target.title}",
            timeoutSeconds = plan.timeoutSeconds.coerceAtLeast(TEAM_TIMEOUT_SECONDS).coerceAtMost(240),
            route = AgentRouteResolver.resolve(synthetic, targets)
        )
        val validation = AgentPlanValidator.validate(compiled)
        return if (validation.valid) compiled.copy(validation = validation) else plan
    }

    private fun compileRequestedSelection(
        plan: AgentPlan,
        requestedMembers: List<AgentRequestedMember>,
        availableAgents: Map<String, AgentCallableTarget>,
        registrations: Collection<AgentRegistration>,
        reputation: AgentReputationSnapshotProvider
    ): AgentPlan {
        val requested = requestedMembers.take(MAX_TEAM_MEMBERS).toMutableList()
        if (allowsAutomaticExpansion(plan.goal)) {
            val explicitMemberCount = requested.size
            val currentIds = requested.mapTo(linkedSetOf(), AgentRequestedMember::agentId)
            plan.actions.asSequence()
                .filter { it.kind == AgentActionKind.CALL_CONNECTOR }
                .map { it.parameters["connector_id"].orEmpty().trim() }
                .filter { it.isNotBlank() && it !in currentIds && it in availableAgents }
                .distinct()
                .take(MAX_TEAM_MEMBERS - requested.size)
                .forEach { agentId ->
                    val target = availableAgents.getValue(agentId)
                    requested += AgentRequestedMember(agentId, target.title)
                    currentIds += agentId
                }
            AgentDynamicTeamCompiler(reputation).compile(
                request = AgentDynamicTeamRequest(
                    goal = plan.goal,
                    policy = AgentDynamicTeamPolicy(
                        forceTeam = true,
                        pinnedAgentIds = currentIds.toSet()
                    )
                ),
                registrations = registrations
            ).definition?.members.orEmpty()
                .asSequence()
                .map(AgentTeamMember::agentId)
                .filter { it !in currentIds && it in availableAgents }
                .distinct()
                .take(MAX_TEAM_MEMBERS - requested.size)
                .forEach { agentId ->
                    requested += AgentRequestedMember(
                        agentId,
                        availableAgents.getValue(agentId).title
                    )
                    currentIds += agentId
                }
            if (requested.size == explicitMemberCount && requested.size < MAX_TEAM_MEMBERS) {
                val requirements = AgentTaskRequirementAnalyzer.analyze(plan.goal)
                registrations.asSequence()
                    .filter { registration ->
                        registration.agentId !in currentIds &&
                            registration.agentId in availableAgents &&
                            registration.kind in setOf(AgentConnectorKind.AGENT, AgentConnectorKind.MODEL) &&
                            registration.status in setOf(
                                AgentEndpointStatus.ONLINE,
                                AgentEndpointStatus.IDLE,
                                AgentEndpointStatus.BUSY
                            ) &&
                            registration.hasCapacity &&
                            registration.trust != AgentResourceTrust.UNKNOWN
                    }
                    .sortedWith(
                        compareByDescending<AgentRegistration> { registration ->
                            registration.capabilities.count(requirements.capabilities::contains)
                        }.thenBy(String.CASE_INSENSITIVE_ORDER, AgentRegistration::displayName)
                    )
                    .firstOrNull()
                    ?.let { registration ->
                        requested += AgentRequestedMember(
                            registration.agentId,
                            availableAgents.getValue(registration.agentId).title
                        )
                    }
            }
        }
        val registrationById = registrations.associateBy(AgentRegistration::agentId)
        val requestedCounts = requested.groupingBy(AgentRequestedMember::agentId).eachCount()
        requestedCounts.forEach { (agentId, count) ->
            require(agentId in availableAgents) { "Selected Agent is no longer available: $agentId" }
            val registration = requireNotNull(registrationById[agentId]) {
                "Selected Agent is not registered: $agentId"
            }
            require(
                registration.status in setOf(
                    AgentEndpointStatus.ONLINE,
                    AgentEndpointStatus.IDLE,
                    AgentEndpointStatus.BUSY
                )
            ) { "Selected Agent is offline: ${registration.displayName}" }
            val availableCapacity = (registration.maxParallelRuns - registration.activeRuns).coerceAtLeast(0)
            require(count <= availableCapacity) {
                "Selected Agent has only $availableCapacity available Run slots: ${registration.displayName}"
            }
        }
        return if (requested.size == 1) {
            compileRequestedSingle(plan, requested.single(), availableAgents.getValue(requested.single().agentId))
        } else {
            compileRequestedTeam(plan, requested, availableAgents)
        }
    }

    private fun compileRequestedSingle(
        plan: AgentPlan,
        member: AgentRequestedMember,
        target: AgentCallableTarget
    ): AgentPlan {
        val template = plan.actions.firstOrNull { it.kind == AgentActionKind.CALL_CONNECTOR }
            ?: plan.actions.first()
        val action = AgentAction(
            id = "agent-mention-${member.agentId.hashCode().toUInt()}",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = target.title,
            risk = template.risk,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Run with selected Agent ${target.title}",
            parameters = template.parameters + mapOf(
                "connector_id" to member.agentId,
                "prompt" to plan.goal,
                "original_goal" to plan.goal,
                "manual_target_locked" to "true",
                "agent_selection_source" to "user_mention"
            ),
            requiresConfirmation = template.requiresConfirmation
        )
        val compiled = plan.copy(
            actions = listOf(action),
            selectedAgentOrModel = target.title,
            expectedResult = action.description,
            route = AgentRouteResolver.resolve(action, targets = listOf(target)),
            plannerProfile = "${plan.plannerProfile}+user-mention",
            routeRationale = "The user explicitly selected ${target.title}."
        )
        return compiled.copy(validation = AgentPlanValidator.validate(compiled))
    }

    private fun compileRequestedTeam(
        plan: AgentPlan,
        requested: List<AgentRequestedMember>,
        availableAgents: Map<String, AgentCallableTarget>
    ): AgentPlan {
        val primaryRequest = requested.first()
        val primary = availableAgents.getValue(primaryRequest.agentId)
        val memberIds = requested.map(AgentRequestedMember::instanceId)
        val members = requested.mapIndexed { index, requestedMember ->
            val target = availableAgents.getValue(requestedMember.agentId)
            val isPrimary = index == 0
            AgentTeamMember(
                agentId = requestedMember.agentId,
                deliveryMode = if (isPrimary) AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                requiredCapabilities = target.capabilities.toSet(),
                role = roleFor(target, isPrimary),
                objective = if (isPrimary) {
                    buildString {
                        append("Lead the selected Agent team, use all member results, and produce one final answer.")
                        requestedMember.roleHint.takeIf(String::isNotBlank)?.let {
                            append(" Explicit role: ").append(it).append('.')
                        }
                        append(" User goal: ").append(plan.goal)
                    }
                } else {
                    buildString {
                        append("Contribute as ").append(roleFor(target, false)).append('.')
                        requestedMember.roleHint.takeIf(String::isNotBlank)?.let {
                            append(" Explicit role: ").append(it).append('.')
                        }
                        append(" User goal: ").append(plan.goal)
                    }
                }.take(MAX_MEMBER_OBJECTIVE_CHARACTERS),
                dependsOnAgentIds = if (isPrimary) memberIds.drop(1).toSet() else emptySet(),
                context = mapOf(
                    "_signalasi_selection_source" to "user_mention",
                    "_signalasi_role_hint" to requestedMember.roleHint
                ),
                instanceId = requestedMember.instanceId
            )
        }
        val memberActions = requested.mapIndexed { index, member ->
            AgentAction(
                id = "mention-$index-${member.agentId.hashCode().toUInt()}",
                kind = AgentActionKind.CALL_CONNECTOR,
                target = availableAgents.getValue(member.agentId).title,
                risk = AgentRisk.LOW,
                status = AgentActionStatus.PENDING_CONFIRMATION,
                description = "Selected Agent team member ${member.displayName}",
                parameters = mapOf("connector_id" to member.agentId, "prompt" to plan.goal),
                requiresConfirmation = false
            )
        }
        val teamId = AgentTeamDispatchIds.teamId(plan, memberActions)
        val runId = AgentTeamDispatchIds.supervisorRunId(teamId)
        val definition = AgentTeamDefinition(
            teamId = teamId,
            primaryAgentId = primaryRequest.agentId,
            primaryInstanceId = primaryRequest.instanceId,
            members = members,
            visibilityMode = AgentTeamVisibilityMode.BACKGROUND,
            collectiveCapabilities = requested.flatMapTo(linkedSetOf()) { member ->
                availableAgents.getValue(member.agentId).capabilities
            }
        )
        val spec = AgentTeamDispatchSpec(definition, runId)
        val template = plan.actions.firstOrNull { it.kind == AgentActionKind.CALL_CONNECTOR }
            ?: plan.actions.first()
        val synthetic = AgentAction(
            id = "agent-team-${teamId.take(12)}",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Agent team: ${primary.title}",
            risk = template.risk,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Coordinate ${members.size} user-selected Agents",
            parameters = template.parameters + mapOf(
                "connector_id" to primaryRequest.agentId,
                "prompt" to plan.goal,
                "original_goal" to plan.goal,
                "node_ref" to "agent_team",
                "manual_target_locked" to "true",
                "agent_selection_source" to "user_mention",
                AGENT_TEAM_SPEC_PARAMETER to AgentTeamDispatchSpecCodec.encode(spec),
                AGENT_TEAM_RUN_PARAMETER to runId,
                AGENT_TEAM_SOURCE_PARAMETER to spec.sourceMessageId.toString()
            ),
            requiresConfirmation = template.requiresConfirmation
        )
        val compiled = plan.copy(
            actions = listOf(synthetic),
            selectedAgentOrModel = "Agent team: ${primary.title}",
            expectedResult = synthetic.description,
            timeoutSeconds = plan.timeoutSeconds.coerceAtLeast(TEAM_TIMEOUT_SECONDS).coerceAtMost(240),
            route = AgentRouteResolver.resolve(synthetic, availableAgents.values.toList()),
            plannerProfile = "${plan.plannerProfile}+user-mention-team",
            routeRationale = "The user explicitly selected ${members.size} Agent instances."
        )
        return compiled.copy(validation = AgentPlanValidator.validate(compiled))
    }

    private fun allowsAutomaticExpansion(goal: String): Boolean = listOf(
        Regex("自动.{0,24}(找|选|补充|增加).{0,24}(agent|智能体)", RegexOption.IGNORE_CASE),
        Regex("(auto|automatically).{0,24}(add|find|choose|select).{0,24}(agent|member)", RegexOption.IGNORE_CASE)
    ).any { it.containsMatchIn(goal) }

    private fun compileDynamicTeam(
        plan: AgentPlan,
        candidate: Candidate,
        availableAgents: Map<String, AgentCallableTarget>,
        registrations: Collection<AgentRegistration>,
        reputation: AgentReputationSnapshotProvider
    ): AgentPlan? {
        val eligibleRegistrations = registrations.filter { registration ->
            registration.kind in setOf(AgentConnectorKind.AGENT, AgentConnectorKind.MODEL) &&
                registration.status in setOf(
                    AgentEndpointStatus.ONLINE,
                    AgentEndpointStatus.IDLE,
                    AgentEndpointStatus.BUSY
                )
        }
        if (eligibleRegistrations.size < MIN_TEAM_MEMBERS) return null
        val teamId = AgentTeamDispatchIds.teamId(plan, listOf(candidate.action))
        val compilation = AgentDynamicTeamCompiler(reputation).compile(
            request = AgentDynamicTeamRequest(
                goal = plan.goal,
                teamId = teamId,
                policy = AgentDynamicTeamPolicy(
                    pinnedAgentIds = setOf(candidate.target.id)
                )
            ),
            registrations = eligibleRegistrations
        )
        val definition = compilation.definition
            ?.takeIf { compilation.outcome == AgentDynamicTeamOutcome.TEAM }
            ?: return null
        val eligibleAgentIds = eligibleRegistrations.mapTo(linkedSetOf(), AgentRegistration::agentId)
        if (definition.members.any { it.agentId !in eligibleAgentIds }) return null
        if (definition.primaryAgentId !in availableAgents) return null

        val runId = AgentTeamDispatchIds.supervisorRunId(teamId)
        val spec = AgentTeamDispatchSpec(definition, runId)
        val syntheticId = "agent-team-${teamId.take(12)}"
        val primary = availableAgents.getValue(definition.primaryAgentId)
        val synthetic = candidate.action.copy(
            id = syntheticId,
            target = "Agent team: ${primary.title}",
            description = "Coordinate ${definition.members.size} specialist Agents",
            parameters = candidate.action.parameters + mapOf(
                "connector_id" to definition.primaryAgentId,
                "original_goal" to plan.goal,
                "node_ref" to "agent_team",
                AGENT_TEAM_SPEC_PARAMETER to AgentTeamDispatchSpecCodec.encode(spec),
                AGENT_TEAM_RUN_PARAMETER to runId,
                AGENT_TEAM_SOURCE_PARAMETER to spec.sourceMessageId.toString()
            )
        )
        val idMap = mapOf(candidate.action.id to syntheticId)
        val actions = plan.actions.map { action ->
            if (action.id == candidate.action.id) {
                synthetic
            } else {
                action.remapToolGraphIds(action.id, idMap)
            }
        }
        val compiled = plan.copy(
            actions = actions,
            selectedAgentOrModel = "Agent team: ${primary.title}",
            timeoutSeconds = plan.timeoutSeconds.coerceAtLeast(TEAM_TIMEOUT_SECONDS).coerceAtMost(240),
            route = AgentRouteResolver.resolve(synthetic, availableAgents.values.toList())
        )
        val validation = AgentPlanValidator.validate(compiled)
        return compiled.takeIf { validation.valid }?.copy(validation = validation)
    }

    private fun transitiveDependencies(
        actionId: String,
        candidates: List<Candidate>
    ): Set<String> {
        val byId = candidates.associateBy { it.action.id }
        val visited = linkedSetOf<String>()
        fun visit(id: String) {
            byId[id]?.action?.dependencyIds().orEmpty().forEach { dependencyId ->
                if (visited.add(dependencyId)) visit(dependencyId)
            }
        }
        visit(actionId)
        return visited
    }

    private fun roleFor(target: AgentCallableTarget, primary: Boolean): String {
        if (primary) return "lead synthesizer"
        return when {
            AgentCapability.CODE in target.capabilities -> "software specialist"
            AgentCapability.RESEARCH in target.capabilities || AgentCapability.LIVE_DATA in target.capabilities ->
                "research specialist"
            AgentCapability.KNOWLEDGE_SEARCH in target.capabilities -> "knowledge specialist"
            AgentCapability.DEVICE_CONTROL in target.capabilities || AgentCapability.SMART_HOME in target.capabilities ->
                "device specialist"
            AgentCapability.TASK_EXECUTION in target.capabilities -> "execution specialist"
            else -> "reasoning specialist"
        }
    }

    private data class Candidate(
        val action: AgentAction,
        val target: AgentCallableTarget
    )

    private fun instanceId(agentId: String, actionId: String): String {
        val suffix = actionId.trim().map { character ->
            if (character.isLetterOrDigit() || character in "._-") character else '-'
        }.joinToString("").trim('-').ifBlank { UUID.randomUUID().toString().take(8) }
        return "$agentId:${suffix.take(48)}".take(96)
    }

    private const val MIN_TEAM_MEMBERS = 2
    private const val MAX_TEAM_MEMBERS = 12
    private const val MAX_MEMBER_OBJECTIVE_CHARACTERS = 4_000
    private const val MAX_MEMBER_KNOWLEDGE_CHARACTERS = 8_000
    private const val TEAM_TIMEOUT_SECONDS = 180
    private const val AGENT_KNOWLEDGE_CONTEXT_KEY = "_signalasi_agent_knowledge_context"
}

internal object AgentTeamDispatchSpecCodec {
    fun encode(spec: AgentTeamDispatchSpec): String = JSONObject()
        .put("version", VERSION)
        .put("supervisor_run_id", spec.supervisorRunId)
        .put("team_id", spec.definition.teamId)
        .put("primary_agent_id", spec.definition.primaryAgentId)
        .put("primary_instance_id", spec.definition.primaryMemberId)
        .put("visibility", spec.definition.visibilityMode.name)
        .put("collective_capabilities", JSONArray(
            spec.definition.collectiveCapabilities.map(AgentCapability::name)
        ))
        .put("members", JSONArray().apply {
            spec.definition.members.forEach { member ->
                put(JSONObject()
                    .put("agent_id", member.agentId)
                    .put("instance_id", member.memberId)
                    .put("delivery_mode", member.deliveryMode.name)
                    .put("capabilities", JSONArray(member.requiredCapabilities.map(AgentCapability::name)))
                    .put("role", member.role)
                    .put("objective", member.objective)
                    .put("depends_on", JSONArray(member.dependsOnAgentIds.toList()))
                    .put("context", JSONObject(member.context)))
            }
        })
        .toString()

    fun decode(raw: String): AgentTeamDispatchSpec? = runCatching {
        val json = JSONObject(raw)
        if (json.optInt("version") != VERSION) return null
        val runId = json.optString("supervisor_run_id").trim()
        val teamId = json.optString("team_id").trim()
        val primaryAgentId = json.optString("primary_agent_id").trim()
        val primaryInstanceId = json.optString("primary_instance_id").trim()
            .ifBlank { primaryAgentId }
        if (runId.isBlank() || teamId.isBlank() || primaryAgentId.isBlank()) return null
        val input = json.optJSONArray("members") ?: return null
        if (input.length() !in 2..12) return null
        val members = buildList {
            for (index in 0 until input.length()) {
                val item = input.optJSONObject(index) ?: return null
                val agentId = item.optString("agent_id").trim()
                if (agentId.isBlank()) return null
                val deliveryMode = runCatching {
                    AgentDeliveryMode.valueOf(item.optString("delivery_mode"))
                }.getOrNull() ?: return null
                val capabilities = item.optJSONArray("capabilities").enumCapabilities()
                val dependencies = item.optJSONArray("depends_on").strings().toSet()
                val context = item.optJSONObject("context").stringMap()
                add(AgentTeamMember(
                    agentId = agentId,
                    deliveryMode = deliveryMode,
                    requiredCapabilities = capabilities,
                    role = item.optString("role").take(80),
                    objective = item.optString("objective").take(4_000),
                    dependsOnAgentIds = dependencies,
                    context = context,
                    instanceId = item.optString("instance_id").trim().ifBlank { agentId }
                ))
            }
        }
        if (members.map { it.memberId }.distinct().size != members.size) return null
        if (members.count { it.deliveryMode == AgentDeliveryMode.RESPOND } != 1) return null
        if (members.none { it.memberId == primaryInstanceId && it.deliveryMode == AgentDeliveryMode.RESPOND }) return null
        val memberIds = members.mapTo(linkedSetOf(), AgentTeamMember::memberId)
        if (members.any { it.memberId in it.dependsOnAgentIds || !memberIds.containsAll(it.dependsOnAgentIds) }) return null
        AgentTeamDispatchSpec(
            definition = AgentTeamDefinition(
                teamId = teamId,
                primaryAgentId = primaryAgentId,
                members = members,
                visibilityMode = runCatching {
                    AgentTeamVisibilityMode.valueOf(json.optString("visibility"))
                }.getOrDefault(AgentTeamVisibilityMode.BACKGROUND),
                collectiveCapabilities = json.optJSONArray("collective_capabilities").enumCapabilities(),
                primaryInstanceId = primaryInstanceId
            ),
            supervisorRunId = runId
        )
    }.getOrNull()

    private fun JSONArray?.strings(): List<String> {
        if (this == null) return emptyList()
        return buildList {
            for (index in 0 until length()) {
                optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
            }
        }
    }

    private fun JSONArray?.enumCapabilities(): Set<AgentCapability> = strings()
        .mapNotNullTo(linkedSetOf()) { value ->
            runCatching { AgentCapability.valueOf(value) }.getOrNull()
        }

    private fun JSONObject?.stringMap(): Map<String, String> {
        if (this == null) return emptyMap()
        return keys().asSequence()
            .mapNotNull { key ->
                key.takeIf { it.startsWith("_signalasi_") }
                    ?.let { it to optString(it).take(8_000) }
            }
            .toMap()
    }

    private const val VERSION = 2
}

internal fun AgentAction.rekeyAgentTeamForRetry(): AgentAction {
    val spec = AgentTeamDispatchSpecCodec.decode(parameters[AGENT_TEAM_SPEC_PARAMETER].orEmpty())
        ?: return this
    val nextTeamId = UUID.randomUUID().toString()
    val nextRunId = AgentTeamDispatchIds.supervisorRunId(nextTeamId)
    val nextSpec = AgentTeamDispatchSpec(
        definition = spec.definition.copy(teamId = nextTeamId),
        supervisorRunId = nextRunId
    )
    return copy(parameters = parameters + mapOf(
        AGENT_TEAM_SPEC_PARAMETER to AgentTeamDispatchSpecCodec.encode(nextSpec),
        AGENT_TEAM_RUN_PARAMETER to nextRunId,
        AGENT_TEAM_SOURCE_PARAMETER to nextSpec.sourceMessageId.toString()
    ))
}

internal object AgentTeamDispatchIds {
    fun teamId(plan: AgentPlan, actions: List<AgentAction>): String {
        val conversationId = actions.firstNotNullOfOrNull {
            it.parameters["_signalasi_conversation_id"]?.takeIf(String::isNotBlank)
        }.orEmpty()
        val turnId = actions.firstNotNullOfOrNull {
            it.parameters["_signalasi_turn_id"]?.takeIf(String::isNotBlank)
        }.orEmpty()
        val source = buildString {
            append("signalasi-agent-team\u001f")
            append(conversationId).append('\u001f')
            append(turnId).append('\u001f')
            append(plan.planId).append('\u001f')
            actions.forEach { action ->
                append(action.id).append(':')
                append(action.parameters["connector_id"].orEmpty()).append('\u001f')
            }
        }
        return UUID.nameUUIDFromBytes(source.toByteArray(Charsets.UTF_8)).toString()
    }

    fun supervisorRunId(teamId: String): String = UUID.nameUUIDFromBytes(
        "signalasi-agent-team-run\u001f$teamId".toByteArray(Charsets.UTF_8)
    ).toString()

    fun sourceMessageId(supervisorRunId: String): Long {
        val uuid = UUID.nameUUIDFromBytes(
            "signalasi-agent-team-response\u001f$supervisorRunId".toByteArray(Charsets.UTF_8)
        )
        val value = (uuid.mostSignificantBits xor uuid.leastSignificantBits) and SOURCE_ID_PAYLOAD_MASK
        return value or SOURCE_ID_NAMESPACE_BIT
    }

    fun responseContactId(teamId: String): String = "agent-team:$teamId"

    private const val SOURCE_ID_NAMESPACE_BIT = 1L shl 62
    private const val SOURCE_ID_PAYLOAD_MASK = SOURCE_ID_NAMESPACE_BIT - 1L
}
