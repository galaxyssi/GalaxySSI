package com.galaxyssi.chat

import java.io.IOException
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AutoGoalTeamEngineTest {
    @Test fun rewriteMustReachTheSameIndependentEditorAndCanStillBeVetoed() = runBlocking {
        for (mode in listOf("approve", "request", "repeat-request", "reject", "ambiguous", "duplicate", "cut-review", "cut-rewrite", "unchanged", "cancel", "offline", "blank", "oversized")) {
            val draft = "Confirmed on Friday."
            val changed = "Friday is provisional."
            val objection = "No confirmation."
            val fake = Fake(plan("WORK|-|Check availability", "REVIEW|-|Audit booking")) { p ->
                when (p.getString("stage")) {
                    "role" -> """{"finding":"A private-to-the-writer finding.","dissent":"Still unresolved."}"""
                    "synthesis" -> JSONObject().put("answer", draft).toString()
                    "audit" -> if (mode in listOf("request", "repeat-request"))
                        JSONObject().put("verdict", "request_changes").put("objection", objection).toString()
                    else JSONObject().put("verdict", "revise").put("objection", objection).put("answer", draft).toString()
                    "rewrite" -> {
                        assertEquals(draft, p.getString("draft"))
                        assertEquals(objection, p.getString("objection"))
                        assertEquals("A private-to-the-writer finding.", p.getJSONArray("reports").getJSONObject(0).getString("finding"))
                        if (mode == "cancel") throw CancellationException()
                        if (mode == "cut-rewrite") """{"answer":"""
                        else JSONObject().put("answer", if (mode == "unchanged") "Confirmed  on Friday." else changed).toString()
                    }
                    "recheck" -> {
                        assertEquals("role2", p.getString("id"))
                        assertEquals(draft, p.getString("rejected_draft"))
                        assertEquals(changed, p.getString("draft"))
                        assertEquals(objection, p.getString("objection"))
                        assertEquals(0, p.getJSONArray("reports").length())
                        assertEquals("Still unresolved.", p.getJSONArray("additional_objections").getJSONObject(0).getString("dissent"))
                        when (mode) {
                            "approve", "request" -> """{"verdict":"accept"}"""
                            "repeat-request" -> """{"verdict":"request_changes","objection":"No support for Friday."}"""
                            "reject" -> """{"verdict":"withhold","objection":"No support for Friday."}"""
                            "duplicate" -> """{"verdict":"withhold","verdict":"accept"}"""
                            "cut-review" -> """{"verdict":"accept""""
                            "offline" -> throw IOException("fixture offline")
                            "blank" -> ""
                            "oversized" -> "x".repeat(1500)
                            else -> """{"verdict":"accept","objection":"But maybe not."}"""
                        }
                    }
                    else -> error("unexpected stage")
                }
            }
            val run = runCatching { fake.run() }
            assertEquals(mode, if (mode in listOf("unchanged", "cut-rewrite", "cancel")) 5 else 6, fake.calls.size)
            if (mode in listOf("approve", "request")) {
                assertTrue(changed in run.getOrThrow() && objection in run.getOrThrow() && draft !in run.getOrThrow())
            } else if (mode == "cancel") {
                assertTrue(run.exceptionOrNull() is CancellationException)
            } else {
                val held = run.exceptionOrNull() as TeamAnswerWithheld
                assertEquals(if (mode in listOf("reject", "repeat-request")) "No support for Friday." else objection, held.reservation)
                assertFalse("Team completed." in fake.events)
            }
        }
    }

    @Test fun handbackFundsBothTurnsOrNeither() = runBlocking {
        for (roles in 8..10) for (explicitRequest in listOf(false, true)) {
            val jobs = (1 until roles).map { "WORK|-|Check item $it" } + "REVIEW|-|Final check"
            val fake = Fake(plan(*jobs.toTypedArray())) { p ->
                when (p.getString("stage")) {
                    "role" -> report("Found.")
                    "synthesis" -> """{"answer":"Initial"}"""
                    "audit" -> if (explicitRequest) """{"verdict":"request_changes","objection":"Disputed"}"""
                        else """{"verdict":"revise","objection":"Disputed","answer":"Initial"}"""
                    "rewrite" -> """{"answer":"Changed"}"""
                    "recheck" -> """{"verdict":"accept"}"""
                    else -> error("unexpected stage")
                }
            }
            val run = runCatching { fake.run() }
            assertEquals(if (roles == 8) 12 else roles + 2, fake.calls.size)
            if (roles == 8) assertTrue(run.getOrThrow().startsWith("Changed"))
            else assertEquals("Disputed", (run.exceptionOrNull() as TeamAnswerWithheld).reservation)
        }
    }

    @Test fun requestChangesRequiresOnlyAnExplicitNonblankObjection() = runBlocking {
        for (receipt in listOf("""{"verdict":"request_changes"}""", """{"verdict":"request_changes","objection":" "}""",
            """{"verdict":"request_changes","objection":"No source","answer":"Unchecked"}""")) {
            val fake = Fake(plan("REVIEW|-|Verify")) {
                if (it.getString("stage") == "synthesis") """{"answer":"Draft"}""" else receipt
            }
            assertTrue(runCatching { fake.run() }.isFailure)
            assertEquals(listOf("plan", "synthesis", "audit"), fake.calls)
        }
    }

    @Test fun trimmingLegacyDraftIsNotAnEditorialCorrection() = runBlocking {
        val fake = Fake(plan("REVIEW|-|Final check")) { p ->
            when (p.getString("stage")) {
                "synthesis" -> "  Initial response\nEND"
                "audit" -> """{"verdict":"revise","objection":"Not supported","answer":"Initial response"}"""
                "rewrite" -> """{"answer":"Initial response"}"""
                else -> error("unexpected stage")
            }
        }
        assertEquals("Not supported", (runCatching { fake.run() }.exceptionOrNull() as TeamAnswerWithheld).reservation)
        assertEquals(listOf("plan", "synthesis", "audit", "rewrite"), fake.calls)
    }

    @Test fun finalEditorIsAnAllocatedRoleAndItsDecisionIsNotAnotherSynthesis() = runBlocking {
        val jobs = (1..9).map { "WORK|-|Evaluate item $it" } + "REVIEW|2,5|Audit edge cases"
        val fake = Fake(plan(*jobs.toTypedArray())) { request ->
            when (request.getString("stage")) {
                "role" -> report(request.getString("id"), if (request.getString("id") == "role9") "Still disputed." else "-")
                "synthesis" -> {
                    assertEquals(9, request.getJSONArray("reports").length())
                    """{"answer":"Both cases pass."}"""
                }
                "audit" -> {
                    assertEquals("Both cases pass.", request.getString("draft"))
                    val parents = request.getJSONArray("reports")
                    assertEquals(listOf("role2", "role5"), (0 until parents.length()).map { parents.getJSONObject(it).getString("id") })
                    val other = request.getJSONArray("additional_objections")
                    assertEquals(1, other.length())
                    assertEquals(setOf("id", "dissent"), other.getJSONObject(0).keys().asSequence().toSet())
                    assertEquals("role9", other.getJSONObject(0).getString("id"))
                    assertEquals("Still disputed.", other.getJSONObject(0).getString("dissent"))
                    """{"verdict":"revise","objection":"One threshold was missed.","answer":"Only the second passes."}"""
                }
                else -> error("Unexpected stage")
            }
        }
        val result = fake.run()
        assertFalse(result.contains("Both cases pass."))
        for (part in listOf("Only the second passes.", "One threshold was missed.", "Still disputed.")) assertTrue(part in result)
        assertEquals(12, fake.calls.size)
        assertEquals(listOf("synthesis", "audit"), fake.calls.takeLast(2))
    }

    @Test fun independentObjectionCanVetoAnApparentlyCompleteSynthesisWithoutExposingItsReport() = runBlocking {
        for (dispute in listOf(false, true)) {
            val objection = "The readings come from a simulation, not a measured sample."
            val unpublished = "The candidate was experimentally verified."
            val reviewerReason = "No candidate-specific measurements were supplied."
            val fake = Fake(plan("WORK|-|Summarize readings", "CRITIC|-|Check provenance",
                "REVIEW|1|Review the conclusion")) { p ->
                when (p.getString("stage")) {
                    "role" -> {
                        assertFalse(p.has("additional_objections"))
                        assertEquals(0, p.getJSONArray("reports").length())
                        if (p.getString("id") == "role2") report("Non-parent finding must stay out of the audit.", if (dispute) objection else "-")
                        else report("Reported readings.")
                    }
                    "synthesis" -> JSONObject().put("answer", unpublished).toString()
                    "audit" -> {
                        assertFalse(p.toString().contains("Non-parent finding"))
                        if (p.has("additional_objections")) {
                            assertEquals(objection, p.getJSONArray("additional_objections").getJSONObject(0).getString("dissent"))
                            JSONObject().put("verdict", "withhold").put("objection", reviewerReason).toString()
                        } else """{"verdict":"accept"}"""
                    }
                    else -> error("Unexpected stage")
                }
            }
            val result = runCatching { fake.run() }
            if (dispute) {
                val failure = result.exceptionOrNull() as TeamAnswerWithheld
                assertEquals(reviewerReason, failure.reservation)
                assertEquals("\n\nReported disagreements:\n- [role2] $objection", failure.publicObjections)
                assertFalse(unpublished in failure.publicObjections)
                assertFalse("Team completed." in fake.events)
            } else assertEquals(unpublished, result.getOrThrow())
            assertEquals(5, fake.calls.size)
        }
    }

    @Test fun withheldMalformedOrCancelledAuditsCannotPublishTheDraft() = runBlocking {
        for (audit in listOf("""{"verdict":"withhold","objection":"No source."}""",
            """{"verdict":"accept","answer":"unexpected"}""", """{"verdict":"revise","objection":"wrong","answer":"Unreviewed"}""",
            """{"verdict":"revise","objection":"wrong"}""", "partial", "cancel")) {
            val fake = Fake(plan("WORK|-|Find the source", "REVIEW|1|Audit it")) { request ->
                when (request.getString("stage")) {
                    "role" -> report("first")
                    "audit" -> if (audit == "cancel") throw CancellationException() else audit
                    else -> """{"answer":"Unreviewed"}"""
                }
            }
            val failure = runCatching { fake.run() }.exceptionOrNull()
            assertNotNull(failure)
            if ("withhold" in audit) assertEquals("No source.", (failure as TeamAnswerWithheld).reservation)
            if (audit == "cancel") assertTrue(failure is CancellationException)
            assertFalse("Team completed." in fake.events)
        }
    }

    @Test fun reviewerWithDownstreamConsumersStaysInDependencyOrder() = runBlocking {
        val fake = Fake(plan("WORK|-|Count", "REVIEW|1|Check count", "WORK|2|Estimate cost")) {
            if (it.getString("stage") == "synthesis") "Done.\nEND" else report(it.getString("id"))
        }
        assertEquals("Done.", fake.run())
        assertEquals(listOf("plan", "role1", "role2", "role3", "synthesis"), fake.calls)
    }

    @Test fun completeJsonFindingsAllowUnreportedReservationsButNotPartialOrMixedObjects() = runBlocking {
        for (text in listOf("""{"finding":"Reported."}""", """{"finding":"Reported.","dissent":null}""",
            """{"finding":"Reported.","dissent":"Unresolved."}""")) {
            val fake = Fake(plan(role("author"))) { if (it.getString("stage") == "role") text else "Summary.\nEND" }
            assertEquals("Unresolved." in text, "Unresolved." in fake.run())
        }
        for (bad in listOf("""{"finding":"partial"""", """{"dissent":"missing result"}""", """{"finding":7}""",
            """{"finding":"ok","dissent":false}""", """{"finding":"ok","tools":[]}""", """{"finding":"ok"}{}""")) {
            val fake = Fake(plan(role("author"))) { bad }
            assertTrue(runCatching { fake.run() }.isFailure)
            assertEquals(listOf("plan", "author"), fake.calls)
        }
    }

    @Test fun jsonSynthesisMustBeOneCompletePublicAnswer() = runBlocking {
        assertEquals("Combined.", Fake(plan()) { """{"answer":"Combined."}""" }.run())
        for (bad in listOf("{\"answer\":\"cut", """{"answer":false}""", """{"answer":" "}""",
            """{"answer":"ok","tool_calls":[]}""", """{"answer":"ok"} trailing""")) {
            assertTrue(runCatching { Fake(plan()) { bad }.run() }.isFailure)
        }
    }

    @Test fun positionalRolesUseHostIdsAndKeepDistinctDependencies() = runBlocking {
        val fake = Fake(plan("WORK|-|Summarize counts.", "CRITIC|-|Consider omissions.", "REVIEW|1, 2|Audit both.")) {
            if (it.getString("stage") == "synthesis") "Done.\nEND" else {
                if (it.getString("id") == "role3") {
                    val inputs = it.getJSONArray("reports")
                    assertEquals(listOf("role1", "role2"), (0 until inputs.length()).map { i -> inputs.getJSONObject(i).getString("id") })
                }
                if (it.getString("stage") == "audit") {
                    assertEquals("Done.", it.getString("draft"))
                    """{"verdict":"accept"}"""
                } else report(it.getString("id"))
            }
        }
        assertEquals("Done.", fake.run())
        for (bad in listOf("REVIEW|2|self", "CRITIC|0|zero", "WORK|1,1|duplicate", "ROLE|x|worker|-|mixed")) {
            val rejected = Fake(plan("WORK|-|first", bad))
            assertTrue(runCatching { rejected.run() }.isFailure)
            assertEquals(listOf("plan"), rejected.calls)
        }
    }

    private fun role(id: String, parents: String = "-", kind: String = "worker") =
        "ROLE|$id|$kind|$parents|private-assignment-$id"

    private fun plan(vararg roles: String) = (roles.toList() + "SYNTHESIS|private-brief").joinToString("\n")
    private fun report(id: String, dissent: String = "-") = "FINDING|public-$id\nDISSENT|$dissent\nEND"

    private class Fake(val plan: String, val respond: suspend (JSONObject) -> String = { error("Unexpected call") }) {
        val calls = Collections.synchronizedList(mutableListOf<String>())
        val events = mutableListOf<String>()

        suspend fun run(objective: String = "private-objective"): String = runAutoGoalTeam(objective, { system, input ->
            val message = JSONObject(input)
            assertEquals(objective, message.getString("objective"))
            assertFalse(system.contains(objective))
            val stage = message.getString("stage")
            calls.add(if (stage == "role") message.getString("id") else stage)
            if (stage == "plan") plan else respond(message)
        }, { events.add(it) })
    }

    @Test fun zeroRolesStillMakesASeparateDirectAnswerCall() = runBlocking {
        val fake = Fake(plan()) {
            assertEquals("private-brief", it.getString("brief"))
            assertEquals(0, it.getJSONArray("reports").length())
            "First line.\r\nSecond line.\r\nEND\r\n"
        }
        assertEquals("First line.\r\nSecond line.", fake.run())
        assertEquals(listOf("plan", "synthesis"), fake.calls)
        assertEquals(listOf("Planning team.", "Plan accepted: 0 roles.", "Synthesizing answer.", "Team completed."), fake.events)
    }

    @Test fun tenIndependentJobsOverlapAtMostThreeAtATimeAndUseExactlyTwelveCalls() = runBlocking {
        withTimeout(5000) {
            val ids = (1..10).map { "job$it" }
            val active = AtomicInteger()
            val peak = AtomicInteger()
            val full = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            val fake = Fake(plan(*ids.map { role(it) }.toTypedArray())) { request ->
                if (request.getString("stage") == "synthesis") {
                    assertEquals(0, active.get())
                    val reports = request.getJSONArray("reports")
                    assertEquals(ids, (0 until reports.length()).map { reports.getJSONObject(it).getString("id") })
                    "Combined.\nEND"
                } else {
                    assertEquals(0, request.getJSONArray("reports").length())
                    val count = active.incrementAndGet()
                    peak.updateAndGet { maxOf(it, count) }
                    if (count == 3) full.complete(Unit)
                    try {
                        release.await()
                        report(request.getString("id"))
                    } finally {
                        active.decrementAndGet()
                    }
                }
            }
            val result = async { fake.run() }
            full.await()
            release.complete(Unit)
            assertEquals("Combined.", result.await())
            assertEquals(3, peak.get())
            assertEquals(12, fake.calls.size)
            assertEquals(ids.toSet(), fake.calls.drop(1).dropLast(1).toSet())
        }
    }

    @Test fun forwardDependenciesReceiveOnlyDirectReportsAndDissentSurvivesSynthesis() = runBlocking {
        withTimeout(5000) {
            val reservation = "The sample omits weekends."
            val objection = "The dates are unconfirmed."
            val reviewDone = CompletableDeferred<Unit>()
            val fake = Fake(plan(role("review", "draft,critic", "reviewer"), role("critic", "source", "dissent"),
                role("slow"), role("draft"), role("source"))) { request ->
                val inputs = request.getJSONArray("reports")
                val reports = (0 until inputs.length()).map { inputs.getJSONObject(it) }
                when (request.optString("id", "")) {
                    "slow" -> {
                        // An unrelated root must not hold up a dependency-ready reviewer.
                        reviewDone.await()
                        report("slow")
                    }
                    "source", "draft" -> {
                        assertTrue(reports.isEmpty())
                        report(request.getString("id"))
                    }
                    "critic" -> {
                        assertEquals("dissent", request.getString("kind"))
                        assertEquals("public-source", reports.single().getString("finding"))
                        report("critic", reservation)
                    }
                    "review" -> {
                        assertEquals("reviewer", request.getString("kind"))
                        assertEquals(listOf("public-draft", "public-critic"), reports.map { it.getString("finding") })
                        assertEquals(reservation, reports.last().getString("dissent"))
                        reviewDone.complete(Unit)
                        report("review", objection)
                    }
                    else -> {
                        assertEquals("synthesis", request.getString("stage"))
                        assertEquals(5, reports.size)
                        "A summary that omits the reservations.\nEND"
                    }
                }
            }
            val answer = fake.run()
            assertTrue(answer.endsWith("Reported disagreements:\n- [review] $objection\n- [critic] $reservation"))
            assertEquals("synthesis", fake.calls.last())
            val progress = Regex("Role [1-5]/5 \\((worker|reviewer|dissent)\\) (started|completed)\\.")
            val roleEvents = fake.events.filter { progress.matches(it) }
            assertEquals(10, roleEvents.distinct().size)
            assertEquals(listOf("Planning team.", "Plan accepted: 5 roles.", "Synthesizing answer.", "Team completed."),
                fake.events - roleEvents.toSet())
        }
    }

    @Test fun invalidPlansCannotDispatchEvenAnOtherwiseReadyRoot() = runBlocking {
        val invalid = listOf(
            plan(role("bad id")), plan(role("a"), role("a")), plan(role("a", "missing")),
            plan(role("a", "a")), plan(role("ok"), role("a", "b"), role("b", "a")),
            plan(role("a"), role("b", "a,a")), plan(role("a", kind = "executor")),
            plan(*(1..11).map { role("r$it") }.toTypedArray()),
            plan(role("a"), role("b", "a"), role("c", "a"), role("d", "a"), role("e", "a")),
            plan(role("a"), role("b"), role("c"), role("d"), role("e", "a,b,c,d")),
            plan("ROLE|a|worker|-|"), plan("ROLE|a|worker|-|unexpected|field"),
            role("a"), plan(role("a")) + "\nextra", "SYNTHESIS|" + "a".repeat(401), "x".repeat(6001)
        )
        for (bad in invalid) {
            val fake = Fake(bad)
            assertTrue(runCatching { fake.run() }.exceptionOrNull() is IllegalStateException)
            assertEquals(listOf("plan"), fake.calls)
            assertEquals("Team stopped without an answer.", fake.events.last())
        }
    }

    @Test fun interruptedOrFailedBranchCancelsSiblingAndCannotSynthesize() = runBlocking {
        withTimeout(5000) {
            for (fault in listOf("transport", "cancel", "truncated", "blank", "oversized")) {
                val started = CompletableDeferred<Unit>()
                val stopped = CompletableDeferred<Unit>()
                val fake = Fake(plan(role("waiter"), role("broken"), role("later", "broken"))) { request ->
                    when (request.getString("id")) {
                        "waiter" -> try {
                            started.complete(Unit)
                            awaitCancellation()
                        } finally {
                            stopped.complete(Unit)
                        }
                        "broken" -> {
                            started.await()
                            when (fault) {
                                "transport" -> throw IOException("private transport detail")
                                "cancel" -> throw CancellationException("private interruption detail")
                                "blank" -> " "
                                "oversized" -> report("x".repeat(2100))
                                else -> "FINDING|partial\nDISSENT|-"
                            }
                        }
                        else -> error("Unexpected dependent or synthesis")
                    }
                }
                val failure = runCatching { fake.run() }.exceptionOrNull()
                if (fault == "cancel") {
                    assertTrue(failure is CancellationException)
                    assertEquals("Team interrupted.", fake.events.last())
                } else {
                    assertTrue("$fault: $failure", failure is IllegalStateException && failure !is CancellationException)
                    assertEquals("Team stopped without an answer.", fake.events.last())
                }
                assertTrue(stopped.isCompleted)
                assertEquals(setOf("plan", "waiter", "broken"), fake.calls.toSet())
                assertFalse(fake.events.any { "private" in it || "Team completed." == it })
            }
        }
    }

    @Test fun callerCancellationPropagatesWithoutNewCalls() = runBlocking {
        withTimeout(5000) {
            val started = CompletableDeferred<Unit>()
            val fake = Fake(plan(role("first"), role("later", "first"))) {
                started.complete(Unit)
                awaitCancellation()
            }
            val result = async { fake.run() }
            started.await()
            result.cancelAndJoin()
            assertTrue(result.isCancelled)
            assertEquals(listOf("plan", "first"), fake.calls)
            assertEquals("Team interrupted.", fake.events.last())
        }
    }

    @Test fun invalidObjectivesAndIncompleteFinalResponsesCannotReturnAnAnswer() = runBlocking {
        for (objective in listOf("  ", "x".repeat(8001))) {
            val fake = Fake(plan())
            assertTrue(runCatching { fake.run(objective) }.exceptionOrNull() is IllegalArgumentException)
            assertTrue(fake.calls.isEmpty())
        }
        for (reply in listOf("partial answer", "END", "x".repeat(8001) + "\nEND")) {
            val fake = Fake(plan()) { reply }
            assertTrue(runCatching { fake.run() }.exceptionOrNull() is IllegalStateException)
            assertEquals(listOf("plan", "synthesis"), fake.calls)
            assertFalse("Team completed." in fake.events)
        }
    }

    @Test fun plannerAndSynthesisTransportFailuresStopWithoutRetry() = runBlocking {
        for (broken in listOf("plan", "synthesis")) {
            val calls = mutableListOf<String>()
            val events = mutableListOf<String>()
            val failure = runCatching {
                runAutoGoalTeam("Summarize a paragraph.", { _, input ->
                    val stage = JSONObject(input).getString("stage")
                    calls.add(stage)
                    if (stage == broken) throw IOException("private transport detail")
                    plan()
                }, { events.add(it) })
            }.exceptionOrNull()
            assertTrue(failure is IllegalStateException && failure.cause is IOException)
            assertEquals(if (broken == "plan") listOf("plan") else listOf("plan", "synthesis"), calls)
            assertEquals("Team stopped without an answer.", events.last())
            assertFalse(events.any { "private" in it })
        }
    }
}
