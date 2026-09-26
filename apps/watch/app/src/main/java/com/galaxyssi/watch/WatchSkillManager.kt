package com.galaxyssi.watch

import android.content.Context
import com.galaxyssi.chat.DoorAccessConfiguration
import com.galaxyssi.chat.DoorAccessConfigurationStore
import com.galaxyssi.chat.DoorAccessCredentialStore
import com.galaxyssi.chat.DoorAccessSkillPackage

/** Installed packages only; bundled executors are not installed Skills. */
internal class WatchSkillManager(context: Context) {
    private val configuration = DoorAccessConfigurationStore(context)
    private val preferences = context.getSharedPreferences("door_access_skill_v1", Context.MODE_PRIVATE)
    private val credentials = DoorAccessCredentialStore(context)

    fun installed(): Boolean = preferences.getBoolean("installed", false) && configuration.load() != null
    fun enabled(): Boolean = installed() && preferences.getBoolean("enabled", true)
    fun activeConfiguration(): DoorAccessConfiguration? = if (enabled()) configuration.load() else null

    fun install(skill: DoorAccessSkillPackage) {
        configuration.save(skill.configuration)
        check(preferences.edit().putBoolean("installed", true).putBoolean("enabled", true).commit())
    }

    fun setEnabled(value: Boolean) {
        check(installed())
        check(preferences.edit().putBoolean("enabled", value).commit())
    }

    fun uninstall() {
        // Stop routing before clearing configuration and local credentials.
        check(preferences.edit().putBoolean("installed", false).putBoolean("enabled", false).commit())
        configuration.clear()
        credentials.clear()
    }
}
