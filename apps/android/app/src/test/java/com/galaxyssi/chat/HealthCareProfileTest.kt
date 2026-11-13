package com.galaxyssi.chat

import java.time.Instant
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareProfileTest {
    private fun id() = UUID.randomUUID().toString()
    private val now = Instant.parse("2026-11-08T10:00:00Z").toEpochMilli()
    private val scope = HealthCareProfileScope("", setOf(HealthProfileField.HEIGHT), emptySet())
    private val link = HealthCareProfileLink(scope, HealthProfileStamp("", mapOf("field:HEIGHT" to "v1")))
    private val issue = HealthCareConcern(id(), HealthMetric.GLUCOSE, 1, now, now, "source",
        HealthCareAssessment(HealthCareRecordRef(id(), 1), now, "6.3", "mmol/L", "4-6", setOf(HealthCareSignal.REPORT_HIGH)),
        profileLink = link)
    private val grant = HealthCareDiscussionGrant(id(), id(), issue.id, 1, "settings", "privacy",
        "a".repeat(64), now, "fixture", "fixture-model", "high", profileLink = link)
    private fun context(value: HealthProfileInput? = HealthProfileInput("170", "cm")) =
        HealthProfileContext(mapOf(HealthProfileField.HEIGHT to value), emptyList(), link.stamp)

    @Test fun selectionAndGrantsRoundTripWithoutCopyingProfileValues() {
        assertEquals(issue, HealthCareConcern.from(issue.json()))
        assertEquals(grant, HealthCareDiscussionGrant.from(grant.json()))
        val expectedLink = JSONObject("""{"scope":{"generation":"","fields":["HEIGHT"],"entries":[]},"stamp":{"generation":"","versions":{"field:HEIGHT":"v1"}}}""")
        val serialized = issue.copy(id = "17000000-0000-4000-8000-000000000001").json()
        assertTrue(expectedLink.similar(serialized.getJSONObject("profile_link")))
        assertTrue(expectedLink.similar(grant.json().getJSONObject("profile_link")))
        assertEquals(issue.copy(profileLink = null), HealthCareConcern.from(issue.copy(profileLink = null).json()))
    }
    @Test fun identityEmptyScopeInvalidIdsAndOversizedSelectionsAreRejected() {
        assertThrows(IllegalArgumentException::class.java) { scope.copy(fields = setOf(HealthProfileField.NAME)) }
        assertThrows(IllegalArgumentException::class.java) { scope.copy(fields = emptySet()) }
        assertThrows(IllegalArgumentException::class.java) { scope.copy(entries = setOf("invalid")) }
        assertThrows(IllegalArgumentException::class.java) { scope.copy(entries = (0..30).map { id() }.toSet()) }
        assertThrows(IllegalArgumentException::class.java) { link.copy(stamp = HealthProfileStamp("", emptyMap())) }
    }
    @Test fun unselectedFieldsCannotBeSmuggledIntoTheHandoff() {
        assertThrows(IllegalArgumentException::class.java) {
            HealthCareProfilePolicy.snapshot(link, context().copy(fields = context().fields +
                (HealthProfileField.NAME to HealthProfileInput("secret"))), now)
        }
        assertThrows(IllegalArgumentException::class.java) { HealthCareDiscussionPolicy.snapshot(issue) }
    }
    @Test fun savedFieldsAreIncludedAndUnknownRemainsUnknown() {
        val result = JSONObject(HealthCareDiscussionPolicy.snapshot(issue, profile = context()))
        assertTrue(result.getJSONObject("clarification_context").getBoolean("separate_profile_included"))
        val profile = result.getJSONObject("selected_profile")
        assertEquals("170", profile.getJSONObject("fields").getJSONObject("HEIGHT").getJSONObject("value").getString("text"))
        assertFalse(profile.getBoolean("complete_medical_history"))
        val missing = HealthCareProfilePolicy.snapshot(link, context(null), now).getJSONObject("fields").getJSONObject("HEIGHT")
        assertEquals("UNKNOWN", missing.getString("state")); assertTrue(missing.isNull("value"))
    }
    @Test fun birthDateBecomesMeasurementAgeWithoutExportingTheBirthDate() {
        val scope = HealthCareProfileScope("", setOf(HealthProfileField.BIRTH_DATE), emptySet())
        val link = HealthCareProfileLink(scope, HealthProfileStamp("", mapOf("field:BIRTH_DATE" to "v1")))
        val context = HealthProfileContext(mapOf(HealthProfileField.BIRTH_DATE to HealthProfileInput("2000-11-09")), emptyList(), link.stamp)
        val result = HealthCareProfilePolicy.snapshot(link, context, now)
        assertEquals(25, result.getJSONObject("fields").getJSONObject("AGE_AT_MEASUREMENT").getInt("age_on_measurement_date"))
        assertFalse(result.toString().contains("2000-11-09"))
    }
    @Test fun removedEntryIsExplicitRatherThanANegativeMedicalHistory() {
        val id = id(); val scope = scope.copy(entries = setOf(id))
        val link = HealthCareProfileLink(scope, link.stamp.copy(versions = link.stamp.versions + ("entry:$id" to "deleted-v2")))
        val result = HealthCareProfilePolicy.snapshot(link, context().copy(stamp = link.stamp), now)
        assertEquals(id, result.getJSONArray("unavailable_selected_entries").getString(0))
        assertFalse(result.getBoolean("unselected_means_absent"))
    }
    @Test fun selectedSourceUpdateChangesResearchAndActionBasisButNotAnUnchangedRead() {
        val refreshed = HealthCareProfilePolicy.refreshed(issue, link.stamp.copy(versions = mapOf("field:HEIGHT" to "v2")))
        assertEquals(HealthCareStage.REASSESS, refreshed.stage)
        assertNotEquals(HealthCareFollowUpPolicy.basis(issue), HealthCareFollowUpPolicy.basis(refreshed))
        assertNotEquals(HealthCareResearchPolicy.trigger(issue, now), HealthCareResearchPolicy.trigger(refreshed, now))
        assertEquals(issue, HealthCareProfilePolicy.refreshed(issue, link.stamp))
        assertEquals(HealthCareStage.PAUSED, HealthCareProfilePolicy.refreshed(issue.copy(stage = HealthCareStage.PAUSED), refreshed.profileLink!!.stamp).stage)
    }
    @Test fun standingConsentAllowsUpdatesButNeverAChangedSelectionOrArchiveGeneration() {
        val consent = HealthCareResearchAuthorization(id(), grant, "b".repeat(64))
        val next = grant.copy(researchAuthorizationId = consent.id, revision = 2,
            profileLink = link.copy(stamp = link.stamp.copy(versions = mapOf("field:HEIGHT" to "v2"))))
        assertTrue(consent.permits(next))
        assertFalse(consent.permits(next.copy(profileLink = null)))
        assertFalse(consent.copy(scope = grant.copy(profileLink = null)).permits(next))
        val scope = scope.copy(generation = id())
        assertFalse(consent.permits(next.copy(profileLink = HealthCareProfileLink(scope, link.stamp.copy(generation = scope.generation)))))
    }
    @Test fun oldGrantCannotAuthorizeNewProfileEvenWithMatchingConcernRevision() {
        val privacy = HealthPrivacyPolicy(version = "privacy")
        val settings = HealthCareSettings(true, "settings")
        assertTrue(HealthCareDiscussionPolicy.permitted(grant, grant.conversationId, grant.turnId, issue, settings, privacy, grant.destination, now))
        assertFalse(HealthCareDiscussionPolicy.permitted(grant, grant.conversationId, grant.turnId, issue.copy(profileLink = null),
            settings, privacy, grant.destination, now))
    }
}
