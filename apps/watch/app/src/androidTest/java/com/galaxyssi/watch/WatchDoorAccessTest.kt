package com.galaxyssi.watch

import com.galaxyssi.chat.DoorAccessClient
import com.galaxyssi.chat.DoorAccessConfiguration
import com.galaxyssi.chat.DoorAccessTransport
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException

/** No real credentials, door services or opening requests are used by these tests. */
class WatchDoorAccessTest {
    private val configuration = requireNotNull(DoorAccessConfiguration.fromJson("""{
      "version":1,"default_door":"home","list_commands":["小区门禁","门禁列表","打开门禁"],
      "default_open_commands":["开门","开门开门"],"doors":[
        {"id":"home","service_name":"Test Unit","display_name":"单元门","commands":["单元门","打开单元门"]},
        {"id":"south","service_name":"Test South","display_name":"南门","commands":["南门","打开南门"]},
        {"id":"north","service_name":"Test North","display_name":"北门","commands":["北门","打开北门"]},
        {"id":"side","service_name":"Test Side","display_name":"侧门","commands":["侧门","打开侧门"]}
      ]} """))
    private val credentials = "test-owner" to "test-password"
    private fun plan(prompt: String) = WatchDoorAccess.plan(configuration, prompt, credentials) as WatchDoorAccess.Plan.Open

    private class FakeTransport(val names: List<String> = listOf("Test Unit", "Test South", "Test North", "Test Side"),
        val reject: Boolean = false, val timeout: Boolean = false) : DoorAccessTransport {
        val requests = mutableListOf<Pair<String, Map<String, String>?>>()
        override fun request(url: String, form: Map<String, String>?): JSONObject {
            requests += url to form
            return when {
                url.endsWith("/House/Login") -> JSONObject("""{"State":true,"Data":{"Token":"fake","House":{"ID":"test"}}}""")
                url.endsWith("/GetSubSystems") -> JSONObject("""{"State":true,"Data":[{"SubSystem":1,"SubSystemHost":"https://rke.taichuan.net"}]}""")
                url.contains("/SearchEquipment") -> JSONObject().put("State", true).put("Data", JSONArray().also { array ->
                    names.forEachIndexed { index, name -> array.put(JSONObject().put("EQ_Name", name).put("EQ_Num", "channel-$index")) }
                })
                url.endsWith("/Publisher/Publish") -> {
                    if (timeout) throw IOException("Fake timeout after submission")
                    JSONObject().put("State", !reject)
                }
                else -> error("Unexpected test request")
            }
        }
        fun opens() = requests.filter { it.first.endsWith("/Publisher/Publish") }
    }

    @Test fun explicitCommandsUseAndroidDirectExecutionAndOnlyTheirConfiguredChannel() {
        mapOf("开门" to 0, "开门开门" to 0, "单元门" to 0, "打开单元门" to 0,
            "南门" to 1, "打开南门" to 1, "打開南門。" to 1,
            "北门" to 2, "打开北门" to 2, "侧门" to 3, "打开侧门" to 3).forEach { (prompt, channel) ->
            val fake = FakeTransport()
            val outcome = WatchDoorAccess.execute(plan(prompt), DoorAccessClient(fake))
            assertEquals(prompt, TaskState.COMPLETED, outcome.state)
            assertEquals("sent", outcome.message)
            assertEquals(4, fake.requests.size)
            assertEquals("channel-$channel", fake.opens().single().second?.get("channel"))
        }
    }

    @Test fun listsAndFirstLoginOpenPanelButQuestionsAndUninstalledSkillsDoNotExecute() {
        listOf("小区门禁", "门禁列表", "打开门禁").forEach {
            assertTrue(WatchDoorAccess.plan(configuration, it, credentials) is WatchDoorAccess.Plan.Panel)
        }
        assertTrue(WatchDoorAccess.plan(configuration, "打开南门", null) is WatchDoorAccess.Plan.Panel)
        assertSame(WatchDoorAccess.Plan.Unmatched, WatchDoorAccess.plan(null, "打开南门", credentials))
        listOf("请分析如何打开南门", "不要打开南门", "南门在哪里", "打开西门", "Hello").forEach {
            assertSame(it, WatchDoorAccess.Plan.Unmatched, WatchDoorAccess.plan(configuration, it, credentials))
        }
    }

    @Test fun missingOrAmbiguousDoorsNeverSendAnOpeningRequest() {
        listOf(listOf("Test Unit"), listOf("Test South", "Test South")).forEach { doors ->
            val fake = FakeTransport(doors)
            val outcome = WatchDoorAccess.execute(plan("打开南门"), DoorAccessClient(fake))
            assertEquals(TaskState.FAILED, outcome.state)
            assertEquals("not_unique_tool", outcome.message)
            assertTrue(fake.opens().isEmpty())
        }
    }

    @Test fun unknownOrRejectedOpeningIsReportedWithoutRetryOrPanelFallback() {
        val unknown = FakeTransport(timeout = true)
        assertEquals("unconfirmed", WatchDoorAccess.execute(plan("打开南门"), DoorAccessClient(unknown)).message)
        assertEquals(1, unknown.opens().size)
        val rejected = FakeTransport(reject = true)
        assertEquals("rejected_tool", WatchDoorAccess.execute(plan("打开南门"), DoorAccessClient(rejected)).message)
        assertEquals(1, rejected.opens().size)
    }

    @Test fun stopBeforePublishPreventsOpening() {
        val fake = FakeTransport()
        var checks = 0
        assertTrue(runCatching { WatchDoorAccess.execute(plan("打开南门"), DoorAccessClient(fake)) {
            if (++checks >= 3) throw IOException("Cancelled")
        } }.isFailure)
        assertTrue(fake.opens().isEmpty())
    }
}
