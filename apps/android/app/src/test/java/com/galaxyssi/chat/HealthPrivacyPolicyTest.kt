package com.galaxyssi.chat

import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class HealthPrivacyPolicyTest {
    @Test fun localUsesAreIndependentAndOnlineUseDefaultsOff() {
        val p = HealthPrivacyPolicy()
        assertTrue(p.metrics); assertTrue(p.profile); assertFalse(p.online); assertFalse(p.images)
        assertEquals(HealthPrivacyOption.CONFIRMED_METRICS, HealthAccessPurpose.TREND.permission)
        assertEquals(HealthPrivacyOption.PROFILE_CONTEXT, HealthAccessPurpose.PROFILE_CONTEXT.permission)
        assertNull(HealthAccessPurpose.SAVE_RECORDS.permission)
    }
    @Test fun originalPermissionCannotBeEnabledWhileOnlineIsOff() {
        assertTrue(runCatching { HealthPrivacyPolicy().change(HealthPrivacyOption.ORIGINAL_IMAGES, true) }.isFailure)
    }
    @Test fun revokingOnlineClearsImagesAndReenablingDoesNotRestoreThem() {
        val enabled = HealthPrivacyPolicy(online = true, images = true)
        val disabled = enabled.change(HealthPrivacyOption.ONLINE_ANALYSIS, false)
        assertFalse(disabled.images); assertFalse(disabled.online)
        assertFalse(disabled.change(HealthPrivacyOption.ONLINE_ANALYSIS, true).images)
    }
    @Test fun policySerializationPreservesTheExactRevision() {
        val p = HealthPrivacyPolicy(metrics = false, profile = false, online = true, images = true, version = "revision")
        assertEquals(p, HealthPrivacyPolicy.from(p.json()))
    }
    @Test fun localRetentionDefaultsOnForExistingPoliciesAndIsIndependentOfOnlineImages() {
        val current = HealthPrivacyPolicy(online = true, images = true, version = "existing")
        val legacy = current.json().also { it.remove("retain_import_originals") }
        assertEquals(current, HealthPrivacyPolicy.from(legacy))
        val disabled = current.change(HealthPrivacyOption.RETAIN_IMPORT_ORIGINALS, false)
        assertTrue(disabled.online && disabled.images)
        assertFalse(disabled.retainImportOriginals)
        assertEquals(disabled, HealthPrivacyPolicy.from(disabled.json()))
    }
    @Test fun trendScopeUsesTheRequestedTimeZoneAndSourceWithoutFileIdentity() {
        val day = LocalDate.of(2026, 3, 8)
        val zone = ZoneId.of("America/New_York")
        val spec = HealthTrendSpec(HealthMetric.STEPS, day, day, zone, HealthMetric.STEPS.units.first(), source = HealthTrendSource(manualOnly = true))
        val scope = HealthAccessScope.trend(HealthAccessPurpose.TREND, spec)
        assertEquals(23 * 60 * 60 * 1000L, scope.until - scope.from)
        assertEquals(HealthAccessSource.MANUAL, scope.source)
        assertEquals(scope, HealthAccessScope.from(scope.json()))
        assertFalse(scope.json().has("record"))
    }
    @Test fun explicitExportScopeKeepsFormatAndNotesChoiceButNotOriginalId() {
        val original = java.util.UUID.randomUUID().toString()
        val session = HealthRecordExportSession(java.util.UUID.randomUUID().toString(), HealthRecordExportScope(
            setOf(HealthMetric.STEPS), originalId = original, annotations = true, format = HealthRecordExportFormat.XLSX), 1L, count = 12)
        val scope = HealthAccessScope.records(session)
        assertEquals(12L, scope.count); assertTrue(scope.annotations); assertEquals(HealthAccessFormat.XLSX, scope.format)
        assertFalse(scope.json().toString().contains(original)); assertEquals(scope, HealthAccessScope.from(scope.json()))
    }
    @Test fun rejectInvalidScopesRatherThanAcceptingAnUnboundedMalformedRequest() {
        assertTrue(runCatching { HealthAccessScope(HealthAccessPurpose.TREND) }.isFailure)
        assertTrue(runCatching { HealthAccessScope.originals(-1) }.isFailure)
        assertTrue(runCatching { HealthAccessScope(HealthAccessPurpose.PROFILE_CONTEXT, count = 0, from = 4, until = 4) }.isFailure)
    }
    @Test fun deleteScopeCountsDoNotIncludeThePrivatePreviewToken() {
        val scope = HealthAccessScope.deleteProfile(HealthProfileDeletePreview(2, 5, 1, "private-version"))
        assertEquals(2, scope.basicCount); assertEquals(5L, scope.count); assertEquals(1L, scope.drafts)
        assertFalse(scope.json().toString().contains("private-version"))
    }
    @Test fun incompleteEventHasItsOwnOutcomeRatherThanBeingReportedAsSuccess() {
        val event = HealthAccessEvent("id", 1L, HealthAccessScope.originals(2, true), HealthAccessOutcome.STARTED, "rev")
        assertEquals(event, HealthAccessEvent.from(event.json()))
    }
}
