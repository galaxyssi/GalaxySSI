package com.signalasi.chat

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class Pr2632AndroidArchitectureMatrixTest {
    @Test
    fun runsOneThousandArchitectureScenariosOnDevice() {
        val failures = mutableListOf<String>()
        val counts = linkedMapOf<String, Int>()

        fun runGroup(name: String, count: Int, scenario: (Int) -> Unit) {
            repeat(count) { index ->
                runCatching { scenario(index) }
                    .onFailure { error ->
                        failures += "$name[$index]: ${error.javaClass.simpleName}: ${error.message.orEmpty()}"
                    }
            }
            counts[name] = count
        }

        runGroup("foreground_core_memory", 100, ::coreMemoryScenario)
        runGroup("foreground_prompt_compiler", 100, ::promptCompilerScenario)
        runGroup("background_scheduler_and_ingestion", 80, ::schedulerScenario)
        runGroup("background_memory_evolution", 160, ::memoryEvolutionScenario)
        runGroup("background_graph_memory", 120, ::graphMemoryScenario)
        knowledgeIndexScenarios(100, failures).also { counts["background_knowledge_index"] = it }
        skillScenarios(100, failures).also { counts["background_skills"] = it }
        runGroup("background_knowledge_gap_and_research", 80, ::knowledgeGapScenario)
        runGroup("proactive_cognition_loop", 80, ::proactiveCognitionScenario)
        runGroup("background_memory_critic", 40, ::memoryCriticScenario)
        runGroup("obsidian_knowledge_projection", 40, ::obsidianScenario)

        val total = counts.values.sum()
        Log.i(LOG_TAG, "scenario_summary total=$total counts=$counts failures=${failures.size}")
        failures.take(30).forEach { failure -> Log.e(LOG_TAG, failure) }
        assertEquals(1_000, total)
        assertTrue(
            "${failures.size} of $total architecture scenarios failed:\n${failures.take(30).joinToString("\n")}",
            failures.isEmpty()
        )
    }

    private fun coreMemoryScenario(index: Int) {
        when {
            index < 30 -> {
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
            index < 55 -> {
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
            index < 90 -> {
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

    private fun promptCompilerScenario(index: Int) {
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
                GlobalMemoryNamespace.PROJECT, "signalasi", "SignalASI project",
                "Project SignalASI current state is $marker"
            )
        }
        val query = when (mode) {
            0 -> "What is my name and identity?"
            1 -> "What response style do I prefer?"
            2 -> "What is my phone device?"
            else -> "What is the current project SignalASI state?"
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
            content = "SignalASI supports MatrixFeature$index",
            conversationTitle = "SignalASI Matrix $index"
        )
        val item = worldItem(
            index,
            GlobalWorldItemKind.FACT,
            GlobalWorldLayer.TOPIC,
            GlobalMemoryNamespace.PROJECT,
            "signalasi",
            "SignalASI Matrix $index",
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
            project = "SignalASI",
            relatedTopics = setOf("MatrixFeature$index"),
            intent = "conversation",
            entities = setOf("SignalASI", "MatrixFeature$index"),
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

    private fun knowledgeIndexScenarios(count: Int, failures: MutableList<String>): Int {
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
                runCatching {
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
                }.onFailure { error ->
                    failures += "background_knowledge_index[$index]: ${error.javaClass.simpleName}: ${error.message.orEmpty()}"
                }
            }
            count
        } finally {
            store.delete(marker)
        }
    }

    private fun skillScenarios(count: Int, failures: MutableList<String>): Int {
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
            runCatching {
                when {
                    index < 10 -> check(AgentSkillCommandParser.isSaveCommand("Save this as a Skill"))
                    index < 20 -> check(!AgentSkillCommandParser.isSaveCommand("Do not save this as a Skill"))
                    index % 2 == 0 -> check(
                        matcher.match("Find matrix technology news category ${index % 5}") != null
                    )
                    else -> check(matcher.match("Open saved matrix news file ${index % 5}") == null)
                }
            }.onFailure { error ->
                failures += "background_skills[$index]: ${error.javaClass.simpleName}: ${error.message.orEmpty()}"
            }
        }
        return count
    }

    private fun knowledgeGapScenario(index: Int) {
        val content = when {
            index < 40 -> "Research the latest official documentation for Android cognition feature $index"
            index < 60 -> "Continuously monitor and track the latest SignalASI research feature $index"
            else -> "SignalASI local note number $index"
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
        when {
            index < 20 -> {
                val value = "SignalASI Android knowledge note $index with verified source"
                check(ObsidianProjectionPrivacyPolicy.safeKnowledge(value))
                check(ObsidianProjectionPrivacyPolicy.transcriptText(value) == value)
            }
            index < 30 -> {
                val value = "mqtt_password=matrix-secret-$index"
                check(!ObsidianProjectionPrivacyPolicy.safeKnowledge(value))
                check(ObsidianProjectionPrivacyPolicy.transcriptText(value).contains("omitted"))
            }
            else -> {
                val value = "https://example.test/note?access_token=matrix-$index"
                check(!ObsidianProjectionPrivacyPolicy.safeMetadata(value))
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

    private companion object {
        const val LOG_TAG = "SignalASITestMatrix"
    }
}
