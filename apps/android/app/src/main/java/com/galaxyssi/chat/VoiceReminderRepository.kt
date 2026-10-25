package com.galaxyssi.chat

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import java.text.DateFormat
import java.util.Date

/** Read-only projection shared by the voice screen and every provider's reminders tool. */
internal class VoiceReminderRepository(context: Context) {
    private val app = context.applicationContext

    fun load(now: Long = System.currentTimeMillis()): VoiceReminderSnapshot {
        val items = mutableListOf<VoiceReminderItem>()
        val sources = linkedMapOf("weather" to "not_connected")
        fun source(name: String, read: () -> Unit) {
            sources[name] = try { read(); "available" } catch (_: Exception) { "unavailable" }
        }
        source("personal_and_news") {
            val (personal, unreadNews) = GlobalAgentRepository(app).voiceReminderPreview()
            items += personal.filter(VoiceReminderPolicy::personal).map {
                VoiceReminderItem(it.key, "personal", app.getString(R.string.voice_reminder_personal),
                    it.content.take(480), it.createdAtMillis,
                    conversationId = it.destinationConversationId.ifBlank { it.sourceConversationId }, state = "unread")
            }
            if (unreadNews > 0) items += VoiceReminderItem("news:unread", "news",
                app.getString(R.string.voice_reminder_news), app.getString(R.string.voice_reminder_news_summary, unreadNews),
                now, state = "unread")
        }
        source("tasks") {
            val transcripts = AgentTranscriptStore(app)
            items += EncryptedAgentWorkspaceStore(app).recoverable(24)
                .filter(VoiceReminderPolicy::taskNeedsAttention)
                .filter { transcripts.conversation(it.conversationId)?.status == AgentConversationStatus.ACTIVE }
                .take(2).map {
                    val label = app.getString(when (it.status) {
                        AgentWorkspaceStatus.PAUSED -> R.string.voice_reminder_task_paused
                        AgentWorkspaceStatus.BLOCKED -> R.string.voice_reminder_task_blocked
                        else -> R.string.voice_reminder_task_confirmation
                    })
                    VoiceReminderItem("task:${it.workspaceId}", "task", app.getString(R.string.voice_reminder_task),
                        "$label\n${it.goal.take(180)}".trim(), it.updatedAtMillis, it.workspaceId,
                        it.conversationId, it.status.name.lowercase())
                }
        }
        if (app.checkSelfPermission(Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
            sources["calendar"] = "permission_not_granted"
        } else source("calendar") { items += calendar(now) }
        return VoiceReminderSnapshot(VoiceReminderPolicy.select(items), sources)
    }

    private fun calendar(now: Long): List<VoiceReminderItem> {
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(uri, now)
        ContentUris.appendId(uri, now + 24 * 60 * 60 * 1000L)
        return app.contentResolver.query(uri.build(), arrayOf(CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE, CalendarContract.Instances.BEGIN),
            "${CalendarContract.Instances.VISIBLE} = 1 AND ${CalendarContract.Instances.BEGIN} >= ? AND " +
                "${CalendarContract.Instances.STATUS} != ? AND ${CalendarContract.Instances.SELF_ATTENDEE_STATUS} != ?",
            arrayOf(now.toString(), CalendarContract.Events.STATUS_CANCELED.toString(),
                CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED.toString()), CalendarContract.Instances.BEGIN + " ASC")?.use { cursor ->
            buildList {
                while (size < 2 && cursor.moveToNext()) {
                    val id = cursor.getLong(0).toString()
                    val at = cursor.getLong(2)
                    val title = cursor.getString(1).orEmpty().trim().take(180)
                    if (title.isNotBlank()) add(VoiceReminderItem("calendar:$id:$at", "calendar",
                        app.getString(R.string.voice_reminder_calendar),
                        DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(at)) + "\n" + title,
                        at, id, state = "upcoming"))
                }
            }
        } ?: error("calendar_query_unavailable")
    }
}
