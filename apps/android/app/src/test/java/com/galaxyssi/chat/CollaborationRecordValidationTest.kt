package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationRecordValidationTest {
    private val tool = CollaborationExecutableTool.TOOL
    private val plan = CollaborationExecutableTool.TEST
    private fun failure(block: () -> Unit): JSONObject {
        try { block(); fail("Expected exact record rejection") }
        catch (error: CollaborationToolFeedback.Invalid) { return error.problem }
        error("Unreachable")
    }
    private fun validate(f: CollaborationExecutableToolTest.Fixture, reference: JSONObject = f.tool,
                         kinds: Set<String> = setOf(tool), current: Boolean = true) =
        CollaborationRecordValidation.exact(reference, kinds,
            { id, version -> f.workspace.read(f.access(), id, version) }, { _, _ -> current })

    @Test fun exactCurrentTypedRecordIsReturnedUnchanged() {
        val f = CollaborationExecutableToolTest.Fixture()
        assertEquals(f.tool.getString("sha256"), validate(f).getString("sha256"))
        assertNull(CollaborationRecordValidation.notice(validate(f)))
    }

    @Test fun kindDigestAndStaleVersionHaveDifferentCodesAndFacts() {
        val f = CollaborationExecutableToolTest.Fixture()
        val kind = failure { validate(f, kinds = setOf(plan)) }
        assertEquals("record_kind_mismatch", kind.getString("code"))
        assertEquals("/reference/kind", kind.getString("path"))
        assertEquals(plan, kind.getJSONArray("expected").getString(0))
        assertEquals(tool, kind.getString("actual"))
        assertEquals(f.tool.getString("object_id"), kind.getJSONObject("reference").getString("object_id"))
        val hash = failure { validate(f, JSONObject(f.tool.toString()).put("sha256", "0".repeat(64))) }
        assertEquals("record_digest_mismatch", hash.getString("code"))
        assertEquals(f.tool.getString("sha256"), hash.getString("expected"))
        assertEquals("record_not_current", failure { validate(f, current = false) }.getString("code"))
    }

    @Test fun invalidRevisionIsRejectedBeforeReadingOrCheckingCurrent() {
        for (value in listOf(0, 1.0, "1", true)) {
            val ref = JSONObject().put("revision", value)
            val error = failure { CollaborationRecordValidation.exact(ref, setOf(tool),
                { _, _ -> error("Must not read") }, { _, _ -> error("Must not inspect current") }) }
            assertEquals("record_revision_invalid", error.getString("code"))
        }
    }

    @Test fun missingOrIsolatedRecordDoesNotExposeKindOrHash() {
        val f = CollaborationExecutableToolTest.Fixture()
        val error = failure { CollaborationRecordValidation.exact(f.tool, setOf(tool), { id, version ->
            f.workspace.read(f.access().copy(groupId = "other-group"), id, version)
        }, { _, _ -> error("Must not inspect isolated current") }) }
        assertEquals("record_unavailable", error.getString("code"))
        assertEquals("missing or isolated", error.getString("actual"))
        assertFalse(error.has("record"))
    }

    private fun publication(f: CollaborationExecutableToolTest.Fixture, id: String, kind: String, body: JSONObject, round: Long = 3): JSONObject {
        val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Typed record fixture")
            .put("workspace", JSONArray().put(JSONObject().put("id", id).put("kind", kind).put("title", id).put("body", body)))
        return f.workspace.publish(f.access(round = round, node = id), raw.toString())
    }

    @Test fun wrongPublicationEnvelopeReportsExactMissingBodyWithoutCallingItInvalidJson() {
        val f = CollaborationExecutableToolTest.Fixture()
        val receipt = publication(f, "wrong-plan", "experiment_plan", JSONObject().put("content", "Fixture").put(plan, f.planSpec))
        assertEquals("rejected", receipt.getString("status"))
        val detail = receipt.getJSONObject(CollaborationRecordValidation.DETAIL)
        assertEquals("typed_body_required", detail.getString("code"))
        assertEquals("/body/experiment_plan", detail.getString("path"))
        assertEquals("absent", detail.getString("actual"))
        assertFalse(receipt.getString("reason").contains("JSON"))
    }

    @Test fun genericPayloadIsPreservedButNotPromotedAndTypedRepairCanBePublished() {
        val f = CollaborationExecutableToolTest.Fixture()
        val receipt = publication(f, "generic-plan", "artifact", JSONObject().put("content", "Documentation").put(plan, f.planSpec))
        val saved = f.ref(receipt)
        val notice = saved.getJSONObject("registration_notice")
        assertFalse(notice.getBoolean("executable_registration"))
        assertEquals(plan, notice.getJSONArray("payload_fields").getString(0))
        assertEquals("artifact", saved.getString("kind"))
        assertEquals("record_kind_mismatch", failure { validate(f, saved, setOf(plan)) }.getString("code"))
        val repaired = f.ref(publication(f, "typed-plan", plan, JSONObject().put("content", "Typed fixture").put(plan, f.planSpec), round = 4))
        assertEquals(plan, validate(f, repaired, setOf(plan)).getString("kind"))
        assertEquals("artifact", f.reopen().read(f.access(), saved.getString("object_id"), 1)!!.getString("kind"))
    }

    @Test fun planReferencingGenericToolGetsStructuredPublicationFeedback() {
        val f = CollaborationExecutableToolTest.Fixture()
        val generic = f.ref(publication(f, "generic-tool", "artifact", JSONObject().put("content", "Documentation").put(tool, f.spec)))
        val spec = JSONObject(f.planSpec.toString()).put(tool, generic)
        val result = publication(f, "bad-source-plan", plan, JSONObject().put("content", "Fixture").put(plan, spec), round = 4)
        assertEquals("rejected", result.getString("status"))
        val detail = result.getJSONObject(CollaborationRecordValidation.DETAIL)
        assertEquals("record_kind_mismatch", detail.getString("code"))
        assertEquals(tool, detail.getJSONArray("expected").getString(0))
        assertEquals("artifact", detail.getString("actual"))
    }

    @Test fun originalFeedbackIsRetainedWithoutHostChosenRepairStrategy() {
        val receipt = JSONObject().put("status", "rejected").put("reason", "record rejected")
            .put(CollaborationRecordValidation.DETAIL, JSONObject().put("code", "record_kind_mismatch"))
        val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Fixture").toString()
        val observed = CollaborationPublicationProblem.observe(raw, receipt, null)
        assertEquals("accepted", observed.getString("json_parse_status"))
        assertEquals("workspace_contract", observed.getString("failure_phase"))
        assertEquals("record_kind_mismatch", observed.getJSONObject(CollaborationRecordValidation.DETAIL).getString("code"))
        assertFalse(observed.has("selected_strategy"))
    }
}
