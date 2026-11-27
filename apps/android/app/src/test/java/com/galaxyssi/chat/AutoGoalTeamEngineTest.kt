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
