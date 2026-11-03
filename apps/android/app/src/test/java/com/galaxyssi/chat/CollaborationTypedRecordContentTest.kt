package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationTypedRecordContentTest {
    private val tool = CollaborationExecutableTool.TOOL
    private val test = CollaborationExecutableTool.TEST
    private val release = CollaborationExecutableTool.RELEASE

    private fun publish(f: CollaborationExecutableToolTest.Fixture, id: String, kind: String, body: JSONObject,
                        person: String = "reviewer", observations: JSONArray = JSONArray()): JSONObject {
        val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Typed fixture")
            .put("workspace", JSONArray().put(JSONObject().put("id", id).put("kind", kind).put("title", id)
                .put("body", body).put("observations", observations)))
        return f.workspace.publish(f.access(person, 5, id), raw.toString(), 100)
    }

    @Test fun completeTypedSourcePersistsUnchangedWithoutRedundantProse() {
        val f = CollaborationExecutableToolTest.Fixture()
        val body = JSONObject().put(tool, JSONObject(f.spec.toString()))
        val before = body.toString()
        val saved = f.ref(publish(f, "source-only", tool, body, "author"))
        val original = f.reopen().read(f.access(round = 6), saved.getString("object_id"), 1)!!
        assertEquals(before, original.getJSONObject("body").toString())
        assertEquals(before, body.toString())
        assertFalse(original.getJSONObject("body").has("content"))
        assertFalse(saved.getJSONObject(CollaborationEvolutionContract.HOST).getBoolean("automatically_installed"))
        assertEquals(saved.getString("sha256"), f.ref(publish(f, "source-only", tool, body, "author")).getString("sha256"))
        assertNull(f.reopen().read(f.access().copy(groupId = "other"), saved.getString("object_id"), 1))
    }

    @Test fun typedTestPlanWithoutProseUsesTheSameNativePreparation() {
        val f = CollaborationExecutableToolTest.Fixture()
        val saved = f.ref(publish(f, "tests-only", test, JSONObject().put(test, f.planSpec)))
        val prepared = f.prepare(JSONObject().put("mode", "test").put(test, saved), access = f.access("executor", 6))
        assertEquals(f.tool.getString("sha256"), prepared.identity.getJSONObject(tool).getString("sha256"))
        assertTrue(f.finish(prepared).isSuccess)
    }

    private fun releaseWithoutProse(read: Boolean, person: String = "reviewer"): JSONObject {
        val f = CollaborationExecutableToolTest.Fixture()
        val observation = f.observed()
        if (read) {
            val access = f.access(person, 5, "typed-review")
            var offset: Int? = 0
            while (offset != null) offset = f.ledger.readPage(access, observation.getString("evidence_id"),
                observation.getString("sha256"), offset)!!.next
        }
        return publish(f, "typed-review", release, JSONObject().put(release, f.releaseSpec(observation)),
            person, JSONArray().put(observation))
    }

    @Test fun independentlyReviewedReleaseNoLongerNeedsADuplicateContentSentence() {
        val receipt = releaseWithoutProse(true)
        assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
        val host = receipt.getJSONArray("revisions").getJSONObject(0).getJSONObject(CollaborationEvolutionContract.HOST)
        assertEquals("eligible_for_scoped_tool_execution", host.getString("state"))
        assertFalse(host.getBoolean("automatically_installed"))
    }

    @Test fun omittingProseCannotBypassOriginalReadOrIndependentReview() {
        assertEquals("rejected", releaseWithoutProse(false).getString("status"))
        assertEquals("rejected", releaseWithoutProse(true, "author").getString("status"))
    }

    @Test fun omittedContentDoesNotRelaxTypedFieldsOrRegressionCoverage() {
        val f = CollaborationExecutableToolTest.Fixture()
        assertEquals("rejected", publish(f, "empty-source", tool, JSONObject().put(tool, JSONObject())).getString("status"))
        val incomplete = JSONObject(f.planSpec.toString()).put("cases", JSONArray().put(f.case("one", "target", "[1]", "[1]")))
        val receipt = publish(f, "no-regression", test, JSONObject().put(test, incomplete))
        assertEquals("rejected", receipt.getString("status"))
        assertTrue(receipt.getString("reason").contains("regression"))
    }

    @Test fun suppliedContentMustBeTextAndReportsTheExactField() {
        val f = CollaborationExecutableToolTest.Fixture()
        for ((index, content) in listOf(JSONObject.NULL, "", "   ", 42, JSONObject(), JSONArray()).withIndex()) {
            val receipt = publish(f, "bad-content-$index", tool, JSONObject().put(tool, f.spec).put("content", content))
            assertEquals("rejected", receipt.getString("status"))
            val detail = receipt.getJSONObject(CollaborationRecordValidation.DETAIL)
            assertEquals("record_content_invalid", detail.getString("code"))
            assertEquals("/body/content", detail.getString("path"))
        }
        assertEquals("recorded", publish(f, "with-content", tool, JSONObject().put(tool, f.spec)
            .put("content", "Actual author note")).getString("status"))
    }

    @Test fun absentTypedBodyIsNotMisdiagnosedAsMissingProse() {
        val f = CollaborationExecutableToolTest.Fixture()
        val receipt = publish(f, "no-body", tool, JSONObject().put("note", "Typed data is missing"))
        assertEquals("typed_body_required", receipt.getJSONObject(CollaborationRecordValidation.DETAIL).getString("code"))
        assertEquals("/body/$tool", receipt.getJSONObject(CollaborationRecordValidation.DETAIL).getString("path"))
    }

    @Test fun documentaryCandidatesStillRequireTheirActualContent() {
        val f = CollaborationExecutableToolTest.Fixture()
        val body = JSONObject().put("candidate", JSONObject().put("operation", "propose").put("rationale", "Fixture")
            .put("criteria", JSONArray().put("Substantive proposal")))
        assertEquals("rejected", publish(f, "empty-candidate", "candidate", body).getString("status"))
    }

    @Test fun finalDeliveryStillRequiresCompleteTextAndCannotUseATypedRecord() {
        val f = CollaborationExecutableToolTest.Fixture()
        val ref = f.tool
        val assessment = JSONObject().put("decision", "achieved").put("final_delivery", ref)
            .put("criteria", JSONArray().put(JSONObject().put("status", "met").put("delivery", ref)))
        for (kind in listOf(tool, "artifact", "proposal", "decision")) {
            val saved = JSONObject().put("kind", kind).put("body", JSONObject().put(tool, f.spec))
            assertThrows(IllegalArgumentException::class.java) { CollaborationFinalDelivery.content(assessment) { saved } }
        }
    }

    @Test fun toolAndEvolutionGuidanceAdvertiseOptionalContent() {
        assertTrue(CollaborationToolProtocol.rules().contains("body.content is optional"))
        val foundation = CollaborationEvolutionProtocol.rules("foundation").getString("contract")
        assertTrue(foundation.contains("body.content is optional"))
        assertTrue(foundation.contains("final user-facing delivery"))
    }
}
