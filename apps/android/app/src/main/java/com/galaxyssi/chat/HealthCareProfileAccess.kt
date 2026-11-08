package com.galaxyssi.chat

import android.content.Context

internal object HealthCareProfileAccess {
    fun stamp(context: Context, scope: HealthCareProfileScope, names: HealthOverviewDatabases = HealthOverviewDatabases()): HealthProfileStamp =
        HealthProfileStore(context, names.profile, names.privacy).use {
            it.dependencyStamp(scope.fields, scope.entries).also { stamp ->
                if (stamp.generation != scope.generation) throw HealthProfileConflict()
            }
        }

    fun current(context: Context, link: HealthCareProfileLink?, names: HealthOverviewDatabases = HealthOverviewDatabases()): Boolean =
        link == null || runCatching { stamp(context, link.scope, names) == link.stamp }.getOrDefault(false)

    fun capture(context: Context, link: HealthCareProfileLink, names: HealthOverviewDatabases = HealthOverviewDatabases()): HealthProfileContext =
        HealthProfileStore(context, names.profile, names.privacy).use {
            it.capture(link.scope.fields, link.scope.entries, allowMissingEntries = true).also { value ->
                if (value.stamp != link.stamp) throw HealthProfileConflict()
            }
        }
}
