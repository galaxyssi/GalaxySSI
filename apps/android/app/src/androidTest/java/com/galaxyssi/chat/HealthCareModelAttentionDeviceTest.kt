package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import androidx.test.platform.app.InstrumentationRegistry
import java.time.ZoneOffset
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareModelAttentionDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(block: (HealthCareAttentionFixture) -> Unit) = HealthCareAttentionFixture(context).use(block)
    private fun deliver(f: HealthCareAttentionFixture, settings: HealthReminderSettings = f.settings,
        at: Long = System.currentTimeMillis(), allowed: Boolean = true, visible: Map<String, Boolean> = emptyMap(),
        valid: (HealthCareModelAttention) -> Boolean = { f.care.modelAttentionCurrent(it, at) },
        post: (HealthCareModelAttention) -> Boolean = { true }, cancel: (String) -> Unit = {},
        foreground: (HealthCareModelAttention) -> Boolean = { false }) =
        HealthCareModelAttentionDelivery.reconcile(f.care, settings, at, ZoneOffset.UTC, allowed, visible, valid, post, cancel, foreground)

    @Test fun assessmentAloneCannotNotifyAndCompletionPersistsOneEncryptedReceipt() = fixture { f ->
        f.record(); assertNull(f.care.modelAttention(f.issue.id)); f.complete()
        val notice = f.notice
        assertEquals(HealthCareAttentionState.WAITING, notice.state)
        HealthCareStore(context, f.names.care).use { assertEquals(notice, it.modelAttention(f.issue.id)) }
        context.openOrCreateDatabase(f.names.care, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM model_attention", null).use {
                assertTrue(it.moveToFirst()); assertFalse(it.getBlob(0).toString(Charsets.UTF_8).contains(notice.conversationId))
            }
        }
        var posts = 0
        deliver(f, post = { posts++; true }); deliver(f, post = { posts++; true })
        assertEquals(1, posts); assertEquals(HealthCareAttentionState.POSTED, f.notice.state)
        f.care.updateResearchJob(f.job, HealthCareResearchState.COMPLETED)
        assertEquals(HealthCareAttentionState.POSTED, f.notice.state)
    }
    @Test fun noAttentionAndProseOnlyResultsNeverCreateNotifications() = fixture { f ->
        f.record(false); f.complete(); assertNull(f.care.modelAttention(f.issue.id))
        f.measurement("6.4"); f.prepare(); f.complete()
        assertEquals(HealthCareResearchState.FAILED, f.job.state); assertNull(f.care.modelAttention(f.issue.id))
    }
    @Test fun postedNoticeSurvivesReopenWithoutReplayAfterSystemDismissal() = fixture { f ->
        f.record(); f.complete(); deliver(f)
        HealthCareStore(context, f.names.care).use { reopened ->
            assertTrue(reopened.pendingModelAttention().isEmpty()); assertEquals(HealthCareAttentionState.POSTED, reopened.modelAttention(f.issue.id)!!.state)
        }
        deliver(f, post = { fail("A dismissed notice must not be replayed"); false })
    }
    @Test fun processDeathAfterPostingReconcilesTheVisibleStableNotification() = fixture { f ->
        f.record(); f.complete()
        deliver(f, visible = mapOf(f.issue.id to true), post = { fail("The visible notification must not ring twice"); false })
        assertEquals(HealthCareAttentionState.POSTED, f.notice.state)
    }
    @Test fun sourceChangesCancelOldNoticeWithoutDeletingModelHistory() = fixture { f ->
        val review = f.record(); f.complete(); deliver(f)
        f.measurement("6.5")
        val cancelled = mutableListOf<String>()
        deliver(f, visible = mapOf(f.issue.id to true), cancel = { cancelled.add(it) })
        assertEquals(listOf(f.issue.id), cancelled); assertEquals(review, f.care.modelReview(review.grant.turnId))
        f.prepare(); f.record(false); f.complete()
        assertEquals(HealthCareAttentionState.STALE, f.notice.state)
    }
    @Test fun revokedAuthorizationStopsQueuedAndLatePostDelivery() = fixture { f ->
        f.record(); f.complete()
        val cancelled = mutableListOf<String>()
        deliver(f, post = { f.care.revokeResearch(f.issue.id, f.authorization.id, System.currentTimeMillis()); true }, cancel = { cancelled.add(it) })
        assertEquals(listOf(f.issue.id), cancelled); assertEquals(HealthCareAttentionState.STALE, f.notice.state)
    }
    @Test fun foregroundConsumptionIsScopedAndDoesNotChangeTheHealthConcern() = fixture { f ->
        f.record(); f.complete(); val issue = f.care.concern(f.issue.id)
        deliver(f, foreground = { it.conversationId == f.issue.conversationId }, post = { fail("No foreground notification"); false })
        assertEquals(HealthCareAttentionState.IN_APP_ONLY, f.notice.state); assertEquals(issue, f.care.concern(f.issue.id))
        assertTrue(f.care.reminders(f.issue.id).isEmpty())
    }
    @Test fun disabledDeliveryDoesNotRetroactivelyBlastOldReviewsWhenReenabled() = fixture { f ->
        f.record(); f.complete(); deliver(f, settings = f.settings.copy(modelReviews = false))
        assertEquals(HealthCareAttentionState.IN_APP_ONLY, f.notice.state)
        deliver(f, post = { fail("A disabled update must not be replayed"); false })
    }
    @Test fun osPermissionDenialKeepsTheAssessmentAvailableInApp() = fixture { f ->
        val review = f.record(); f.complete(); deliver(f, allowed = false)
        assertEquals(HealthCareAttentionState.IN_APP_ONLY, f.notice.state); assertEquals(review, f.care.modelReview(f.job.turnId))
    }
    @Test fun pauseAndQuietWindowDeferRatherThanConsumeThePendingReview() = fixture { f ->
        f.record(); f.complete(); val at = System.currentTimeMillis(); val end = at + 3_600_000
        assertEquals(end, deliver(f, settings = f.settings.copy(pauseUntil = end), at = at, post = { fail("Paused"); false }))
        assertEquals(HealthCareAttentionState.WAITING, f.notice.state)
        val date = java.time.Instant.ofEpochMilli(end).atZone(ZoneOffset.UTC)
        val minute = date.hour * 60 + date.minute
        val quiet = f.settings.copy(quiet = true, quietStart = (minute + 1430) % 1440, quietEnd = (minute + 20) % 1440)
        assertEquals(HealthReminderPolicy.quietUntil(quiet, end, ZoneOffset.UTC), deliver(f, quiet, end, post = { fail("Quiet window"); false }))
        assertEquals(HealthCareAttentionState.WAITING, f.notice.state)
    }
    @Test fun failedOsPostBacksOffAndRetriesTheSameReceipt() = fixture { f ->
        f.record(); f.complete(); val notice = f.notice; val at = System.currentTimeMillis()
        assertEquals(at + 60_000, deliver(f, at = at, post = { false })); assertEquals(notice, f.notice)
        assertNull(deliver(f, at = at + 60_000)); assertEquals(HealthCareAttentionState.POSTED, f.notice.state)
    }
    @Test fun staleCompareAndSetCannotAcknowledgeANewerAssessment() = fixture { f ->
        f.record(); f.complete(); val previous = f.notice
        f.measurement("6.4"); f.prepare(); f.record(); f.complete()
        assertNotEquals(previous.turnId, f.notice.turnId)
        assertFalse(f.care.finishModelAttention(previous, HealthCareAttentionState.POSTED))
        assertEquals(HealthCareAttentionState.WAITING, f.notice.state)
    }
    @Test fun realRuntimeRechecksPrivacyAndTheModelBinding() = fixture { f ->
        f.record(); f.complete()
        HealthCareModelAttentionRuntime.reconcile(context, f.settings, System.currentTimeMillis(), ZoneOffset.UTC, true,
            emptyMap(), post = { fail("Revoked model binding"); false }, cancel = {}, names = f.names, binding = { false })
        assertEquals(HealthCareAttentionState.STALE, f.notice.state)
        f.measurement("6.4"); f.prepare(); f.record(); f.complete()
        HealthPrivacyStore(context, f.names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
        HealthCareModelAttentionRuntime.reconcile(context, f.settings, System.currentTimeMillis(), ZoneOffset.UTC, true,
            emptyMap(), post = { fail("Revoked health data permission"); false }, cancel = {}, names = f.names, binding = { true })
        assertEquals(HealthCareAttentionState.STALE, f.notice.state)
    }
    @Test fun tamperedNoticeIndexCannotRedirectTheConversation() = fixture { f ->
        f.record(); f.complete()
        context.openOrCreateDatabase(f.names.care, 0, null).use { db ->
            db.update("model_attention", ContentValues().apply { put("turn_id", UUID.randomUUID().toString()) }, "concern_id=?", arrayOf(f.issue.id))
        }
        assertThrows(IllegalStateException::class.java) { f.care.modelAttention(f.issue.id) }
    }
    @Test fun failedOutboxWriteRollsBackCompletionButPreservesAssessmentForRetry() = fixture { f ->
        val review = f.record()
        context.openOrCreateDatabase(f.names.care, 0, null).use { it.execSQL("CREATE TRIGGER ignore_attention BEFORE INSERT ON model_attention BEGIN SELECT RAISE(IGNORE); END") }
        f.job = f.care.updateResearchJob(f.job, HealthCareResearchState.DISPATCHED)
        assertThrows(IllegalStateException::class.java) { f.care.updateResearchJob(f.job, HealthCareResearchState.COMPLETED) }
        assertEquals(f.job, f.care.researchJob(f.job.turnId)); assertEquals(review, f.care.modelReview(f.job.turnId))
        context.openOrCreateDatabase(f.names.care, 0, null).use { it.execSQL("DROP TRIGGER ignore_attention") }
        f.care.updateResearchJob(f.job, HealthCareResearchState.COMPLETED)
        assertNotNull(f.notice)
    }
    @Test fun schema18MigrationPreservesExistingReviewsWithoutCreatingRetroactiveAlerts() = fixture { f ->
        val review = f.record(); f.complete(); f.care.close()
        context.openOrCreateDatabase(f.names.care, 0, null).use { it.execSQL("DROP TABLE model_attention"); it.version = 18 }
        HealthCareStore(context, f.names.care).use {
            assertEquals(review, it.modelReview(f.job.turnId)); assertEquals(f.job, it.researchJob(f.job.turnId)); assertNull(it.modelAttention(f.issue.id))
        }
        context.openOrCreateDatabase(f.names.care, 0, null).use { assertEquals(19, it.version) }
    }
    @Test fun noticeDeepLinksOnlyToTheBoundAgentWithoutEmbeddingHealthText() = fixture { f ->
        f.record(); f.complete(); val intent = HealthCareModelAttentionRuntime.openIntent(context, f.notice)
        assertEquals(f.issue.conversationId, intent.getStringExtra("galaxyssi_agent_conversation_id"))
        assertEquals(MainActivity::class.java.name, intent.component!!.className)
        assertFalse(intent.toUri(0).contains("6.3"))
        val notification = HealthReminderWork.notification(context, intent, 0, R.string.health_model_attention_notice, f.settings)
        assertEquals(Notification.VISIBILITY_PRIVATE, notification.visibility)
        assertFalse(notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString().contains("6.3"))
        assertNull(notification.publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT))
    }
    @Test fun largeOutboxUsesBoundedPagesAndNeverDropsRemainingUpdates() {
        SQLiteDatabase.create(null).use { db ->
            HealthCareModelAttentionRows.create(db)
            val rows = HealthCareModelAttentionRows(db, { _, _, json -> json.toString().toByteArray() }, { _, _, bytes -> org.json.JSONObject(String(bytes)) })
            repeat(65) { rows.write(HealthCareModelAttention(UUID.randomUUID().toString(), UUID.randomUUID().toString(), UUID.randomUUID().toString(), 1000L + it)) }
            val sizes = mutableListOf<Int>()
            while (true) {
                val page = rows.waiting(30); if (page.isEmpty()) break
                sizes.add(page.size); page.forEach { rows.write(it.copy(state = HealthCareAttentionState.POSTED)) }
            }
            assertEquals(listOf(30, 30, 5), sizes)
        }
    }
    @Test fun realSystemNotificationReceivesTheScopedGenericUpdateWithoutReplay() = fixture { f ->
        val manager = context.getSystemService(NotificationManager::class.java)
        org.junit.Assume.assumeTrue(manager.areNotificationsEnabled())
        val channel = "health-model-test-${UUID.randomUUID()}"
        val tag = "health-model-test:${f.issue.id}"
        try {
            manager.createNotificationChannel(NotificationChannel(channel, "Synthetic health delivery test", NotificationManager.IMPORTANCE_LOW))
            f.record(); f.complete()
            fun post(value: HealthCareModelAttention): Boolean {
                val original = HealthReminderWork.notification(context, HealthCareModelAttentionRuntime.openIntent(context, value),
                    0, R.string.health_model_attention_notice, f.settings)
                manager.notify(tag, 1, Notification.Builder.recoverBuilder(context, original).setChannelId(channel).build())
                return true
            }
            HealthCareModelAttentionRuntime.reconcile(context, f.settings, System.currentTimeMillis(), ZoneOffset.UTC, true,
                emptyMap(), ::post, { manager.cancel(tag, 1) }, names = f.names, binding = { true })
            assertEquals(HealthCareAttentionState.POSTED, f.notice.state)
            val deadline = android.os.SystemClock.elapsedRealtime() + 5000
            while (manager.activeNotifications.none { it.tag == tag } && android.os.SystemClock.elapsedRealtime() < deadline)
                android.os.SystemClock.sleep(50)
            val posted = manager.activeNotifications.single { it.tag == tag }.notification
            assertEquals(context.getString(R.string.health_model_attention_notice), posted.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
            manager.cancel(tag, 1)
            deliver(f, post = { fail("System dismissal must not resend the update"); false })
        } finally { manager.cancel(tag, 1); manager.deleteNotificationChannel(channel) }
    }
}
