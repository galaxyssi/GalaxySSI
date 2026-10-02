package com.galaxyssi.chat

import android.content.Context
import android.os.Bundle
import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Host-driven, two-process persistence fixture. No model, tool, network or device-control execution. */
@RunWith(AndroidJUnit4::class)
class CollaborationGoalContractRecoveryDeviceTest {
    @Test fun processCheckpointPhase() {
        val arguments = InstrumentationRegistry.getArguments()
        val phase = arguments.getString("goalContractPhase").orEmpty()
        assumeTrue("Explicit seed/recover phase required", phase.isNotEmpty())
        require(phase in setOf("seed", "recover"))
        val token = arguments.getString("goalContractToken").orEmpty()
        require(token.matches(Regex("[a-f0-9]{32}")))
        val fixture = Fixture(InstrumentationRegistry.getInstrumentation().targetContext, token)
        // Deliberately no finally/@After cleanup: any assertion failure preserves the fixture and marker.
        val marker = if (phase == "seed") fixture.seed() else fixture.recover()
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
            putString("goal_contract_phase", phase)
            putString("goal_contract_fixture", token)
            putString("fixture_pid", Process.myPid().toString())
            putString("seed_pid", marker.getInt("seed_pid").toString())
            putString("goal_contract_pages", marker.getJSONObject("healthy_descriptor").getInt("page_count").toString())
            putString("goal_contract_fixture_state", if (phase == "seed") "retained" else "verified_and_removed")
        })
    }

    private class Fixture(private val context: Context, private val token: String) {
        private val group = "goal-contract-recovery-fixture-$token"
        private val groups = CollaborationGroupStore(context)
        private val ledger = CollaborationEvidenceLedger(context)
        private val contracts = CollaborationGoalContractStore(context)
        private val contractRows = AgentEncryptedDatabase(context, CONTRACT_DATABASE)
        private val ledgerRows = AgentEncryptedDatabase(context, LEDGER_DATABASE)
        private val artifacts = AgentEncryptedDatabase(context, ARTIFACT_DATABASE)
        private val artifactKey = "fixture:$token"
        private val contractPrefix = "group:${digest(group)}:"
        private val ledgerPrefix = "group:${AgentNativeJsonCodec.sha256(group)}:"
        private val good = CollaborationWorkspaceAccess(group, "fixture-run-$token", "fixture-turn-$token", 7,
            "intact-reader", "fixture-member", setOf("fixture-dependency-a", "fixture-dependency-b"))
        private val missing = good.copy(nodeId = "missing-page-reader")
        private val goal: String by lazy {
            val prefix = "Private goal fixture $token: "
            val suffix = "\nKeep \"quotes\", \\ paths, \u4e2d\u6587 and \uD83D\uDE80; never drop the final constraint.\n"
            prefix + "g".repeat(100_000 - prefix.length - suffix.length) + suffix
        }
        private val criteria: String by lazy {
            " \n" + JSONArray().put(JSONObject().put("id", "fixture-criterion")
                .put("requirement", "Private criteria fixture $token: " + "c".repeat(21_000) + "\n\u4e2d\u6587\uD83D\uDE80")
                .put("verification", "documentary")).toString() + "\t "
        }
        private val sections: Map<String, String> by lazy {
            linkedMapOf("roster" to ("Private roster fixture $token\n" + "Member \"\u4e2d\u6587\" \\ \uD83D\uDE80\n".repeat(2500)),
                "previousAssessment" to ("Private assessment fixture $token\n" + "Untested; preserve qualifiers.\n".repeat(1500)),
                "emptyOptional" to "")
        }

        fun seed(): JSONObject {
            check(!artifacts.contains(artifactKey)) { "Fixture marker already exists; use recover or a fresh token" }
            check(groups.load(group) == null && contractRows.keys(contractPrefix).isEmpty() && ledgerRows.keys(ledgerPrefix).isEmpty()) {
                "Fixture state already exists; refusing to overwrite retained evidence"
            }
            val marker = JSONObject().put("format", MARKER_FORMAT).put("token", token).put("group_id", group)
                .put("seed_pid", Process.myPid()).put("stage", "seed_started")
            artifacts.writeString(artifactKey, marker.toString())
            groups.update(group) { it.copy(members = listOf(CollaborationMember(id = good.personId,
                name = "Contract Fixture", agentId = "fixture-only", providerLabel = "Fixture")), coordinatorId = good.personId) }

            // Production authorization must already exist before any prompt/contract publication or pinning.
            ledger.bind(source(good), good)
            ledger.bind(source(missing), missing)
            assertLedgerBindings()
            val healthy = ok(contracts.publish(good, goal, criteria, sections))
            val healthyId = healthy.getString("snapshot_id")
            ok(contracts.bind(good, healthyId))
            val first = ok(contracts.read(good))
            assertEquals(0, first.getInt("page_index"))
            assertTrue(healthy.getInt("page_count") > 2)
            val resumeCursor = first.getString("next_cursor")
            val resumed = ok(contracts.read(good, resumeCursor))
            assertEquals(1, resumed.getInt("page_index"))
            marker.put("healthy_descriptor", healthy).put("healthy_first_page", first)
                .put("healthy_cursor", resumeCursor).put("healthy_resume_sha256", digest(resumed.toString()))
                .put("stage", "healthy_seeded")
            artifacts.writeString(artifactKey, marker.toString())

            val damaged = ok(contracts.publish(missing, goal, criteria, sections + ("faultFixture" to "One deliberately absent page")))
            val damagedId = damaged.getString("snapshot_id")
            assertNotEquals(healthyId, damagedId)
            ok(contracts.bind(missing, damagedId))
            val damagedFirst = ok(contracts.read(missing))
            val missingCursor = damagedFirst.getString("next_cursor")
            val target = ok(contracts.read(missing, missingCursor))
            val pageIndex = target.getInt("page_index")
            assertEquals(1, pageIndex)
            val pageKey = "$contractPrefix" + "snapshot:$damagedId:page:$pageIndex"
            check(pageKey.startsWith(contractPrefix) && pageKey != "${contractPrefix}snapshot:$healthyId:page:$pageIndex")
            assertTrue(contractRows.contains(pageKey))
            assertEquals(target.getString("page_sha256"), digest(contractRows.readString(pageKey, "")))
            marker.put("missing_descriptor", damaged).put("missing_cursor", missingCursor)
                .put("missing_page_key", pageKey).put("missing_page_index", pageIndex)
                .put("missing_page_sha256", target.getString("page_sha256")).put("stage", "before_page_removal")
            artifacts.writeString(artifactKey, marker.toString())
            // Fault injection affects only one exact row of this dedicated fixture's second snapshot.
            contractRows.remove(pageKey)
            assertFalse(contractRows.contains(pageKey))
            rejected(contracts.read(missing, missingCursor), "snapshot_corrupt")
            assertNoDelivery(good, healthyId)
            assertNoDelivery(missing, damagedId)
            assertNoObservations()
            marker.put("contract_rows_sha256", fingerprint(contractRows, contractPrefix))
                .put("ledger_rows_sha256", fingerprint(ledgerRows, ledgerPrefix)).put("stage", "seed_ready")
            artifacts.writeString(artifactKey, marker.toString())
            assertEncryptedAtRest(marker)
            return marker
        }

        fun recover(): JSONObject {
            check(artifacts.contains(artifactKey)) { "Run seed in a separate process first; recovery never reseeds" }
            val marker = JSONObject(artifacts.readString(artifactKey, ""))
            assertEquals(MARKER_FORMAT, marker.getString("format"))
            assertEquals(token, marker.getString("token"))
            assertEquals(group, marker.getString("group_id"))
            assertEquals("seed_ready", marker.getString("stage"))
            assertNotEquals("Recovery must run in a different target process", marker.getInt("seed_pid"), Process.myPid())
            assertNotNull(groups.load(group))
            assertLedgerBindings()
            assertEncryptedAtRest(marker)
            assertEquals(marker.getString("contract_rows_sha256"), fingerprint(contractRows, contractPrefix))
            assertEquals(marker.getString("ledger_rows_sha256"), fingerprint(ledgerRows, ledgerPrefix))

            val descriptor = marker.getJSONObject("healthy_descriptor")
            val id = descriptor.getString("snapshot_id")
            assertSameJson("Pinned descriptor changed", descriptor, ok(contracts.lookup(good)))
            assertSameJson("Idempotent binding changed", descriptor, ok(contracts.bind(good, id)))
            val missingDescriptor = marker.getJSONObject("missing_descriptor")
            val missingId = missingDescriptor.getString("snapshot_id")
            rejected(contracts.bind(good, missingId), "access_already_bound")
            rejected(contracts.read(good, missingId, ""), "snapshot_not_bound")
            rejected(contracts.read(good.copy(round = good.round + 1)), "access_denied")
            rejected(contracts.read(good.copy(dependencyNodes = emptySet())), "access_denied")

            val first = marker.getJSONObject("healthy_first_page")
            assertSameJson("Persisted first page changed", first, ok(contracts.read(good)))
            val assembly = Assembly(descriptor)
            assembly.add(first)
            var cursor = marker.getString("healthy_cursor")
            var firstResumedPage = true
            while (true) {
                val page = ok(contracts.read(good, cursor))
                if (firstResumedPage) {
                    assertEquals(marker.getString("healthy_resume_sha256"), digest(page.toString()))
                    firstResumedPage = false
                }
                assembly.add(page)
                if (page.isNull("next_cursor")) break
                cursor = page.getString("next_cursor")
            }
            assembly.verify(goal, criteria, sections)

            assertSameJson("Missing-page pin changed", missingDescriptor, ok(contracts.lookup(missing)))
            val pageKey = marker.getString("missing_page_key")
            assertEquals("${contractPrefix}snapshot:$missingId:page:${marker.getInt("missing_page_index")}", pageKey)
            assertFalse(contractRows.contains(pageKey))
            val failed = contracts.read(missing, marker.getString("missing_cursor"))
            rejected(failed, "snapshot_corrupt")
            assertFalse(failed.has("fragments"))
            assertFalse(failed.has("next_cursor"))
            assertFalse(failed.has("page_sha256"))
            rejected(contracts.bind(missing, id), "access_already_bound")
            rejected(contracts.read(good, marker.getString("missing_cursor")), "invalid_cursor")
            assertSameJson("Intact pin changed after rejection", descriptor, ok(contracts.lookup(good)))
            assertSameJson("Damaged pin changed after rejection", missingDescriptor, ok(contracts.lookup(missing)))
            assertNoDelivery(good, id)
            assertNoDelivery(missing, missingId)
            assertNoObservations()
            assertEquals(marker.getString("contract_rows_sha256"), fingerprint(contractRows, contractPrefix))
            assertEquals(marker.getString("ledger_rows_sha256"), fingerprint(ledgerRows, ledgerPrefix))

            // Cleanup is reached only after every recovery assertion above passes; marker is removed last.
            CollaborationGoalContractStore.remove(context, group)
            CollaborationEvidenceLedger.remove(context, group)
            groups.remove(group)
            artifacts.remove(artifactKey)
            return marker
        }

        private fun source(access: CollaborationWorkspaceAccess) = AgentTeamDispatchIds.sourceMessageId("$group:${access.nodeId}")

        private fun assertLedgerBindings() {
            listOf(good, missing).forEach { access ->
                assertEquals(access, ledger.binding(source(access), group, access.turnId))
            }
        }

        private fun assertNoDelivery(access: CollaborationWorkspaceAccess, id: String) {
            val state = ok(contracts.delivery(access, id))
            assertEquals(0, state.getInt("delivered_page_count"))
            assertFalse(state.getBoolean("all_pages_delivered"))
            assertEquals("", state.getString("next_undelivered_cursor"))
            assertEquals("delivery_only_not_comprehension", state.getString("trust"))
            assertFalse(contractRows.keys(contractPrefix).any { ":delivery:" in it })
        }

        private fun assertNoObservations() {
            assertTrue(ledger.browse(good).first.isEmpty())
            assertTrue(ledger.browse(missing).first.isEmpty())
            assertFalse(ledgerRows.keys(ledgerPrefix).any { ":observation:" in it })
        }

        private fun assertEncryptedAtRest(marker: JSONObject) {
            val privateSentinels = listOf("Private goal fixture $token", "Private roster fixture $token",
                "Private assessment fixture $token", "Private criteria fixture $token", marker.getString("healthy_cursor"))
            fun inspect(database: AgentEncryptedDatabase, prefix: String) {
                var count = 0
                database.indexedTransaction { sql ->
                    sql.query("encrypted_values", arrayOf("encrypted_value"), "storage_key >= ? AND storage_key < ?",
                        arrayOf(prefix, "$prefix\uffff"), null, null, null).use { values ->
                        while (values.moveToNext()) {
                            val encoded = values.getString(0)
                            assertTrue("Fixture row must use authenticated encrypted storage", AgentStorageCipher.isEncrypted(encoded))
                            assertTrue("Fixture plaintext/cursor found in storage column", privateSentinels.none(encoded::contains))
                            count++
                        }
                    }
                }
                assertTrue("Expected encrypted fixture rows", count > 0)
            }
            inspect(contractRows, contractPrefix)
            inspect(ledgerRows, ledgerPrefix)
            inspect(artifacts, artifactKey)
        }
    }

    private class Assembly(private val descriptor: JSONObject) {
        private data class TextParts(val text: StringBuilder = StringBuilder(), var nextPart: Int = 0, var ended: Boolean = false)
        private val fields = linkedMapOf<Pair<String, String>, TextParts>()
        private val contextNames = mutableMapOf<String, String>()
        private var nextPage = 0

        fun add(page: JSONObject) {
            assertEquals(nextPage++, page.getInt("page_index"))
            assertTrue("Page count exceeded", nextPage <= descriptor.getInt("page_count"))
            assertEquals(descriptor.getString("snapshot_id"), page.getString("snapshot_id"))
            assertEquals(descriptor.getString("snapshot_sha256"), page.getString("snapshot_sha256"))
            assertEquals(descriptor.getInt("page_count"), page.getInt("page_count"))
            val encoded = page.toString().toByteArray(Charsets.UTF_8)
            assertTrue("Encoded page budget exceeded", encoded.size <= descriptor.getInt("max_page_bytes"))
            JSONObject(String(encoded, Charsets.UTF_8))
            val fragments = page.getJSONArray("fragments")
            assertTrue(fragments.length() > 0)
            repeat(fragments.length()) { index ->
                val fragment = fragments.getJSONObject(index)
                val stream = fragment.getString("stream")
                val identity = if (fragment.has("context_index")) fragment.getInt("context_index").toString()
                    else fragment.getString("source_id")
                val value = fields.getOrPut(stream to identity) { TextParts() }
                assertFalse("Fragment after terminal part", value.ended)
                assertEquals(value.nextPart++, fragment.getInt("part"))
                assertEquals(value.text.length, fragment.getInt("start_utf16"))
                val text = fragment.getString("text")
                assertTrue("Invalid Unicode fragment", Charsets.UTF_8.newEncoder().canEncode(text))
                assertTrue("Surrogate pair split", text.isEmpty() || !text.first().isLowSurrogate() && !text.last().isHighSurrogate())
                value.text.append(text)
                assertEquals(value.text.length, fragment.getInt("end_utf16"))
                value.ended = fragment.getBoolean("last")
                if (stream == "context" && !fragment.isNull("id")) {
                    val name = fragment.getString("id")
                    assertTrue("Context name changed", contextNames[identity]?.let { it == name } ?: true)
                    contextNames[identity] = name
                }
            }
            assertEquals(nextPage == descriptor.getInt("page_count"), page.isNull("next_cursor"))
        }

        fun verify(goal: String, criteria: String, sections: Map<String, String>) {
            assertEquals(descriptor.getInt("page_count"), nextPage)
            assertTrue("Incomplete fragment stream", fields.values.all { it.ended })
            fun exact(stream: String, id: String, expected: String) {
                assertTrue("Exact $stream reconstruction failed", fields[stream to id]?.text?.toString() == expected)
            }
            exact("goal", "", goal)
            exact("criteria", "", criteria)
            assertEquals(digest(goal), descriptor.getString("goal_sha256"))
            assertEquals(digest(criteria), descriptor.getString("criteria_json_sha256"))
            assertEquals(CollaborationSemanticGoalCoverage.criteriaHash(JSONArray(criteria)), descriptor.getString("criteria_sha256"))
            val sources = CollaborationSemanticGoalCoverage.source(goal).getJSONArray("segments")
            assertEquals(sources.length(), descriptor.getInt("source_segment_count"))
            repeat(sources.length()) { index ->
                val source = sources.getJSONObject(index)
                exact("source", source.getString("id"), source.getString("text"))
            }
            assertEquals(sections.size, descriptor.getInt("context_section_count"))
            sections.toSortedMap().entries.forEachIndexed { index, (name, text) ->
                assertTrue("Exact context name reconstruction failed", contextNames[index.toString()] == name)
                exact("context", index.toString(), text)
            }
            assertEquals(2 + sources.length() + sections.size, fields.size)
        }
    }

    companion object {
        // These private production storage names are used only for scoped fault injection/at-rest inspection.
        private const val CONTRACT_DATABASE = "galaxyssi_collaboration_goal_contract_v1"
        private const val LEDGER_DATABASE = "galaxyssi_collaboration_evidence_v1"
        private const val ARTIFACT_DATABASE = "test_goal_contract_recovery_artifacts_v1"
        private const val MARKER_FORMAT = "galaxyssi.goal-contract-recovery-fixture.v1"

        private fun digest(value: String) = AgentResultRecoveryClient.sha256(value.toByteArray(Charsets.UTF_8))
        private fun fingerprint(rows: AgentEncryptedDatabase, prefix: String) = AgentNativeJsonCodec.sha256(
            rows.keys(prefix).sorted().map { key -> listOf(key, digest(rows.readString(key, ""))) })
        private fun ok(value: JSONObject) = value.also { assertEquals("ok", it.optString("status")) }
        private fun rejected(value: JSONObject, reason: String) {
            assertEquals("rejected", value.optString("status"))
            assertEquals(reason, value.optString("reason"))
        }
        private fun assertSameJson(message: String, expected: JSONObject, actual: JSONObject) {
            assertTrue(message, expected.toString() == actual.toString())
        }
    }
}
