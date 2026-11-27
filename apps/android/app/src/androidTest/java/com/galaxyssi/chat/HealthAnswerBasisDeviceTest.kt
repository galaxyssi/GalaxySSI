package com.galaxyssi.chat

import android.os.SystemClock
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthAnswerBasisDeviceTest {
    @Test fun approvedTurnAloneCanExpandAndRevocationErasesTheMountedRows() {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val transcripts = AgentTranscriptStore(ctx)
        val previous = transcripts.activeConversation().id
        var conversation = ""
        val turn = UUID.randomUUID().toString()
        try {
            HealthRecordStore(ctx, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
                mapOf("glucose" to "6.3"), "mmol/L", System.currentTimeMillis() - 1000, reference = "4-6")) }
            HealthCareStore(ctx, names.care).use { care ->
                care.configure(true, "")
                HealthCareEngine.evaluate(ctx, names)
                val id = care.forMetric(HealthMetric.GLUCOSE)!!.id
                conversation = HealthCareDiscussion.open(ctx, id, names)
                val issue = care.concern(id)!!
                val grant = HealthCareDiscussionGrant(conversation, turn, id, issue.revision, care.settings().version,
                    HealthPrivacyStore(ctx, names.privacy).use { it.policy().version },
                    HealthCareDiscussion.destination(ctx, "local-llm", "fixture"), System.currentTimeMillis(),
                    "local-llm", "fixture", "auto", questionsShared = true)
                val sources = HealthAnswerBasis.snapshot(HealthCareDiscussionPolicy.snapshot(issue))
                care.approveDiscussion(grant, sources)
                assertEquals(sources, care.answerBasis(grant))
                assertTrue(care.answerBasis(grant.copy(turnId = UUID.randomUUID().toString())).isEmpty())
                assertFalse(care.answerBasis(grant).isEmpty())
            }
            transcripts.switchConversation(conversation)
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                lateinit var row: HealthAnswerBasisRow
                lateinit var wrongTurn: HealthAnswerBasisRow
                scenario.onActivity { activity ->
                    activity.healthCareSurface?.destroy()
                    val surface = HealthCareAgentSurface(activity, names)
                    activity.healthCareSurface = surface
                    surface.showForAgent(true); surface.resume()
                    assertNull(surface.answerRow(previous, turn))
                    row = surface.answerRow(conversation, turn) as HealthAnswerBasisRow
                    wrongTurn = surface.answerRow(conversation, UUID.randomUUID().toString()) as HealthAnswerBasisRow
                    activity.findViewById<FrameLayout>(android.R.id.content).addView(LinearLayout(activity).apply {
                        orientation = LinearLayout.VERTICAL; addView(row); addView(wrongTurn)
                    })
                }
                fun await(check: () -> Boolean) {
                    val end = SystemClock.elapsedRealtime() + 20_000
                    do {
                        var ok = false; scenario.onActivity { ok = check() }
                        if (ok) return
                        SystemClock.sleep(60)
                    } while (SystemClock.elapsedRealtime() < end)
                    fail("Health source row did not reach expected state")
                }
                await { row.visibility == View.VISIBLE && row.childCount == 1 }
                scenario.onActivity { assertTrue(row.getChildAt(0).performClick()); assertEquals(View.GONE, wrongTurn.visibility) }
                await { row.childCount > 2 }
                HealthPrivacyStore(ctx, names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
                await { row.visibility == View.GONE && row.childCount == 0 && wrongTurn.childCount == 0 }
            }
        } finally {
            transcripts.switchConversation(previous)
            if (conversation.isNotEmpty()) transcripts.deleteConversation(conversation)
            listOf(names.care, names.records, names.privacy, names.reminders, names.profile).forEach(ctx::deleteDatabase)
        }
    }
}
