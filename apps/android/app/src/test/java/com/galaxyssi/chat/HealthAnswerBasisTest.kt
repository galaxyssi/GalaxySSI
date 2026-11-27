package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAnswerBasisTest {
    private val report = """{"record":{"id":"record-a","revision":2},"metric":"GLUCOSE","measured_at":400,"value":"private value"}"""

    @Test fun sourceFactsFollowApprovedRecordRevisionAndNotDuplicatedHistoryOrUnavailableRelatedRows() {
        val sources = HealthAnswerBasis.snapshot("""{"metric":"GLUCOSE","assessment":$report,"measurement_history":{"samples":[$report]},
            "clarification_context":{"context_status":"CURRENT_RECORD","confirmed_at":405,"recorded_condition":"FASTING"},
            "related_measurements":{"selected":[{"metric":"GLUCOSE","available":false,"sample":$report}]},
            "selected_profile":{"fields":{"SEX":{"state":"UNKNOWN"}},"entries":[]}}""")
        assertEquals(listOf(HealthBasisSource(HealthBasisKind.MEASUREMENT, 400, metric = HealthMetric.GLUCOSE),
            HealthBasisSource(HealthBasisKind.CONTEXT, 405)), sources)
        assertTrue(sources.all { HealthBasisSource.from(it.json()) == it })
        assertFalse(sources.any { it.json().toString().contains("private value") || it.json().toString().contains("FASTING") })
    }
    @Test fun narrowerClinicalScopesCannotPickUpAnUnrelatedMeasurementOrUnverifiedUrl() {
        for ((scope, kind) in listOf("selected_instruction" to HealthBasisKind.INSTRUCTION, "selected_visit_followup" to HealthBasisKind.FOLLOW_UP)) {
            assertEquals(listOf(HealthBasisSource(kind, 0)), HealthAnswerBasis.snapshot(
                """{"$scope":{"quote":"private text"},"assessment":$report,"metric":"GLUCOSE"}"""))
        }
        assertTrue(HealthAnswerBasis.snapshot("""{"url":"https://example.test/uncited","clarification_context":{"context_status":"OTHER_RECORD_OR_REVISION","confirmed_at":149}}""").isEmpty())
    }
    @Test fun profileDateUsesOnlyActualIncludedUpdatedFieldsAndEntries() {
        val sources = HealthAnswerBasis.snapshot("""{"selected_profile":{"fields":{"A":{"state":"KNOWN","updated_at":12},
            "B":{"state":"UNKNOWN","updated_at":99}},"entries":[{"updated":30,"detail":"private"}]}}""")
        assertEquals(listOf(HealthBasisSource(HealthBasisKind.PROFILE, 30)), sources)
    }
}
