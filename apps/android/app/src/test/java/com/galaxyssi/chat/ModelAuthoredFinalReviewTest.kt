package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ModelAuthoredFinalReviewTest {
    private val objective = "Compare schedules, then independently audit the final answer."
    private val auditTask = "Check the proposed handover against the disputed Friday slot."
    private val draft = "The handover is scheduled for Friday afternoon."
    private val objection = "The Friday slot is provisional."

    private fun plan(roles: List<Any>, review: String = auditTask) = JSONObject()
        .put("roles", JSONArray(roles)).put("synthesis", "State the handover time.").put("final_review", review)

    private class Trace {
        val calls = mutableListOf<JSONObject>()
        val events = mutableListOf<String>()
        fun stage(name: String) = calls.filter { it.getString("stage") == name }
        fun stages() = calls.map { it.getString("stage") }
    }

    // No transport: pass the provider's reply through the same optional plan adapter used by the runner.
    private fun run(planReply: String, trace: Trace, style: String? = null,
        auditReply: String = """{"verdict":"accept"}""", task: String = objective): String = runBlocking {
        runAutoGoalTeam(task, { system, raw ->
            val input = JSONObject(raw)
            trace.calls += input
            when (input.getString("stage")) {
                "plan" -> if (style == null) planReply else {
                    val wire = checkNotNull(teamPlanWire(system, "http://127.0.0.1:8080/v1/chat/completions", style))
                    if (style == "openai") assertNull(wire.requestFormat)
                    else {
                        val schema = checkNotNull(wire.requestFormat).getJSONObject("json_schema").getJSONObject("schema")
                        val required = schema.getJSONArray("required")
                        assertEquals(setOf("roles", "synthesis", "final_review"), (0 until required.length()).map(required::getString).toSet())
                        assertEquals(9, schema.getJSONObject("properties").getJSONObject("roles").getInt("maxItems"))
                    }
                    wire.decode(planReply)
                }
                "role" -> if (input.getString("kind") == "dissent")
                    JSONObject().put("finding", "Contributor-only staffing note.").put("dissent", objection).toString()
                    else """{"finding":"Contributor-only calendar note."}"""
                "synthesis" -> JSONObject().put("answer", draft).toString()
                "audit" -> auditReply
                else -> error("Unexpected stage")
            }
        }, { trace.events += it })
    }

    @Test fun authoredReviewerSeesActualDraftAndOnlyPublicDissentAcrossPlanTransports() {
        val critic = JSONObject().put("kind", "CRITIC").put("parents", JSONArray().put(1))
            .put("task", "Challenge the proposed timing.")
        val mixedPlan = plan(listOf("Compare the listed times.", critic))
        for (style in listOf(null, "openai", "llama.cpp-json-schema")) {
            val trace = Trace()
            val answer = run(mixedPlan.toString(), trace, style)
            assertEquals(listOf("plan", "role", "role", "synthesis", "audit"), trace.stages())
            assertTrue(trace.stage("plan").single().getBoolean("final_review_required"))
            val (worker, skeptic) = trace.stage("role")
            assertEquals("Compare the listed times.", worker.getString("assignment"))
            assertEquals(0, worker.getJSONArray("reports").length())
            val parents = skeptic.getJSONArray("reports")
            assertEquals(1, parents.length())
            assertEquals(worker.getString("id"), parents.getJSONObject(0).getString("id"))
            val audit = trace.stage("audit").single()
            assertEquals(auditTask, audit.getString("assignment"))
            assertEquals(draft, audit.getString("draft"))
            assertEquals(objective, audit.getString("objective"))
            assertEquals("reviewer", audit.getString("kind"))
            assertFalse(audit.getString("id") in trace.stage("role").map { it.getString("id") })
            assertEquals(0, audit.getJSONArray("reports").length())
            val forwarded = audit.getJSONArray("additional_objections")
            assertEquals(1, forwarded.length())
            val item = forwarded.getJSONObject(0)
            assertEquals(setOf("id", "dissent"), item.keys().asSequence().toSet())
            assertEquals(skeptic.getString("id"), item.getString("id"))
            assertEquals(objection, item.getString("dissent"))
            assertFalse(audit.toString().contains("Contributor-only"))
            assertTrue(answer.contains(draft) && answer.contains(objection))
        }
    }

    @Test fun finalReviewerConsumesOneOfTenRoleSlots() {
        val trace = Trace()
        val briefs = (1..9).map { "Check slot $it." }
        run(plan(briefs).toString(), trace)
        assertEquals(briefs.sorted(), trace.stage("role").map { it.getString("assignment") }.sorted())
        val ids = (trace.stage("role") + trace.stage("audit").single()).map { it.getString("id") }
        assertEquals(10, ids.toSet().size)
        assertEquals(listOf("synthesis", "audit"), trace.stages().takeLast(2))
        assertTrue("Plan accepted: 10 roles." in trace.events)

        val overflow = Trace()
        assertThrows(Exception::class.java) { run(plan(briefs + "One extra slot.").toString(), overflow) }
        assertEquals(listOf("plan"), overflow.stages())
    }

    @Test fun invalidOrAbsentReviewStopsBeforeWorkersAndCannotPromoteAnIntermediateReviewer() {
        val missing = plan(listOf("Check the slot.")).apply { remove("final_review") }
        for (style in listOf(null, "openai", "llama.cpp-json-schema")) {
            for (invalid in listOf(missing, plan(listOf("Check the slot."), "  "),
                plan(listOf("Check the slot.")).put("final_review", JSONObject.NULL))) {
                val trace = Trace()
                assertThrows(TeamFinalAuditMissing::class.java) { run(invalid.toString(), trace, style) }
                assertEquals(listOf("plan"), trace.stages())
            }
        }
        val upstream = "REVIEW|-|Check the inputs\nWORK|1|Use the checked inputs\nSYNTHESIS|Report the time"
        for (style in listOf(null, "openai")) {
            val trace = Trace()
            assertThrows(TeamFinalAuditMissing::class.java) { run(upstream, trace, style) }
            assertEquals(listOf("plan"), trace.stages())
        }
    }

    @Test fun previousTerminalReviewerKeepsItsDeclaredParentAndOrdinaryPlansRemainOptional() {
        val terminal = "WORK|-|Check the slot\nREVIEW|1|Verify the handover independently\nSYNTHESIS|Report it"
        val oldJson = """{"roles":[{"kind":"WORK","parents":[],"task":"Check the slot"},{"kind":"REVIEW","parents":[1],"task":"Verify the handover independently"}],"synthesis":"Report it"}"""
        for (previous in listOf(terminal, oldJson)) {
            val trace = Trace()
            run(previous, trace)
            val audit = trace.stage("audit").single()
            assertEquals("Verify the handover independently", audit.getString("assignment"))
            val parents = audit.getJSONArray("reports")
            assertEquals(1, parents.length())
            assertEquals(trace.stage("role").single().getString("id"), parents.getJSONObject(0).getString("id"))
            assertEquals(draft, audit.getString("draft"))
        }

        val ordinary = Trace()
        assertEquals(draft, run("SYNTHESIS|Report the time", ordinary, task = "Compare schedules."))
        assertEquals(listOf("plan", "synthesis"), ordinary.stages())
        assertFalse(ordinary.stage("plan").single().optBoolean("final_review_required"))
    }

    @Test fun authoredReviewerCanWithholdTheOnlyDraft() {
        val trace = Trace()
        val withheld = assertThrows(TeamAnswerWithheld::class.java) {
            run(plan(listOf("Check the slot.")).toString(), trace,
                auditReply = """{"verdict":"withhold","objection":"No confirmed handover time."}""")
        }
        assertEquals(listOf("plan", "role", "synthesis", "audit"), trace.stages())
        assertEquals(draft, trace.stage("audit").single().getString("draft"))
        assertEquals("No confirmed handover time.", withheld.reservation)
        assertFalse("Team completed." in trace.events)
    }
}
