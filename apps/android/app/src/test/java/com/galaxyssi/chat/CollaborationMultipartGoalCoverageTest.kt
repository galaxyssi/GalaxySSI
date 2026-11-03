package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationMultipartGoalCoverageTest {
    internal class Fixture(goal: String = "Document the outcome; preserve all constraints; identify remaining uncertainty.") {
        val f = CollaborationGoalAcceptanceTest.Fixture(goal = goal)
        val access = f.access.copy(round = 100)
        private var sequence = 0
        fun select(values: JSONArray, ids: Set<String>) = JSONArray((0 until values.length()).map { values.getJSONObject(it) }
            .filter { it.getString("id") in ids })
        fun part(ids: Set<String>, author: String = "mapper-${sequence}", reviewer: String = "reviewer-${sequence}"): JSONObject {
            val body = f.mappingBody().let { it.put("segments", select(it.getJSONArray("segments"), ids)) }
            val mapping = publish("artifact", JSONObject().put(CollaborationSemanticGoalCoverage.MAPPING, body), author, round = 10)
            val check = f.coverageReviewBody(mapping).let { it.put("segments", select(it.getJSONArray("segments"), ids)) }
            val review = publish(CollaborationReviewContract.KIND, JSONObject().put(CollaborationSemanticGoalCoverage.REVIEW, check),
                reviewer, JSONArray().put(mapping), round = 11)
            return JSONObject().put("mapping", mapping).put("review", review)
        }
        fun publish(kind: String, body: JSONObject, author: String = "lead", parents: JSONArray = JSONArray(),
                    round: Long = 20, previous: JSONObject? = null): JSONObject {
            val node = "multipart-${++sequence}"
            val item = f.item(node, kind, body).put("parents", parents)
            previous?.let { item.put("object_id", it.getString("object_id")).put("base_revision", it.getInt("revision")) }
            return f.publish(access.copy(nodeId = node, personId = author, round = round), item)
        }
        fun saved(ref: JSONObject) = requireNotNull(f.workspace.read(access, ref.getString("object_id"), ref.getInt("revision")))
        fun parts() = (1..3).map { part(setOf("source-$it")) }
        fun coverage(parts: List<JSONObject>) = JSONObject().put("parts", JSONArray(parts))
        fun evaluate(coverage: JSONObject) = f.evaluate(f.assessment().put("goal_coverage", coverage).toString(), access)
        fun header() = JSONObject().put("format", CollaborationGoalCoverageManifest.FORMAT)
            .put("goal_sha256", CollaborationSemanticGoalCoverage.source(f.goal).getString("goal_sha256"))
            .put("criteria_sha256", CollaborationSemanticGoalCoverage.criteriaHash(JSONArray(f.prior)))
        fun manifest(parts: List<JSONObject>? = null, children: List<JSONObject>? = null,
                     previous: JSONObject? = null, round: Long = 20): JSONObject {
            val parents = JSONArray()
            val body = header()
            if (parts != null) {
                body.put("parts", JSONArray(parts))
                parts.forEach { parents.put(it.getJSONObject("mapping")).put(it.getJSONObject("review")) }
            }
            if (children != null) {
                body.put("manifests", JSONArray(children))
                children.forEach(parents::put)
            }
            return publish("artifact", JSONObject().put(CollaborationGoalCoverageManifest.FIELD, body), parents = parents,
                previous = previous, round = round)
        }
    }

    @Test fun independentPartsCoverTheWholeGoalWithoutOneGiantMapping() {
        val h = Fixture()
        val parts = h.parts()
        parts.forEach { part -> assertFalse(h.evaluate(h.coverage(listOf(part))).accepted) }
        val result = h.evaluate(h.coverage(parts))
        assertTrue(result.feedback, result.accepted)
        assertTrue(result.feedback.contains("reviewer judgment"))
    }

    @Test fun thousandsOfSourceSegmentsCanBePartitionedWithoutTruncation() {
        val h = Fixture((1..4097).joinToString(";") { "Preserve requirement $it" })
        val mapping = h.f.mappingBody()
        val review = h.f.coverageReviewBody(h.f.mapping)
        val validation = CollaborationSemanticGoalCoverage.Validation(JSONArray(h.f.prior), h.f.goal)
        val parts = (1..4097).chunked(31).map { batch ->
            val ids = batch.map { "source-$it" }.toSet()
            validation.part(JSONObject(mapping.toString()).put("segments", h.select(mapping.getJSONArray("segments"), ids)),
                JSONObject(review.toString()).put("segments", h.select(review.getJSONArray("segments"), ids)))
        }
        validation.complete(parts)
        assertEquals(4097, parts.sumOf { it.sourceIds.size })
        assertThrows(IllegalArgumentException::class.java) { validation.complete(parts.dropLast(1)) }
        assertThrows(IllegalArgumentException::class.java) { validation.complete(parts + parts.last()) }
    }

    @Test fun missingMiddleExtraOrRepeatedCoverageCannotPass() {
        val h = Fixture()
        val parts = h.parts()
        assertFalse(h.evaluate(h.coverage(listOf(parts.first(), parts.last()))).accepted)
        assertFalse(h.evaluate(h.coverage(parts + parts.first())).accepted)
        assertFalse(h.evaluate(h.coverage(parts + h.part(setOf("source-1")))).accepted)
    }

    @Test fun everyPartNeedsItsOwnIndependentCurrentReview() {
        listOf("mapper", "lead").forEach { reviewer ->
            val h = Fixture()
            val parts = listOf(h.part(setOf("source-1"), "mapper", reviewer),
                h.part(setOf("source-2", "source-3")))
            assertFalse(h.evaluate(h.coverage(parts)).accepted)
        }
        val h = Fixture()
        val parts = h.parts()
        parts[1].put("review", parts[0].getJSONObject("review"))
        assertFalse(h.evaluate(h.coverage(parts)).accepted)
    }

    @Test fun oneStaleMappingOrForgedReferenceRejectsTheWholeGroup() {
        listOf("mapping", "review").forEach { field ->
            val h = Fixture()
            val parts = h.parts()
            parts[1].getJSONObject(field).put("sha256", "0".repeat(64))
            assertFalse(h.evaluate(h.coverage(parts)).accepted)
        }
        val h = Fixture()
        val parts = h.parts()
        val previous = parts[1].getJSONObject("mapping")
        h.publish("artifact", h.saved(previous).getJSONObject("body"), "mapper-new", previous = previous)
        assertFalse(h.evaluate(h.coverage(parts)).accepted)
    }

    @Test fun unselectedDissentOnAnyPartStillBlocksCompletion() {
        val h = Fixture()
        val parts = h.parts()
        val target = parts[1].getJSONObject("mapping")
        val body = h.saved(parts[1].getJSONObject("review")).getJSONObject("body")
        body.getJSONObject(CollaborationSemanticGoalCoverage.REVIEW).put("verdict", "refuted")
            .put("unresolved", JSONArray().put("An original qualifier is not preserved"))
        h.publish(CollaborationReviewContract.KIND, body, "independent-dissenter", JSONArray().put(target))
        val result = h.evaluate(h.coverage(parts))
        assertFalse(result.accepted)
        assertTrue(result.feedback, result.feedback.contains("dissent"))
    }

    @Test fun sourceAndCriteriaBindingsCannotDifferBetweenParts() {
        listOf("goal_sha256", "criteria_sha256").forEach { field ->
            val h = Fixture()
            val mapping = h.f.mappingBody().put(field, "0".repeat(64))
            val validation = CollaborationSemanticGoalCoverage.Validation(JSONArray(h.f.prior), h.f.goal)
            assertThrows(IllegalArgumentException::class.java) { validation.part(mapping, h.f.coverageReviewBody(h.f.mapping)) }
        }
    }

    @Test fun ambiguousEmptyAndMalformedInlineEnvelopesAreRejected() {
        val h = Fixture()
        val part = h.parts().first()
        listOf(JSONObject(), JSONObject().put("parts", JSONArray()), JSONObject(part.toString()).put("parts", JSONArray().put(part)),
            JSONObject().put("parts", "not an array"), JSONObject().put("parts", JSONArray().put(JSONObject(part.toString()).put("claim", "done"))))
            .forEach { assertFalse(h.evaluate(it).accepted) }
    }
}
