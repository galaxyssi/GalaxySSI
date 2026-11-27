package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TeamPlanWireTest {
    @Test fun explicitFinalAuditCannotPublishAnUnreviewedDraft() = runBlocking {
        for (objective in listOf("Compare schedules, then independently audit the final answer.",
            "请比较两份日程，并独立审核最后的答复。")) {
            val stages = mutableListOf<String>()
            try {
                runAutoGoalTeam(objective, { _, input ->
                    val p = JSONObject(input)
                    stages += p.getString("stage")
                    assertTrue(p.getBoolean("final_review_required"))
                    "WORK|-|Compare schedules\nSYNTHESIS|Report differences"
                })
                fail("The missing final reviewer must be reported")
            } catch (_: TeamFinalAuditMissing) { }
            assertEquals(listOf("plan"), stages)
        }
        for (text in listOf("Review the timetable.", "Do not independently review the final answer.",
            "Explain how to independently review the final answer.", "请翻译“独立审核最终答案”。", "不需要独立审核最终答复。"))
            assertFalse(text, AutoGoalTeamCommand.requestsFinalAudit(text))
    }
    private val local = "http://127.0.0.1:8080/v1/chat/completions"
    private val remote = "https://planner.example.invalid/v1/chat/completions"
    private val hardStyle = "llama.cpp-json-schema"
    private val objective = "Compare the two proposed schedules."
    private val legacy = "ROLE|cost|worker|-|Check cost\nROLE|check|reviewer|cost|Check totals\nSYNTHESIS|Compare totals"

    // Capture the real private prompts, including the two different prompts for stage "audit".
    private fun systemsFor(task: String): Map<String, String> = runBlocking {
        val systems = mutableMapOf<String, String>()
        runAutoGoalTeam(task, { system, input ->
            val stage = JSONObject(input).getString("stage")
            systems[stage] = system
            when (stage) {
                "plan" -> "WORK|-|Check cost\nREVIEW|1|Check totals\nSYNTHESIS|Compare totals"
                "role" -> """{"finding":"Totals checked."}"""
                "synthesis" -> """{"answer":"Report."}"""
                "audit" -> if (JSONObject(input).has("verified_table"))
                    """{"purpose":"Compare costs.","limitation":"Synthetic costs.","pass_all":["right"]}"""
                    else """{"verdict":"accept"}"""
                else -> error("Unexpected stage: $stage")
            }
        })
        systems
    }

    private val systems by lazy { systemsFor(objective) }
    private val planner get() = systems.getValue("plan")
    private fun wire(style: String) = checkNotNull(teamPlanWire(planner, local, style))
    private fun role(kind: String = "WORK", vararg parents: Int, task: String = "Check costs") =
        JSONObject().put("kind", kind).put("parents", JSONArray(parents.toList())).put("task", task)
    private fun plan(vararg roles: JSONObject, synthesis: String = "Report totals") =
        JSONObject().put("roles", JSONArray(roles.toList())).put("synthesis", synthesis)

    @Test fun onlyTheExactPlannerAndCanonicalNumericLoopbackRouteGetTheWire() {
        val table = systemsFor("Compare costs.\n|input|gate|left|right|\n|---|---|---|---|\n|sample|<2|2|1|")
        assertNotEquals(systems.getValue("audit"), table.getValue("audit"))
        for (style in listOf("openai", hardStyle)) {
            for (system in listOf(systems.getValue("role"), systems.getValue("synthesis"), systems.getValue("audit"),
                table.getValue("audit"), "plan", "other\n$planner", "$planner\n")) {
                assertNull(style, teamPlanWire(system, local, style))
            }
            for (endpoint in listOf(remote, local.replace("127.0.0.1", "localhost"),
                local.replace("127.0.0.1", "127.0.0.1.example.invalid"), local.replace("//", "//user@"),
                local.replace("127.0.0.1", "127.0.0.1@remote.invalid"), local.replace("http:", "ftp:"),
                local.replace("/v1/chat/completions", "/fixture"), "$local/", "$local?schema=true", "$local#plan",
                local.replace(":8080", ":0"), local.replace(":8080", ":65536"), local.replace(":8080", ":"), "not a URI")) {
                assertNull("$style: $endpoint", teamPlanWire(planner, endpoint, style))
            }
            assertNotNull(teamPlanWire(planner, "http://[::1]:8080/v1/chat/completions", style))
        }
        for (style in listOf("anthropic", "gemini", "unknown")) assertNull(style, teamPlanWire(planner, local, style))
    }

    @Test fun ordinaryOpenAiLoopbackAsksForJsonWithoutRequiringHttpSchemaSupport() {
        val soft = wire("openai")
        assertNull(soft.requestFormat)
        assertEquals("json_schema", soft.format.getString("type"))
        assertNotEquals(planner, soft.system)
        assertEquals("WORK|-|Check costs\nSYNTHESIS|Report totals", soft.decode(plan(role()).toString()))
    }

    @Test fun onlySoftModeAcceptsACompleteValidLegacyPlanWithoutRepair() {
        val soft = wire("openai")
        val hard = wire(hardStyle)
        val numbered = "WORK|-|Check cost\nREVIEW|1|Check totals\nSYNTHESIS|Compare totals"
        for (valid in listOf(legacy, numbered, "SYNTHESIS|Compare totals")) {
            assertEquals(valid, soft.decode(valid))
            assertThrows(valid, Exception::class.java) { hard.decode(valid) }
        }
        val json = plan().toString()
        for (invalid in listOf("WORK|-|Check cost", numbered.replace("REVIEW|1|", "REVIEW|2|"),
            legacy.replace("reviewer|cost|", "reviewer|missing|"), "Plan:\n$legacy", "$legacy\nextra",
            "$json\n$legacy", "$numbered\n$json", "{\"roles\":[\n$numbered")) {
            assertThrows(invalid, Exception::class.java) { soft.decode(invalid) }
            assertThrows(invalid, Exception::class.java) { hard.decode(invalid) }
        }
    }

    private fun fields(schema: JSONObject, vararg keys: String): JSONObject {
        assertEquals("object", schema.getString("type"))
        assertFalse(schema.getBoolean("additionalProperties"))
        val properties = schema.getJSONObject("properties")
        assertEquals(keys.toSet(), properties.keys().asSequence().toSet())
        val required = schema.getJSONArray("required")
        assertEquals(keys.toSet(), (0 until required.length()).map(required::getString).toSet())
        return properties
    }

    @Test fun planFormatDescribesTypedRolesAndNumericParentsWithoutTools() {
        val format = checkNotNull(wire(hardStyle).requestFormat)
        assertEquals("json_schema", format.getString("type"))
        val envelope = format.getJSONObject("json_schema")
        assertTrue(envelope.getBoolean("strict"))
        val root = fields(envelope.getJSONObject("schema"), "roles", "synthesis")
        assertEquals("string", root.getJSONObject("synthesis").getString("type"))
        val roles = root.getJSONObject("roles")
        assertEquals("array", roles.getString("type"))
        assertEquals(10, roles.getInt("maxItems"))
        val props = fields(roles.getJSONObject("items"), "kind", "parents", "task")
        val kinds = props.getJSONObject("kind").getJSONArray("enum")
        assertEquals(setOf("WORK", "REVIEW", "CRITIC"), (0 until kinds.length()).map(kinds::getString).toSet())
        val parents = props.getJSONObject("parents")
        assertEquals("array", parents.getString("type"))
        assertEquals(3, parents.getInt("maxItems"))
        assertEquals("integer", parents.getJSONObject("items").getString("type"))
        assertEquals("string", props.getJSONObject("task").getString("type"))
    }

    @Test fun decodesAnEmptyTeamAndPreservesKindsAssignmentsAndParentOrder() {
        val wire = wire(hardStyle)
        assertEquals("SYNTHESIS|Report totals", wire.decode(plan().toString()))
        val input = plan(role(task = "Check A, then B."), role("CRITIC", task = "Question A."),
            role("REVIEW", 2, 1, task = "Recheck both."))
        assertEquals("WORK|-|Check A, then B.\nCRITIC|-|Question A.\nREVIEW|2,1|Recheck both.\nSYNTHESIS|Report totals",
            wire.decode(input.toString()))
    }

    @Test fun acceptsTheDocumentedSizeAndDegreeLimitsInclusively() {
        val brief = "x".repeat(400)
        val roles = arrayOf(role(task = brief), role("WORK", 1), role("WORK", 1), role("WORK", 1),
            role("REVIEW", 2, 3, 4), role(), role(), role(), role(), role())
        val decoded = wire("openai").decode(plan(*roles, synthesis = brief).toString()).lines()
        assertEquals(11, decoded.size)
        assertEquals("WORK|-|$brief", decoded.first())
        assertEquals("REVIEW|2,3,4|Check costs", decoded[4])
        assertEquals("SYNTHESIS|$brief", decoded.last())
    }

    @Test fun rejectsMalformedAndCoercedFieldsInsteadOfFallingBackToText() {
        val adapters = listOf(wire("openai"), wire(hardStyle))
        fun rejects(input: String) {
            for (adapter in adapters) assertThrows(input, Exception::class.java) { adapter.decode(input) }
        }
        val good = plan().toString()
        for (raw in listOf("", "[]", "{}", "null", "Plan: $good", good + good, good + " trailing",
            """{"roles":[],"roles":[],"synthesis":"report"}""", """{"roles":[]}""", """{"synthesis":"Report"}""")) rejects(raw)
        for (wrong in listOf(JSONObject.NULL, 1, true, "[]", JSONObject())) rejects(plan().put("roles", wrong).toString())
        for (wrong in listOf(JSONObject.NULL, 1, true, "WORK", JSONArray())) {
            rejects(plan().put("roles", JSONArray().put(wrong)).toString())
        }
        rejects(plan().put("note", "extra").toString())
        rejects(plan(role().put("id", "assigned")).toString())
        for (key in listOf("kind", "parents", "task")) rejects(plan(role().apply { remove(key) }).toString())
        for (kind in listOf(JSONObject.NULL, 1, "worker", "ROLE", "SOLVE")) rejects(plan(role().put("kind", kind)).toString())
        for (parents in listOf(JSONObject.NULL, 1, "1", JSONObject())) rejects(plan(role().put("parents", parents)).toString())
        for (parent in listOf(JSONObject.NULL, true, "1", 1.5, 4294967297L)) {
            rejects(plan(role(), role().put("parents", JSONArray().put(parent))).toString())
        }
        for (value in listOf(JSONObject.NULL, 1, false, JSONArray(), "", "  ", "x".repeat(401),
            "A|B", "A\nWORK|-|B", "A\rB", "A\u2028B", "A\u202EB")) {
            rejects(plan(role().put("task", value)).toString())
            rejects(plan().put("synthesis", value).toString())
        }
    }

    @Test fun invalidGraphsStopAtPlanningWithoutIssuingAnyRoleOrSynthesisCalls() {
        val adapter = wire("openai")
        val cases = mapOf(
            "zero" to plan(role(), role("WORK", 0)),
            "negative" to plan(role(), role("WORK", -1)),
            "self" to plan(role("WORK", 1)),
            "forward" to plan(role("WORK", 2), role()),
            "unknown" to plan(role(), role("REVIEW", 3)),
            "duplicate" to plan(role(), role("REVIEW", 1, 1)),
            "fan-in" to plan(role(), role(), role(), role(), role("REVIEW", 1, 2, 3, 4)),
            "fan-out" to plan(role(), role("WORK", 1), role("WORK", 1), role("WORK", 1), role("WORK", 1)),
            "role count" to plan(*Array(11) { role() })
        )
        for ((label, invalid) in cases) {
            val stages = mutableListOf<String>()
            assertThrows(label, Exception::class.java) {
                runBlocking {
                    runAutoGoalTeam(objective, { _, input ->
                        stages += JSONObject(input).getString("stage")
                        adapter.decode(invalid.toString())
                    })
                }
            }
            assertEquals(label, listOf("plan"), stages)
        }
    }

    @Test fun remoteCloudStillRunsItsNamedTextPlanAndReviewsBeforeSynthesis() = runBlocking {
        val stages = mutableListOf<String>()
        val answer = runAutoGoalTeam(objective, { system, input ->
            val payload = JSONObject(input)
            assertNull(teamPlanWire(system, remote, "openai"))
            when (val stage = payload.getString("stage")) {
                "plan" -> legacy.also { stages += stage }
                "role" -> """{"finding":"Checked."}""".also { stages += payload.getString("id") }
                "synthesis" -> """{"answer":"Done."}""".also { stages += stage }
                else -> error("Unexpected stage: $stage")
            }
        })
        assertEquals(listOf("plan", "cost", "check", "synthesis"), stages)
        assertEquals("Done.", answer)
    }
}
