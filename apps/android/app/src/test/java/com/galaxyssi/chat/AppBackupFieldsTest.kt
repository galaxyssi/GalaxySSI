package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AppBackupFieldsTest {
    @Test fun optionalAppSectionsFollowExportOptions() {
        val full = AppBackupFields.expected(true, true)
        assertEquals(setOf("app-field" to "contacts", "app-field" to "friend_requests", "app-field" to "messages"),
            full - AppBackupFields.expected(false, false))
        assertEquals(full - ("app-field" to "messages"), AppBackupFields.expected(true, false))
        assertEquals(full - setOf("app-field" to "contacts", "app-field" to "friend_requests"), AppBackupFields.expected(false, true))
    }

    @Test fun memoryCannotBeHiddenInsideALegacyField() {
        for (key in listOf("memory", "memory_deletion_index", "agent_data"))
            assertNotNull(runCatching { AppBackupFields.validate("agent-field", key, JSONArray()) }.exceptionOrNull())
    }

    @Test fun fieldTypesAndSchemaAreValidatedRatherThanIgnored() {
        AppBackupFields.validate("agent-field", "version", 33)
        AppBackupFields.validate("app-field", "profile", JSONObject())
        AppBackupFields.validate("app-field", "contacts", JSONArray())
        AppBackupFields.validate("agent-field", "interface_language", "zh")
        for (value in listOf(32, 33.5, "33", JSONObject.NULL))
            assertNotNull(runCatching { AppBackupFields.validate("agent-field", "version", value) }.exceptionOrNull())
        assertNotNull(runCatching { AppBackupFields.validate("app-field", "contacts", JSONObject()) }.exceptionOrNull())
    }

    @Test fun jsonRecordsRejectTrailingGarbageArraysAndInvalidUtf8() {
        assertEquals(1, readBackupJson("{\"v\":1} \n".byteInputStream()).getInt("v"))
        for (text in listOf("{}{}", "{} trailing", "[]", "null"))
            assertNotNull(runCatching { readBackupJson(text.byteInputStream()) }.exceptionOrNull())
        assertNotNull(runCatching { readBackupJson(byteArrayOf(123, 34, 0xc3.toByte(), 34, 58, 49, 125).inputStream()) }.exceptionOrNull())
    }
}
