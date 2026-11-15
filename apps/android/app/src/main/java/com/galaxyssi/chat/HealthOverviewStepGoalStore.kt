package com.galaxyssi.chat

import android.content.Context
import android.util.Base64
import java.nio.ByteBuffer

internal class HealthOverviewStepGoalStore(context: Context, names: HealthOverviewDatabases) {
    private val prefs = context.getSharedPreferences(names.prefs, Context.MODE_PRIVATE)
    private val aad = "${names.prefs}|step_goal|v1".toByteArray(Charsets.UTF_8)

    fun load(): Int? {
        val encoded = prefs.getString(KEY, null) ?: return null
        val plain = AgentStorageCipher.decryptBinary(Base64.decode(encoded, Base64.NO_WRAP), aad)
        return try {
            check(plain.size == Int.SIZE_BYTES)
            ByteBuffer.wrap(plain).int.also { check(it in 1..HealthOverviewGuidance.MAX_STEP_GOAL) }
        } finally { plain.fill(0) }
    }

    fun save(goal: Int?) {
        val editor = prefs.edit()
        if (goal == null) editor.remove(KEY) else {
            require(goal in 1..HealthOverviewGuidance.MAX_STEP_GOAL)
            val plain = ByteBuffer.allocate(Int.SIZE_BYTES).putInt(goal).array()
            val encrypted = try { AgentStorageCipher.encryptBinary(plain, aad) } finally { plain.fill(0) }
            editor.putString(KEY, Base64.encodeToString(encrypted, Base64.NO_WRAP))
        }
        check(editor.commit()) { "Step goal could not be persisted" }
    }

    private companion object {
        const val KEY = "step_goal"
    }
}
