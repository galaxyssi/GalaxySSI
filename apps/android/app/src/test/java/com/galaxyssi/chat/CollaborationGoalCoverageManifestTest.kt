package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationGoalCoverageManifestTest {
    private fun fixture() = CollaborationMultipartGoalCoverageTest.Fixture()
    private fun envelope(root: JSONObject) = JSONObject().put("manifest", root)

    @Test fun savedLeafAndHierarchicalDirectoriesAcceptTheSameReviewedParts() {
        val h = fixture()
        val parts = h.parts()
        val leaf = h.manifest(parts)
        assertTrue(h.evaluate(envelope(leaf)).feedback, h.evaluate(envelope(leaf)).accepted)
        val children = parts.map { h.manifest(listOf(it)) }
        val root = h.manifest(children = children, round = 21)
        val receipt = h.evaluate(envelope(root))
        assertTrue(receipt.feedback, receipt.accepted)
        val resolved = CollaborationGoalCoverageManifest.resolve(envelope(root), JSONArray(h.f.prior), h.f.goal, h::saved)
        assertEquals(3, resolved.parts.size)
        assertEquals(4, resolved.manifests.size)
        assertTrue(envelope(root).toString().length < h.coverage(parts).toString().length)
    }

    @Test fun omittedRepeatedAndStaleBranchesCannotHideCoverageLoss() {
        val h = fixture()
        val parts = h.parts()
        val leaves = parts.map { h.manifest(listOf(it)) }
        assertFalse(h.evaluate(envelope(h.manifest(children = leaves.drop(1), round = 21))).accepted)
        assertFalse(h.evaluate(envelope(h.manifest(children = leaves + leaves[0], round = 21))).accepted)
        val root = h.manifest(children = leaves, round = 21)
        h.manifest(listOf(parts[0]), previous = leaves[0], round = 22)
        assertFalse(h.evaluate(envelope(root)).accepted)
    }

    @Test fun duplicateMappingsAcrossDistinctLeafArtifactsAreRejected() {
        val h = fixture()
        val parts = h.parts()
        val root = h.manifest(children = listOf(h.manifest(parts), h.manifest(parts)), round = 21)
        val receipt = h.evaluate(envelope(root))
        assertFalse(receipt.accepted)
        assertTrue(receipt.feedback, receipt.feedback.contains("Duplicate mapping"))
    }

    @Test fun missingParentsAndWrongBindingsCannotBeReplacedByInlineClaims() {
        listOf("parents", "goal_sha256", "criteria_sha256", "format", "mixed", "empty").forEach { change ->
            val h = fixture()
            val parts = h.parts()
            val leaf = h.manifest(parts)
            val saved = h.saved(leaf)
            val body = saved.getJSONObject("body")
            val manifest = body.getJSONObject(CollaborationGoalCoverageManifest.FIELD)
            var parents = saved.getJSONArray("parents")
            when (change) {
                "parents" -> parents = JSONArray()
                "mixed" -> manifest.put("manifests", JSONArray().put(leaf))
                "empty" -> { manifest.remove("parts"); manifest.put("manifests", JSONArray()) }
                else -> manifest.put(change, "forged")
            }
            val invalid = h.publish("artifact", body, parents = parents, round = 21)
            assertFalse(change, h.evaluate(envelope(invalid)).accepted)
        }
        val h = fixture()
        val leaf = h.manifest(h.parts())
        assertFalse(h.evaluate(envelope(leaf).put("parts", JSONArray())).accepted)
        assertFalse(h.evaluate(envelope(JSONObject().put("url", "https://example.com"))).accepted)
        assertFalse(h.f.evaluate(h.f.assessment().put("goal_coverage", envelope(leaf)).toString(),
            h.access.copy(runId = "different-run", turnId = "different-turn")).accepted)
    }

    @Test fun manifestUpdateBetweenResolutionAndSnapshotCannotCertifyOldDirectory() {
        val h = fixture()
        val parts = h.parts()
        val root = h.manifest(parts)
        var triggered = false
        val rows = object : CollaborationWorkspaceRows by h.f.rows {
            override fun read(key: String): String? {
                if (!triggered && key.startsWith("mutation:")) {
                    triggered = true
                    h.manifest(parts.dropLast(1), previous = root, round = 22)
                }
                return h.f.rows.read(key)
            }
        }
        val engine = CollaborationGoalAcceptance(CollaborationResearchWorkspace(rows), h.f.ledger)
        val result = engine.evaluate(h.access, h.f.assessment().put("goal_coverage", envelope(root)).toString(), h.f.prior, h.f.goal)
        assertTrue(triggered)
        assertFalse(result.accepted)
        assertTrue(result.feedback, result.feedback.contains("newer revision"))
    }

    @Test fun manifestUpdateDuringAcceptanceIsCaughtByTheSharedMutationFence() {
        val h = fixture()
        val parts = h.parts()
        val root = h.manifest(parts)
        val target = parts[0].getJSONObject("mapping")
        var armed = false
        var triggered = false
        val rows = object : CollaborationWorkspaceRows by h.f.rows {
            override fun read(key: String): String? {
                val result = h.f.rows.read(key)
                if (key.startsWith("mutation:")) armed = true
                if (armed && !triggered && key.endsWith("revision:${target.getString("object_id")}:1")) {
                    triggered = true
                    h.manifest(parts.dropLast(1), previous = root, round = 22)
                }
                return result
            }
        }
        val engine = CollaborationGoalAcceptance(CollaborationResearchWorkspace(rows), h.f.ledger)
        val result = engine.evaluate(h.access, h.f.assessment().put("goal_coverage", envelope(root)).toString(), h.f.prior, h.f.goal)
        assertTrue(triggered)
        assertFalse(result.accepted)
    }

    @Test fun deepDirectoryWalkIsIterativeAndCyclesAreRejected() {
        val h = fixture()
        val part = h.parts().first()
        fun ref(index: Int) = JSONObject().put("object_id", index.toString(16).padStart(64, '0'))
            .put("revision", 1).put("sha256", "a".repeat(64))
        fun resolve(cycle: Boolean): CollaborationGoalCoverageManifest.Resolved = CollaborationGoalCoverageManifest.resolve(
            envelope(ref(1)), JSONArray(h.f.prior), h.f.goal) { current ->
                val index = current.getString("object_id").toInt(16)
                val body = h.header()
                val parents = JSONArray()
                if (index == 4097 && !cycle) {
                    body.put("parts", JSONArray().put(part))
                    parents.put(part.getJSONObject("mapping")).put(part.getJSONObject("review"))
                } else {
                    val child = ref(if (index == 4097) 1 else index + 1)
                    body.put("manifests", JSONArray().put(child)); parents.put(child)
                }
                JSONObject().put("kind", "artifact").put("body", JSONObject().put(CollaborationGoalCoverageManifest.FIELD, body))
                    .put("parents", parents)
            }
        assertEquals(4097, resolve(false).manifests.size)
        assertThrows(IllegalArgumentException::class.java) { resolve(true) }
    }
}
