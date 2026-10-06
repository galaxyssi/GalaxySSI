package com.galaxyssi.chat

import org.json.JSONObject

/** Wire identifiers shared by phone collaboration and the watch's read-only web loop. */
internal object CloudGoalPageProtocol {
    const val FORMAT = "galaxyssi.goal-contract-page.v1"
    const val RECALL_TOOL = "collaboration_recall"

    fun integer(value: JSONObject, key: String): Long? = when (val number = value.opt(key)) {
        is Int -> number.toLong()
        is Long -> number
        else -> null
    }
}
