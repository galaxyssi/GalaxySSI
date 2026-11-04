package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import java.io.File

internal enum class HealthExportShareKind(val path: String) { RECORDS("records"), ORIGINALS("originals") }

internal data class HealthExportShareItem(
    val kind: HealthExportShareKind, val id: String, val attempt: String, val createdAt: Long,
    val extension: String, val mime: String, val size: Long
) {
    val name get() = "GalaxySSI-${kind.path}-$createdAt.$extension"

    companion object {
        fun records(session: HealthRecordExportSession) = HealthExportShareItem(
            HealthExportShareKind.RECORDS, session.id, session.attempt, session.createdAt,
            session.scope.extension, session.scope.mime, session.artifactBytes)

        fun originals(session: HealthOriginalExportSession) = HealthExportShareItem(
            HealthExportShareKind.ORIGINALS, session.id, session.attempt, session.createdAt,
            "zip", "application/zip", session.archiveBytes)
    }
}

internal object HealthExportShare {
    fun authority(context: Context) = "${context.packageName}.health-exports"

    fun uri(context: Context, item: HealthExportShareItem, fixture: String? = null): Uri {
        require(HealthProfilePolicy.uuid(item.id) && HealthProfilePolicy.uuid(item.attempt))
        val builder = Uri.Builder().scheme("content").authority(authority(context))
        if (fixture != null) {
            require(BuildConfig.DEBUG && HealthProfilePolicy.uuid(fixture))
            builder.appendPath("fixture").appendPath(fixture)
        }
        return builder.appendPath(item.kind.path).appendPath(item.id).appendPath(item.attempt).build()
    }

    fun chooser(context: Context, item: HealthExportShareItem, fixture: String? = null): Intent {
        val uri = uri(context, item, fixture)
        val send = Intent(Intent.ACTION_SEND).setType(item.mime).putExtra(Intent.EXTRA_STREAM, uri).apply {
            clipData = ClipData.newRawUri(item.name, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return Intent.createChooser(send, null)
    }

    fun confirm(activity: Activity, item: HealthExportShareItem, fixture: String? = null): AlertDialog =
        AlertDialog.Builder(activity)
            .setTitle(R.string.health_export_share)
            .setMessage(R.string.health_export_share_unencrypted)
            .setNegativeButton(R.string.common_cancel, null)
            .setPositiveButton(R.string.health_export_share) { _, _ ->
                try { activity.startActivity(chooser(activity, item, fixture)) }
                catch (_: Exception) { Toast.makeText(activity, R.string.health_export_share_unavailable, Toast.LENGTH_LONG).show() }
            }.show()

    fun recordDatabase(fixture: String?) = fixture?.let { "health-record-export-test-$it.db" } ?: "health_record_exports_v1.db"
    fun openRecords(context: Context, fixture: String?) = if (fixture == null) HealthRecordExportStore(context) else
        HealthRecordExportStore(context, recordDatabase(fixture), File(context.cacheDir, "health-record-export-test-$fixture"))

    fun openOriginals(context: Context, fixture: String?) = if (fixture == null) HealthOriginalStore(context) else
        HealthOverviewDatabases(fixture).let { HealthOriginalStore(context, it.originals, it.originalRoot(context)) }

    fun originalLibrary(context: Context, originals: HealthOriginalStore, fixture: String?) =
        if (fixture == null) HealthOriginalLibraryStore(context, originals) else
            HealthOriginalLibraryStore(context, originals, File(context.cacheDir, "health-original-export-test-$fixture"))
}
