package com.galaxyssi.chat

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test

class GlobalMemoryLoCoMoCorpusTest {
    @Test
    fun versionedCorpusMeetsLongTermMemoryContracts() {
        val root = repositoryRoot()
        val corpus = JSONObject(
            File(root, "benchmarks/memory/locomo-corpus.json").readText(Charsets.UTF_8)
        )
        require(corpus.getInt("schema_version") == 1)
        val results = JSONArray()
        val categories = linkedSetOf<String>()
        var passedAssertions = 0
        var totalAssertions = 0

        corpus.getJSONArray("timelines").objects().forEach { timeline ->
            val world = PersonalWorldModel(
                items = timeline.getJSONArray("items").objects().map(::worldItem)
            )
            timeline.getJSONArray("queries").objects().forEach { query ->
                val context = GlobalMemoryPromptCompiler.compile(
                    world = world,
                    topicGraph = GlobalTopicProjectGraph(),
                    entityGraph = GlobalEntityMemoryGraph(),
                    query = query.getString("query"),
                    currentConversationId = query.getString("conversation_id")
                )
                val assertions = JSONArray()
                query.optJSONArray("include").strings().forEach { expected ->
                    assertions.put(assertion("include", expected, context.contains(expected)))
                }
                query.optJSONArray("exclude").strings().forEach { forbidden ->
                    assertions.put(assertion("exclude", forbidden, !context.contains(forbidden)))
                }
                query.optJSONArray("markers").strings().forEach { marker ->
                    assertions.put(assertion("marker", marker, context.contains(marker)))
                }
                if (query.optBoolean("expect_empty", false)) {
                    assertions.put(assertion("empty", "", context.isBlank()))
                }
                val assertionObjects = assertions.objects()
                passedAssertions += assertionObjects.count { it.getBoolean("passed") }
                totalAssertions += assertionObjects.size
                val category = query.getString("category")
                categories += category
                results.put(
                    JSONObject()
                        .put("query_id", query.getString("id"))
                        .put("timeline_id", timeline.getString("id"))
                        .put("category", category)
                        .put("passed", assertionObjects.all { it.getBoolean("passed") })
                        .put("context", context)
                        .put("assertions", assertions)
                )
            }
        }

        val requiredCategories = corpus.getJSONArray("required_categories").strings().toSet()
        val score = if (totalAssertions == 0) 0.0 else {
            passedAssertions.toDouble() / totalAssertions.toDouble()
        }
        val report = JSONObject()
            .put("schema_version", 1)
            .put("benchmark_id", corpus.getString("benchmark_id"))
            .put("scenario_count", results.length())
            .put("passed_assertions", passedAssertions)
            .put("total_assertions", totalAssertions)
            .put("score", score)
            .put("categories", JSONArray(categories.toList()))
            .put("results", results)
        val output = File(root, "build/reports/memory-locomo/raw-results.json")
        output.parentFile?.mkdirs()
        output.writeText(report.toString(2), Charsets.UTF_8)

        val failures = results.objects()
            .filterNot { it.getBoolean("passed") }
            .joinToString("\n") { result ->
                val failed = result.getJSONArray("assertions").objects()
                    .filterNot { it.getBoolean("passed") }
                    .joinToString { "${it.getString("type")}:${it.getString("value")}" }
                "${result.getString("query_id")}: $failed"
            }
        assertTrue(
            "LoCoMo corpus categories are incomplete: ${requiredCategories - categories}",
            categories.containsAll(requiredCategories)
        )
        assertTrue(
            "LoCoMo corpus score $score is below ${corpus.getDouble("minimum_score")}\n$failures",
            score >= corpus.getDouble("minimum_score") && failures.isBlank()
        )
    }

    private fun worldItem(value: JSONObject): GlobalWorldItem {
        val id = value.getString("id")
        val eventId = "$id-event"
        val conversationId = value.getString("conversation_id")
        val kind = GlobalWorldItemKind.valueOf(value.getString("kind"))
        val topic = value.getString("topic")
        val itemValue = value.getString("value")
        return GlobalWorldItem(
            id = id,
            stableKey = GlobalAgentText.stableKey(kind.name, topic, itemValue),
            kind = kind,
            layer = GlobalWorldLayer.valueOf(value.getString("layer")),
            namespace = GlobalMemoryNamespace.valueOf(value.optString("namespace", "GENERAL")),
            namespaceId = value.optString("namespace_id", "").orEmpty(),
            topic = topic,
            value = itemValue,
            confidence = value.optDouble("confidence", 0.9),
            contextVisibility = GlobalWorldContextVisibility.valueOf(
                value.optString("visibility", "SHAREABLE")
            ),
            conversationIds = setOf(conversationId),
            evidenceEventIds = listOf(eventId),
            evidenceProvenance = listOf(
                GlobalEvidenceRef(eventId, setOf(eventId), conversationId, 1_000L)
            ),
            status = GlobalWorldItemStatus.valueOf(value.optString("status", "ACTIVE")),
            temporalState = GlobalMemoryTemporalState.valueOf(
                value.optString("temporal_state", "CURRENT")
            ),
            conflictGroupId = value.optString("conflict_group_id"),
            firstSeenAtMillis = 1_000L,
            lastSeenAtMillis = 2_000L
        )
    }

    private fun assertion(type: String, value: String, passed: Boolean): JSONObject =
        JSONObject()
            .put("type", type)
            .put("value", value)
            .put("passed", passed)

    private fun repositoryRoot(): File {
        var candidate = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        repeat(8) {
            if (File(candidate, "benchmarks/memory/locomo-corpus.json").isFile) {
                return candidate
            }
            candidate = candidate.parentFile
                ?: error("Unable to locate the GalaxySSI repository root")
        }
        error("Unable to locate the GalaxySSI repository root")
    }

    private fun JSONArray?.objects(): List<JSONObject> =
        if (this == null) emptyList() else (0 until length()).map(::getJSONObject)

    private fun JSONArray?.strings(): List<String> =
        if (this == null) emptyList() else (0 until length()).map(::getString)
}
