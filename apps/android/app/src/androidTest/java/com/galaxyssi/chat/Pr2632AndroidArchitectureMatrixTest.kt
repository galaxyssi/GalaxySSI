package com.galaxyssi.chat

import android.content.Context
import android.os.Build
import android.os.Debug
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class Pr2632AndroidArchitectureMatrixTest {
    @Test
    fun runsOneThousandArchitectureScenariosOnDevice() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        requireSmT575()
        val failures = mutableListOf<String>()
        val counts = linkedMapOf<String, Int>()
        val outcomes = mutableListOf<ScenarioOutcome>()

        fun runCase(name: String, index: Int, scenario: () -> Unit) {
            val result = runCatching(scenario)
            result.onFailure { error ->
                failures += "$name[$index]: ${error.javaClass.simpleName}: ${error.message.orEmpty()}"
            }
            outcomes += ScenarioOutcome(
                group = name,
                index = index,
                passed = result.isSuccess,
                detail = result.exceptionOrNull()?.let { error ->
                    "${error.javaClass.simpleName}: ${error.message.orEmpty()}"
                }.orEmpty()
            )
        }

        fun runGroup(name: String, count: Int, scenario: (Int) -> Unit) {
            repeat(count) { index ->
                runCase(name, index) { scenario(index) }
            }
            counts[name] = count
        }

        runGroup("foreground_core_memory", 100, ::coreMemoryScenario)
        runGroup("foreground_prompt_compiler", 100, ::promptCompilerScenario)
        runGroup("background_scheduler_and_ingestion", 80, ::schedulerScenario)
        runGroup("background_memory_evolution", 160, ::memoryEvolutionScenario)
        runGroup("background_graph_memory", 120, ::graphMemoryScenario)
        knowledgeIndexScenarios(100) { index, scenario ->
            runCase("background_knowledge_index", index, scenario)
        }.also { counts["background_knowledge_index"] = it }
        skillScenarios(100) { index, scenario ->
            runCase("background_skills", index, scenario)
        }.also { counts["background_skills"] = it }
        runGroup("background_knowledge_gap_and_research", 80, ::knowledgeGapScenario)
        runGroup("proactive_cognition_loop", 80, ::proactiveCognitionScenario)
        runGroup("background_memory_critic", 40, ::memoryCriticScenario)
        runGroup("obsidian_knowledge_projection", 40, ::obsidianScenario)

        val total = counts.values.sum()
        assertEquals(1_000, outcomes.size)
        val visibleReport = VisibleScenarioConversationRecorder(context).replace(outcomes, counts)
        Log.i(
            LOG_TAG,
            "scenario_summary total=$total counts=$counts failures=${failures.size} " +
                "visible_conversations=${visibleReport.getInt("visible_conversations")}"
        )
        failures.take(30).forEach { failure -> Log.e(LOG_TAG, failure) }
        assertEquals(1_000, total)
        assertTrue(
            "${failures.size} of $total architecture scenarios failed:\n${failures.take(30).joinToString("\n")}",
            failures.isEmpty()
        )
    }

    private fun coreMemoryScenario(index: Int) {
        if (index < 8) {
            crossSessionCoreMemoryScenario(index)
            return
        }
        when {
            index < 32 -> {
                val prefixes = listOf(
                    "我的名字是", "我的名字叫", "我的姓名是", "我叫",
                    "请叫我", "以后叫我", "你可以叫我", "称呼我为"
                )
                val name = "测试用户$index"
                val candidate = AndroidCoreMemoryExtractor.extract(
                    "${prefixes[index % prefixes.size]} $name，后面的内容不属于名字。"
                ).single { it.key == AndroidCoreMemoryExtractor.KEY_NAME }
                check(candidate.value == "The user's preferred name is $name.")
            }
            index < 56 -> {
                val prefixes = listOf(
                    "我的手机是", "我的手机型号是", "我的设备是", "当前设备是",
                    "我用的手机是", "我用的设备是", "我正在用的手机是"
                )
                val device = "Matrix Device $index"
                val candidate = AndroidCoreMemoryExtractor.extract(
                    "${prefixes[index % prefixes.size]} $device。"
                ).single { it.key == AndroidCoreMemoryExtractor.KEY_PRIMARY_DEVICE }
                check(candidate.value.contains(device))
            }
            index < 80 -> {
                val prefixes = listOf(
                    "我的项目是", "当前项目是", "我正在开发",
                    "我正在开发的项目是", "我正在做的项目是", "我在做的项目是"
                )
                val project = "MatrixProject$index"
                val candidate = AndroidCoreMemoryExtractor.extract(
                    "${prefixes[index % prefixes.size]} $project。"
                ).single { it.key == AndroidCoreMemoryExtractor.KEY_CURRENT_PROJECT }
                check(candidate.value.contains(project))
            }
            index < 92 -> {
                val preference = "使用简洁回答格式 $index"
                val candidate = AndroidCoreMemoryExtractor.extract("我偏好 $preference")
                    .single { it.category == AndroidCoreMemoryCategory.PREFERENCE }
                check(candidate.value.contains(preference))
                check(candidate.key.startsWith("core:preference:"))
            }
            else -> {
                val unsafe = "我的名字是测试用户，api_key=sk-matrix-secret-$index"
                check(AndroidCoreMemoryExtractor.extract(unsafe).isEmpty())
            }
        }
    }

    private fun crossSessionCoreMemoryScenario(index: Int) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = EncryptedAgentMemoryStore(context).apply { suppressObservations = true }
        if (index == 0) {
            store.snapshot().activeItems
                .filter { it.source == VISIBLE_MATRIX_MEMORY_SOURCE }
                .forEach { store.deleteById(it.id) }
        }
        val marker = "sm-t575-cross-session-$index-${UUID.randomUUID()}"
        val remembered = requireNotNull(store.remember(AgentMemoryItem(
            kind = AgentMemoryKind.IDENTITY,
            value = "The temporary device-test identity marker is $marker.",
            source = VISIBLE_MATRIX_MEMORY_SOURCE,
            key = "core:identity:device-test:$marker",
            important = true,
            confidence = 1.0,
            lastConfirmedAtMillis = System.currentTimeMillis()
        )).item)
        try {
            val promptFromSessionA = AndroidCoreMemoryCoordinator(context).compilePrompt(3_000)
            val freshSessionB = AgentConversationContext(
                conversationId = "sm-t575-session-b-$index",
                summary = "",
                turns = emptyList(),
                privateMode = false,
                globalContext = promptFromSessionA
            )
            check(promptFromSessionA.contains(marker))
            check(freshSessionB.asPromptBlock(includeGlobalContext = true).contains(marker))
            check(freshSessionB.asTransportBlock(includeGlobalContext = true).contains(marker))
        } finally {
            check(store.deleteById(remembered.id))
        }
    }

    private fun promptCompilerScenario(index: Int) {
        if (index < 20) {
            currentConversationRetrievalScenario(index)
            return
        }
        if (index < 40) {
            val marker = "matrix-global-context-$index"
            val privateMode = index % 4 == 1
            val trackingPaused = index % 4 == 2
            val context = AgentConversationContext(
                conversationId = "matrix-context-$index",
                summary = "",
                turns = emptyList(),
                privateMode = privateMode,
                globalContext = marker,
                trackingPaused = trackingPaused
            )
            check(!context.asPromptBlock().contains(marker))
            val explicit = context.asPromptBlock(includeGlobalContext = true)
            check(explicit.contains(marker) == (!privateMode && !trackingPaused))
            val transport = context.asTransportBlock(includeGlobalContext = true)
            check(transport.contains(marker) == (!privateMode && !trackingPaused))
            return
        }

        val marker = "MatrixPrompt$index"
        val mode = index % 4
        val item = when (mode) {
            0 -> worldItem(
                index, GlobalWorldItemKind.FACT, GlobalWorldLayer.USER,
                GlobalMemoryNamespace.USER, "self", "User identity",
                "The user's name is $marker"
            )
            1 -> worldItem(
                index, GlobalWorldItemKind.PREFERENCE, GlobalWorldLayer.USER,
                GlobalMemoryNamespace.USER, "self", "Response preference",
                "The user prefers $marker response style"
            )
            2 -> worldItem(
                index, GlobalWorldItemKind.STATE, GlobalWorldLayer.USER,
                GlobalMemoryNamespace.DEVICE, "local", "Phone device",
                "The phone device is $marker"
            )
            else -> worldItem(
                index, GlobalWorldItemKind.STATE, GlobalWorldLayer.TOPIC,
                GlobalMemoryNamespace.PROJECT, "galaxyssi", "GalaxySSI project",
                "Project GalaxySSI current state is $marker"
            )
        }
        val query = when (mode) {
            0 -> "What is my name and identity?"
            1 -> "What response style do I prefer?"
            2 -> "What is my phone device?"
            else -> "What is the current project GalaxySSI state?"
        }
        val prompt = GlobalMemoryPromptCompiler.compile(
            PersonalWorldModel(items = listOf(item)),
            GlobalTopicProjectGraph(),
            GlobalEntityMemoryGraph(),
            query,
            "matrix-conversation"
        )
        check(prompt.contains(marker))
        check(prompt.contains("untrusted evidence"))
    }

    private fun currentConversationRetrievalScenario(index: Int) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = AgentTranscriptStore(context)
        val marker = "current-session-marker-$index-${UUID.randomUUID()}"
        val conversation = store.createConversation("临时上下文检索-$index")
        try {
            check(store.append(
                role = AgentTranscriptRole.USER,
                text = "Current context question $marker",
                dedupeKey = "matrix-current-user-$marker",
                conversationId = conversation.id,
                turnId = "matrix-current-turn-$index"
            ))
            check(store.append(
                role = AgentTranscriptRole.ASSISTANT,
                text = "Current context answer $marker",
                dedupeKey = "matrix-current-assistant-$marker",
                conversationId = conversation.id,
                turnId = "matrix-current-turn-$index"
            ))
            val restored = AgentTranscriptStore(context).context(conversation.id)
            check(restored.turns.size == 2)
            check(restored.turns.all { it.text.contains(marker) })
            check(restored.asPromptBlock().contains(marker))
        } finally {
            check(store.deleteConversation(conversation.id))
        }
    }

    private fun schedulerScenario(index: Int) {
        if (index < 40) {
            val mode = AndroidCognitionWorkMode.entries[index % AndroidCognitionWorkMode.entries.size]
            val plan = AndroidCognitionSchedulePolicy.workPlan(mode)
            when (mode) {
                AndroidCognitionWorkMode.EVENT -> check(
                    plan.eventLimit == 12 && !plan.runBatchCognition && !plan.projectKnowledge
                )
                AndroidCognitionWorkMode.SCHEDULED -> check(
                    plan.eventLimit == 48 && plan.runBatchCognition && plan.cycleCount == 1 && plan.projectKnowledge
                )
                AndroidCognitionWorkMode.EXPLICIT -> check(
                    plan.eventLimit == 200 && plan.runBatchCognition && plan.cycleCount == 2 && plan.projectKnowledge
                )
                AndroidCognitionWorkMode.PROJECTION -> check(
                    plan.eventLimit == 0 && !plan.runBatchCognition && plan.projectKnowledge
                )
            }
            return
        }
        val branch = index % 4
        val delay = AndroidCognitionSchedulePolicy.nextExplorationDelayMillis(
            pendingEvents = if (branch == 0) index + 1 else 0,
            activeCognition = if (branch == 1) index + 1 else 0,
            activeResearch = 0,
            pendingInsights = if (branch == 2) index + 1 else 0
        )
        val expected = when (branch) {
            0, 1 -> AndroidCognitionSchedulePolicy.MIN_DELAY_MILLIS
            2 -> 30L * 60L * 1_000L
            else -> AndroidCognitionSchedulePolicy.MAX_DELAY_MILLIS
        }
        check(delay == expected)
        check(delay in AndroidCognitionSchedulePolicy.MIN_DELAY_MILLIS..AndroidCognitionSchedulePolicy.MAX_DELAY_MILLIS)
    }

    private fun memoryEvolutionScenario(index: Int) {
        val variant = index % 4
        val eventId = "matrix-evolution-$index"
        val privateEvent = variant == 2
        val kind = if (variant == 1) GlobalWorldItemKind.PREFERENCE else GlobalWorldItemKind.FACT
        val layer = if (variant == 1) GlobalWorldLayer.USER else GlobalWorldLayer.TOPIC
        val value = if (privateEvent) "Private matrix secret $index" else "Matrix durable fact $index"
        val event = GlobalConversationEvent(
            id = eventId,
            type = GlobalConversationEventType.MEMORY_CREATED,
            conversationId = "matrix-conversation-${index % 8}",
            actor = GlobalConversationActor.USER,
            timestampMillis = 10_000L + index,
            content = value,
            sensitivity = if (privateEvent) {
                GlobalConversationSensitivity.SESSION_PRIVATE
            } else GlobalConversationSensitivity.PERSONAL,
            metadata = if (variant == 1) mapOf("memory_kind" to AgentMemoryKind.PREFERENCE.name) else emptyMap()
        )
        val item = worldItem(
            index, kind, layer,
            if (variant == 1) GlobalMemoryNamespace.USER else GlobalMemoryNamespace.GENERAL,
            if (variant == 1) "self" else "",
            if (variant == 1) "Response preference" else "Matrix fact",
            value,
            event
        )
        val reduction = GlobalWorldReduction(
            world = PersonalWorldModel(
                items = listOf(item),
                processedEventIds = listOf(event.id),
                updatedAtMillis = event.timestampMillis
            ),
            changedItems = listOf(item),
            conflicts = emptyList()
        )
        val understanding = GlobalUnderstanding(
            eventId = event.id,
            topic = item.topic,
            intent = "conversation",
            preferenceCandidates = if (variant == 1) listOf(value) else emptyList()
        )
        val evolved = GlobalMemoryEvolutionPolicy.evolve(
            PersonalWorldModel(), reduction, GlobalMemoryInbox(), event, understanding
        )

        check(event.id in evolved.inbox.processedEventIds)
        check(evolved.records.size == evolved.candidates.size)
        check(evolved.candidates.isNotEmpty())
        when (variant) {
            0 -> check(evolved.candidates.single().status == GlobalMemoryCandidateStatus.AUTO_MERGED)
            1 -> {
                check(evolved.candidates.single().status == GlobalMemoryCandidateStatus.PENDING_REVIEW)
                check(evolved.reduction.world.items.none { it.value == value })
            }
            2 -> {
                check(evolved.candidates.single().risk == GlobalMemoryCandidateRisk.PRIVATE_BLOCKED)
                check(evolved.reduction.world.items.none { it.value.contains(value) })
                check(evolved.candidates.single().item.value.isBlank())
            }
            else -> {
                val duplicate = GlobalMemoryEvolutionPolicy.evolve(
                    evolved.reduction.world,
                    evolved.reduction,
                    evolved.inbox,
                    event,
                    understanding
                )
                check(duplicate.candidates.isEmpty())
            }
        }
        GlobalMemorySupersessionPolicy.inspect(evolved.reduction.world).requireSafe()
        GlobalMemoryInboxIsolationPolicy.inspect(
            evolved.reduction.world,
            GlobalTopicProjectGraph(),
            GlobalEntityMemoryGraph(),
            evolved.inbox
        ).requireSafe()
    }

    private fun graphMemoryScenario(index: Int) {
        val event = GlobalConversationEvent(
            id = "matrix-graph-$index",
            type = GlobalConversationEventType.MESSAGE_CREATED,
            conversationId = "matrix-graph-conversation-${index % 12}",
            actor = GlobalConversationActor.USER,
            timestampMillis = 20_000L + index,
            content = "GalaxySSI supports MatrixFeature$index",
            conversationTitle = "GalaxySSI Matrix $index"
        )
        val item = worldItem(
            index,
            GlobalWorldItemKind.FACT,
            GlobalWorldLayer.TOPIC,
            GlobalMemoryNamespace.PROJECT,
            "galaxyssi",
            "GalaxySSI Matrix $index",
            event.content,
            event
        )
        val reduction = GlobalWorldReduction(
            PersonalWorldModel(listOf(item), processedEventIds = listOf(event.id), updatedAtMillis = event.timestampMillis),
            listOf(item),
            emptyList()
        )
        val understanding = GlobalUnderstanding(
            eventId = event.id,
            topic = item.topic,
            project = "GalaxySSI",
            relatedTopics = setOf("MatrixFeature$index"),
            intent = "conversation",
            entities = setOf("GalaxySSI", "MatrixFeature$index"),
            durableFollowUpUseful = index % 2 == 0
        )
        val topicGraph = GlobalTopicProjectGraphReducer.reduce(
            GlobalTopicProjectGraph(), event, understanding, reduction
        )
        val entityGraph = GlobalEntityMemoryGraphReducer.reduce(
            GlobalEntityMemoryGraph(), event, understanding, reduction
        )
        check(event.id in topicGraph.processedEventIds)
        check(event.id in entityGraph.processedEventIds)
        check(topicGraph.nodes.isNotEmpty())
        check(entityGraph.nodes.isNotEmpty())
        check(topicGraph.relations.all { relation ->
            topicGraph.nodes.any { it.id == relation.fromNodeId } &&
                topicGraph.nodes.any { it.id == relation.toNodeId }
        })
        check(entityGraph.relations.all { relation ->
            entityGraph.nodes.any { it.id == relation.fromNodeId } &&
                entityGraph.nodes.any { it.id == relation.toNodeId }
        })
        if (index % 3 == 0) {
            val duplicateTopic = GlobalTopicProjectGraphReducer.reduce(topicGraph, event, understanding, reduction)
            val duplicateEntity = GlobalEntityMemoryGraphReducer.reduce(entityGraph, event, understanding, reduction)
            check(duplicateTopic == topicGraph)
            check(duplicateEntity == entityGraph)
        }
    }

    private fun knowledgeIndexScenarios(
        count: Int,
        runScenario: (Int, () -> Unit) -> Unit
    ): Int {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = SharedPreferencesAgentKnowledgeStore(context)
        val marker = "matrixknowledge${UUID.randomUUID().toString().replace("-", "")}"
        val items = (0 until 20).map { index ->
            AgentKnowledgeItem(
                id = "$marker-$index",
                kind = AgentKnowledgeKind.NOTE,
                title = "$marker topic$index",
                content = "Verified Android cognition knowledge $marker topic$index detail$index",
                source = "device-test:$marker",
                tags = listOf(marker, "topic$index"),
                summary = "Summary $marker topic$index",
                updatedAtMillis = 30_000L + index
            )
        }
        return try {
            items.forEach(store::upsert)
            repeat(count) { index ->
                runScenario(index) {
                    val expected = items[index % items.size]
                    val query = "$marker topic${index % items.size}"
                    val hit = store.searchRanked(query, limit = 5).firstOrNull()
                    check(hit != null)
                    check(hit.item.id == expected.id)
                    check(hit.score >= 1.2)
                    check(hit.excerpt.isNotBlank())
                    val snapshot = store.querySnapshot(query, limit = 3)
                    check(snapshot.items.first().id == expected.id)
                    check(snapshot.stats.itemCount >= items.size)
                }
            }
            count
        } finally {
            store.delete(marker)
        }
    }

    private fun skillScenarios(
        count: Int,
        runScenario: (Int, () -> Unit) -> Unit
    ): Int {
        val runtime = AgentSkillRuntime(availableNativeToolIds = setOf("web.search"))
        repeat(5) { slot ->
            runtime.install(
                AgentSkillManifest(
                    id = "matrix-news-$slot",
                    version = "1.0.0",
                    title = "Matrix news $slot",
                    description = "Find current technology news for matrix category $slot",
                    instructions = "Search current public news.",
                    nativeTools = setOf("web.search"),
                    parameters = AgentSkillParameterSchema.objectSchema(
                        properties = mapOf("request" to AgentSkillParameterSchema.string()),
                        required = setOf("request")
                    ),
                    steps = listOf(
                        AgentSkillStep("search", "web.search", mapOf("query" to "{{parameters.request}}"))
                    ),
                    autoInvoke = true,
                    triggerExamples = listOf("Find matrix technology news category $slot"),
                    negativeExamples = listOf("Open saved matrix news file $slot")
                )
            )
        }
        val matcher = AgentSkillMatcher(runtime)
        repeat(count) { index ->
            runScenario(index) {
                when {
                    index < 10 -> check(AgentSkillCommandParser.isSaveCommand("Save this as a Skill"))
                    index < 20 -> check(!AgentSkillCommandParser.isSaveCommand("Do not save this as a Skill"))
                    index % 2 == 0 -> check(
                        matcher.match("Find matrix technology news category ${index % 5}") != null
                    )
                    else -> check(matcher.match("Open saved matrix news file ${index % 5}") == null)
                }
            }
        }
        return count
    }

    private fun knowledgeGapScenario(index: Int) {
        val content = when {
            index < 40 -> "Research the latest official documentation for Android cognition feature $index"
            index < 60 -> "Continuously monitor and track the latest GalaxySSI research feature $index"
            else -> "GalaxySSI local note number $index"
        }
        val event = GlobalConversationEvent(
            id = "matrix-gap-$index",
            type = GlobalConversationEventType.MESSAGE_CREATED,
            conversationId = "matrix-gap",
            actor = GlobalConversationActor.USER,
            timestampMillis = 40_000L + index,
            content = content,
            conversationTitle = "Knowledge gap $index"
        )
        val understanding = GlobalUnderstandingPipeline().understand(event, PersonalWorldModel())
        val task = GlobalResearchPlanner.plan(event, understanding)
        when {
            index < 40 -> {
                check(understanding.externalResearchUseful)
                check(task != null)
                check(task.preferredSources.contains("official"))
            }
            index < 60 -> {
                check(understanding.externalResearchUseful)
                check(understanding.durableFollowUpUseful)
                check(task?.depth == GlobalResearchDepth.CONTINUOUS_MONITOR)
            }
            else -> {
                check(!understanding.externalResearchUseful)
                check(!understanding.durableFollowUpUseful)
                check(task == null)
            }
        }
    }

    private fun proactiveCognitionScenario(index: Int) {
        val hidden = index >= 60
        val kind = if (index % 2 == 0) GlobalWorldItemKind.RISK else GlobalWorldItemKind.OPPORTUNITY
        val item = GlobalWorldItem(
            id = "matrix-proactive-item-$index",
            stableKey = "matrix-proactive-$index",
            kind = kind,
            layer = GlobalWorldLayer.TOPIC,
            topic = "Matrix proactive topic $index",
            value = if (kind == GlobalWorldItemKind.RISK) {
                "Material security risk $index"
            } else "High value opportunity $index",
            confidence = 0.90,
            contextVisibility = if (hidden) {
                GlobalWorldContextVisibility.LOCAL_ONLY
            } else GlobalWorldContextVisibility.SHAREABLE,
            evidenceCount = 2,
            conversationIds = setOf("matrix-proactive-conversation-$index"),
            evidenceEventIds = listOf("matrix-proactive-event-$index"),
            lastSeenAtMillis = 50_000L + index
        )
        val candidates = GlobalProactiveDiscoveryPolicy.scan(
            world = PersonalWorldModel(items = listOf(item)),
            goals = emptyList(),
            excludedConversationIds = emptySet(),
            nowMillis = 60_000L + index
        )
        if (hidden) {
            check(candidates.isEmpty())
            return
        }
        check(candidates.size == 1)
        val selected = GlobalProactiveDiscoveryPolicy.selectForDeliberation(
            candidates,
            GlobalProactiveDiscoveryState(),
            emptyList(),
            GlobalAgentSettings(dailyDiscoveryTaskBudget = 3),
            60_000L + index
        )
        check(selected.size == 1)
        val task = GlobalProactiveDiscoveryPolicy.task(selected.single(), 60_000L + index)
        check(task.sourceEvent.causalEventIds.contains("matrix-proactive-event-$index"))
        check(task.baselineUnderstanding.durableFollowUpUseful)
    }

    private fun memoryCriticScenario(index: Int) {
        val now = 80_000L + index
        val variant = index % 4
        val item = GlobalWorldItem(
            id = "matrix-critic-item-$index",
            stableKey = "matrix-critic-$index",
            kind = when (variant) {
                2 -> GlobalWorldItemKind.DECISION
                3 -> GlobalWorldItemKind.GOAL
                else -> GlobalWorldItemKind.FACT
            },
            layer = GlobalWorldLayer.TOPIC,
            topic = "Matrix critic $index",
            value = "Matrix critic evidence $index",
            confidence = if (variant == 1) 0.35 else 0.90,
            evidenceCount = if (variant in setOf(1, 2)) 3 else 1,
            conversationIds = setOf("matrix-critic"),
            evidenceEventIds = listOf("matrix-critic-event-$index"),
            status = if (variant == 3) GlobalWorldItemStatus.COMPLETED else GlobalWorldItemStatus.ACTIVE,
            expiresAtMillis = if (variant == 0) now - 1 else 0L
        )
        val (audited, report) = GlobalMemoryCritic.audit(
            PersonalWorldModel(items = listOf(item)),
            GlobalMemoryInbox(),
            now
        )
        when (variant) {
            0 -> {
                check(audited.items.single().status == GlobalWorldItemStatus.SUPERSEDED)
                check(report.findings.any { it.kind == GlobalMemoryAuditFindingKind.EXPIRED })
            }
            1 -> check(report.findings.any { it.kind == GlobalMemoryAuditFindingKind.LOW_CONFIDENCE_REUSED })
            2 -> check(report.findings.any { it.kind == GlobalMemoryAuditFindingKind.SKILL_CANDIDATE })
            else -> check(report.findings.any { it.kind == GlobalMemoryAuditFindingKind.COMPLETED_GOAL })
        }
        check(report.auditedItemCount == 1)
    }

    private fun obsidianScenario(index: Int) {
        when (index / 8) {
            0 -> {
                val value = "GalaxySSI Android knowledge note $index with verified evidence"
                check(ObsidianProjectionPrivacyPolicy.safeKnowledge(value))
                check(ObsidianProjectionPrivacyPolicy.transcriptText(value) == value)
            }
            1 -> {
                val source = "https://example.test/reading/$index"
                val value = "Verified reading record $index about Android cognition"
                check(ObsidianProjectionPrivacyPolicy.safeMetadata(source))
                check(ObsidianProjectionPrivacyPolicy.safeKnowledge(value))
                check(AgentKnowledgeItem(
                    kind = AgentKnowledgeKind.DOCUMENT,
                    title = "Reading $index",
                    content = value,
                    source = source
                ).source.startsWith("https://"))
            }
            2 -> {
                val runtime = AgentSkillRuntime(availableNativeToolIds = setOf("web.search"))
                val id = "obsidian-matrix-skill-$index"
                runtime.install(AgentSkillManifest(
                    id = id,
                    version = "1.0.0",
                    title = "Obsidian matrix skill $index",
                    description = "Reusable verified research flow $index",
                    instructions = "Search official sources and preserve citations.",
                    nativeTools = setOf("web.search"),
                    parameters = AgentSkillParameterSchema.objectSchema(),
                    steps = listOf(AgentSkillStep("search", "web.search"))
                ))
                check(runtime.list().any { it.manifest.id == id })
                check(ObsidianProjectionPrivacyPolicy.safeKnowledge(
                    "Search official sources and preserve citations."
                ))
            }
            3 -> {
                val kind = listOf(
                    GlobalWorldItemKind.GOAL,
                    GlobalWorldItemKind.TASK,
                    GlobalWorldItemKind.DECISION
                )[index % 3]
                val plan = worldItem(
                    index = index,
                    kind = kind,
                    layer = GlobalWorldLayer.TOPIC,
                    namespace = GlobalMemoryNamespace.PROJECT,
                    namespaceId = "galaxyssi",
                    topic = "Obsidian plan $index",
                    value = "Verified Android plan item $index"
                )
                check(plan.status != GlobalWorldItemStatus.SUPERSEDED)
                check(ObsidianProjectionPrivacyPolicy.safeKnowledge(plan.value))
            }
            else -> {
                val insight = GlobalProactiveMessage(
                    sourceEventId = "obsidian-insight-event-$index",
                    sourceConversationId = "obsidian-insight-conversation-$index",
                    target = GlobalProactiveTarget.GLOBAL_DIGEST,
                    title = "Verified insight $index",
                    content = "A relevant Android cognition insight $index is ready for review.",
                    topic = "Android cognition",
                    urgent = index % 2 == 0
                )
                check(insight.status == GlobalProactiveMessageStatus.PENDING)
                check(ObsidianProjectionPrivacyPolicy.safeMetadata(insight.title))
                check(ObsidianProjectionPrivacyPolicy.safeKnowledge(insight.content))
            }
        }
    }

    private fun worldItem(
        index: Int,
        kind: GlobalWorldItemKind,
        layer: GlobalWorldLayer,
        namespace: GlobalMemoryNamespace,
        namespaceId: String,
        topic: String,
        value: String,
        event: GlobalConversationEvent? = null
    ): GlobalWorldItem {
        val eventId = event?.id ?: "matrix-world-event-$index"
        val conversationId = event?.conversationId ?: "matrix-world-conversation-$index"
        val timestamp = event?.timestampMillis ?: 1_000L + index
        return GlobalWorldItem(
            id = "matrix-world-item-$index-${kind.name}",
            stableKey = "matrix-world-$index-${kind.name}",
            kind = kind,
            layer = layer,
            namespace = namespace,
            namespaceId = namespaceId,
            topic = topic,
            value = value,
            confidence = 0.92,
            conversationIds = setOf(conversationId),
            evidenceEventIds = listOf(eventId),
            evidenceProvenance = listOf(
                GlobalEvidenceRef(eventId, setOf(eventId), conversationId, timestamp)
            ),
            firstSeenAtMillis = timestamp,
            lastSeenAtMillis = timestamp
        )
    }

    private fun requireSmT575() {
        val normalizedModel = Build.MODEL.replace('_', '-').uppercase()
        check(normalizedModel == "SM-T575" && Build.DEVICE.equals("gtactive3", ignoreCase = true)) {
            "This persistent 1,000-conversation matrix may run only on SM-T575; " +
                "actual model=${Build.MODEL}, device=${Build.DEVICE}"
        }
    }

    private data class ScenarioOutcome(
        val group: String,
        val index: Int,
        val passed: Boolean,
        val detail: String
    )

    private class VisibleScenarioConversationRecorder(context: Context) {
        private val appContext = context.applicationContext
        private val store = AgentTranscriptStore(appContext)

        fun replace(
            outcomes: List<ScenarioOutcome>,
            counts: Map<String, Int>
        ): JSONObject {
            check(outcomes.size == EXPECTED_VISIBLE_CONVERSATIONS)
            val removedLegacyEvents = removeLegacyPrivateDeletionEvents()
            val cleanupStartedAt = SystemClock.elapsedRealtime()
            val previous = store.conversations(includeArchived = true)
                .filter { it.title.startsWith(VISIBLE_TITLE_PREFIX) }
            check(store.deleteConversations(previous) == previous.size) {
                "Could not remove all ${previous.size} previous visible matrix conversations"
            }

            val createdIds = ArrayList<String>(outcomes.size)
            val startedAt = SystemClock.elapsedRealtime()
            outcomes.forEachIndexed { position, outcome ->
                val ordinal = position + 1
                val displayGroup = visibleGroupName(outcome)
                val description = scenarioDescription(outcome)
                val title = "$VISIBLE_TITLE_PREFIX${ordinal.toString().padStart(4, '0')} · $displayGroup"
                val conversation = store.createConversation(title, privateMode = true)
                val turnId = "sm-t575-visible-matrix-${ordinal.toString().padStart(4, '0')}"
                check(store.append(
                    role = AgentTranscriptRole.USER,
                    text = buildString {
                        append("真机验收用例 #").append(ordinal.toString().padStart(4, '0')).append('\n')
                        append("模块：").append(displayGroup).append('\n')
                        append("验证目标：").append(description).append('\n')
                        append("设备限定：SM-T575")
                    },
                    dedupeKey = "$turnId:user",
                    conversationId = conversation.id,
                    turnId = turnId,
                    taskId = VISIBLE_MATRIX_TASK_ID
                ))
                check(store.append(
                    role = AgentTranscriptRole.ASSISTANT,
                    text = buildString {
                        append(if (outcome.passed) "PASS" else "FAIL")
                        append(" · SM-T575 真机执行\n")
                        append("结果：")
                        if (outcome.passed) append("验证通过") else append(outcome.detail.ifBlank { "未知失败" })
                        append("\n测试编号：").append(outcome.group).append('[').append(outcome.index).append(']')
                    },
                    dedupeKey = "$turnId:assistant",
                    conversationId = conversation.id,
                    turnId = turnId,
                    taskId = VISIBLE_MATRIX_TASK_ID
                ))
                createdIds += conversation.id
                if (ordinal % VISIBLE_PROGRESS_INTERVAL == 0 || ordinal == outcomes.size) {
                    Log.i(
                        LOG_TAG,
                        "visible_progress $ordinal/${outcomes.size} " +
                            "elapsed=${SystemClock.elapsedRealtime() - startedAt}ms pss=${Debug.getPss()}KiB"
                    )
                }
            }

            val matching = store.conversations(includeArchived = true)
                .filter { it.title.startsWith(VISIBLE_TITLE_PREFIX) }
            val matchingIds = matching.mapTo(hashSetOf(), AgentConversation::id)
            assertEquals(EXPECTED_VISIBLE_CONVERSATIONS, matching.size)
            assertEquals(EXPECTED_VISIBLE_CONVERSATIONS, matching.map(AgentConversation::title).distinct().size)
            assertTrue(matchingIds.containsAll(createdIds))
            assertTrue(matching.all { it.status == AgentConversationStatus.ACTIVE })
            assertTrue(matching.all(AgentConversation::privateMode))
            assertTrue(matching.all { it.latestMessagePreview.startsWith("PASS") || it.latestMessagePreview.startsWith("FAIL") })
            val visibleMessages = matching.sumOf { conversation ->
                store.page(conversation.id, pageSize = 3).entries.size
            }
            assertEquals(EXPECTED_VISIBLE_MESSAGES, visibleMessages)

            val report = JSONObject()
                .put("device_model", Build.MODEL)
                .put("device_name", Build.DEVICE)
                .put("visible_conversations", matching.size)
                .put("private_conversations", matching.count(AgentConversation::privateMode))
                .put("visible_messages", visibleMessages)
                .put("passed", outcomes.count(ScenarioOutcome::passed))
                .put("failed", outcomes.count { !it.passed })
                .put("legacy_private_deletion_events_removed", removedLegacyEvents)
                .put("cleanup_count", previous.size)
                .put("cleanup_elapsed_ms", startedAt - cleanupStartedAt)
                .put("write_elapsed_ms", SystemClock.elapsedRealtime() - startedAt)
                .put("final_pss_kib", Debug.getPss())
                .put("counts", JSONObject(counts))
                .put("conversation_ids", JSONArray(createdIds))
            val reportDirectory = File(appContext.filesDir, VISIBLE_REPORT_DIRECTORY)
            check(reportDirectory.mkdirs() || reportDirectory.isDirectory)
            File(reportDirectory, VISIBLE_REPORT_FILE).writeText(report.toString(2))
            return report
        }

        private fun removeLegacyPrivateDeletionEvents(): Int {
            val repository = GlobalAgentRepository(appContext)
            val snapshot = repository.exportSnapshot()
            val eventIds = buildSet {
                listOf("events", "event_overflow", "context_journal").forEach { key ->
                    val events = snapshot.optJSONArray(key) ?: return@forEach
                    for (index in 0 until events.length()) {
                        val event = events.optJSONObject(index) ?: continue
                        if (
                            event.optString("type") == GlobalConversationEventType.CONVERSATION_DELETED.name &&
                            event.optString("sensitivity") == GlobalConversationSensitivity.SESSION_PRIVATE.name
                        ) {
                            event.optString("id").takeIf(String::isNotBlank)?.let(::add)
                        }
                    }
                }
            }
            repository.removeEvents(eventIds)
            repository.removeContextJournalEvents(eventIds)
            return eventIds.size
        }

        private fun visibleGroupName(outcome: ScenarioOutcome): String = when (outcome.group) {
            "foreground_core_memory" -> if (outcome.index < 8) {
                "前台·跨会话核心记忆"
            } else "前台·核心记忆"
            "foreground_prompt_compiler" -> if (outcome.index < 20) {
                "前台·当前会话检索"
            } else "前台·Prompt Compiler"
            "background_scheduler_and_ingestion" -> if (outcome.index < 40) {
                "前台·事件快速入库"
            } else "后台·认知调度"
            "background_memory_evolution" -> "后台·记忆整理与演化"
            "background_graph_memory" -> "后台·Graph Memory"
            "background_knowledge_index" -> "后台·知识索引"
            "background_skills" -> "后台·Skills 提取"
            "background_knowledge_gap_and_research" -> when {
                outcome.index < 40 -> "后台·主动研究"
                outcome.index < 60 -> "后台·持续研究"
                else -> "后台·知识空白检测"
            }
            "proactive_cognition_loop" -> "主动认知·观察到规划"
            "background_memory_critic" -> "后台·Memory Critic"
            "obsidian_knowledge_projection" -> listOf(
                "Obsidian·知识笔记",
                "Obsidian·阅读记录",
                "Obsidian·Skills",
                "Obsidian·计划",
                "Obsidian·洞察"
            )[(outcome.index / 8).coerceIn(0, 4)]
            else -> outcome.group
        }

        private fun scenarioDescription(outcome: ScenarioOutcome): String = when (outcome.group) {
            "foreground_core_memory" -> when {
                outcome.index < 8 -> "A 会话写入临时加密核心记忆，B 新会话通过 Prompt 与 Agent transport 读取，随后清理测试记忆"
                outcome.index < 32 -> "识别明确姓名表达并生成规范身份记忆候选"
                outcome.index < 56 -> "识别当前设备信息并生成设备记忆候选"
                outcome.index < 80 -> "识别当前项目状态并生成项目记忆候选"
                outcome.index < 92 -> "识别明确偏好并生成稳定偏好键"
                else -> "检测敏感凭据并阻止其进入即时核心记忆"
            }
            "foreground_prompt_compiler" -> when {
                outcome.index < 20 -> "从正式会话数据库恢复当前会话消息并编译为模型上下文"
                outcome.index < 40 -> "按隐私与暂停跟踪状态控制全局上下文注入"
                else -> "按身份、偏好、设备或项目查询编译有边界的长期记忆证据"
            }
            "background_scheduler_and_ingestion" -> if (outcome.index < 40) {
                "验证事件、定时、显式和 Obsidian 投影任务的快速入库执行计划"
            } else "根据积压事件、活跃认知、洞察和空闲状态计算下一次后台探索时间"
            "background_memory_evolution" -> "验证自动合并、待确认、私密阻断、幂等和 superseded 记忆演化"
            "background_graph_memory" -> "验证主题/项目图与实体图节点关系、证据完整性和幂等更新"
            "background_knowledge_index" -> "写入加密知识条目并验证排序检索、摘要、命中分数和快照统计"
            "background_skills" -> "验证 Skill 保存命令、负例、自动匹配和工具清单约束"
            "background_knowledge_gap_and_research" -> when {
                outcome.index < 40 -> "识别需要外部资料的知识空白并生成官方来源研究计划"
                outcome.index < 60 -> "识别持续跟踪需求并生成连续研究任务"
                else -> "对本地已知内容避免无价值联网研究"
            }
            "proactive_cognition_loop" -> "从风险或机会观察生成候选，经价值筛选后形成可追溯的主动认知任务"
            "background_memory_critic" -> "审计过期、低置信度复用、Skill 候选和已完成目标"
            "obsidian_knowledge_projection" -> when (outcome.index / 8) {
                0 -> "验证知识笔记可安全投影且正文保持可读"
                1 -> "验证带来源的阅读记录符合知识与元数据隐私策略"
                2 -> "验证可复用 Skill 的结构与内容可进入 Obsidian 知识层"
                3 -> "验证目标、任务和决策可作为计划条目投影"
                else -> "验证主动洞察的标题、正文和待处理状态可安全投影"
            }
            else -> outcome.group
        }
    }

    private companion object {
        const val LOG_TAG = "GalaxySSITestMatrix"
        const val VISIBLE_TITLE_PREFIX = "真机验收 "
        const val VISIBLE_MATRIX_TASK_ID = "sm-t575-visible-architecture-matrix"
        const val VISIBLE_MATRIX_MEMORY_SOURCE = "sm_t575_visible_matrix"
        const val VISIBLE_REPORT_DIRECTORY = "acceptance-reports"
        const val VISIBLE_REPORT_FILE = "sm-t575-visible-architecture-matrix.json"
        const val EXPECTED_VISIBLE_CONVERSATIONS = 1_000
        const val EXPECTED_VISIBLE_MESSAGES = 2_000
        const val VISIBLE_PROGRESS_INTERVAL = 100
    }
}
