package com.galaxyssi.chat

import android.app.Application
import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import androidx.test.runner.AndroidJUnitRunner
import java.io.File

/** Explicit runner for paid acceptance. Application, workers and recovery share isolated storage.
 * The live Signal ratchet is deliberately not copied or rolled back; only pairing is shared.
 */
open class HealthResearchAcceptanceRunner(private val prefix: String = "health-runtime-acceptance-") : AndroidJUnitRunner() {
    override fun newApplication(cl: ClassLoader, className: String, context: Context): Application =
        super.newApplication(cl, className, HealthResearchAcceptanceContext(context, prefix))
}

class HealthRelatedResearchAcceptanceRunner : HealthResearchAcceptanceRunner("health-related-acceptance-")
class HealthRevocationAcceptanceRunner : HealthResearchAcceptanceRunner("health-revocation-acceptance-")
open class HealthClarificationAcceptanceRunner(prefix: String = "health-clarification-acceptance-") : HealthResearchAcceptanceRunner(prefix)
class HealthClarificationReceiptAcceptanceRunner : HealthClarificationAcceptanceRunner("health-clarification-acceptance-receipts-")

private class HealthResearchAcceptanceContext(base: Context, private val prefix: String) : ContextWrapper(base) {
    override fun getDatabasePath(name: String): File {
        val leaf = File(name).name
        return baseContext.getDatabasePath(if (leaf == "${AndroidPersistentSignalStore.DATABASE}.db" ||
            leaf.startsWith(prefix)) leaf else prefix + leaf)
    }
    override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
        baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory)
    override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?,
        errorHandler: DatabaseErrorHandler?): SQLiteDatabase =
        baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory, errorHandler)
    override fun deleteDatabase(name: String): Boolean {
        val path = getDatabasePath(name)
        check(path.name.startsWith(prefix)) { "Acceptance cannot delete live pairing" }
        return SQLiteDatabase.deleteDatabase(path)
    }
    override fun getFilesDir(): File = File(baseContext.filesDir, prefix).apply { mkdirs() }
    override fun getCacheDir(): File = File(baseContext.cacheDir, prefix).apply { mkdirs() }
    override fun getNoBackupFilesDir(): File = File(baseContext.noBackupFilesDir, prefix).apply { mkdirs() }
    override fun getSharedPreferences(name: String, mode: Int) =
        baseContext.getSharedPreferences(if (name in PAIRING || name.startsWith(prefix)) name else prefix + name, mode)
    override fun createConfigurationContext(overrideConfiguration: Configuration): Context =
        HealthResearchAcceptanceContext(baseContext.createConfigurationContext(overrideConfiguration), prefix)

    companion object {
        private val PAIRING = setOf("galaxyssi_app_store", "galaxyssi_signal_trust", "opaque_link_v2", "galaxyssi_language")
    }
}
