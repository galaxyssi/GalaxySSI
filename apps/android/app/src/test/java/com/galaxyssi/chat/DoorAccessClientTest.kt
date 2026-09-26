package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class DoorAccessClientTest {
    private val manifestFile = File("src/testFixtures/door/manifest.json")
    private val configuration get() = requireNotNull(DoorAccessConfiguration.fromManifest(manifestFile.readText()))

    @Test fun doorDisplayAliasesPreserveServiceNamesAndChannels() {
        val aliases = mapOf(
            "Test South" to "南门(测试)",
            "Test Unit" to "Home",
            "Test North" to "北门(测试)",
            "Test Side" to "侧门(测试)",
            "Other Door" to "Other Door"
        )
        aliases.forEach { (original, alias) ->
            val door = DoorAccessDoor(original, "channel-$original", "Community")
            assertEquals(alias, configuration.displayName(door))
            assertEquals(original, door.name)
            assertEquals("channel-$original", door.channel)
        }
    }

    @Test fun configurationBindsDisplayAliasesToExactServiceNamesAndChannels() {
        val fake = openingTransport("""{"State":true}""")
        val result = DoorAccessClient(fake).openUnique("owner", "password", DoorAccessCommand.Open(null), 100L, configuration)
        assertEquals(DoorAccessOpenStatus.ACCEPTED, result.status)
        assertEquals("Test Unit", result.doorName)
        assertEquals("unit-3", fake.requests.last().second?.get("channel"))
        val north = DoorAccessDoor("Test North", "gate-2", "Community")
        assertEquals(north, configuration.select(DoorAccessCommand.Open("north"), listOf(north)))
    }

    private class FakeTransport(vararg replies: String) : DoorAccessTransport {
        val requests = mutableListOf<Pair<String, Map<String, String>?>>()
        private val responses = ArrayDeque(replies.toList())
        override fun request(url: String, form: Map<String, String>?): JSONObject {
            requests += url to form
            return JSONObject(responses.removeFirst())
        }
    }

    @Test fun loginAndListDoNotUnlock() {
        val fake = FakeTransport(
            """{"State":true,"Data":{"Token":"secret-token","House":{"ID":"user-1"}}}""",
            """{"State":true,"Data":[{"SubSystem":1,"SubSystemHost":"http://rke.taichuan.net"}]}""",
            """{"State":true,"Data":[{"EQ_Name":"Lobby","EQ_Num":"door-1","EQ_CommunityName":"Home"},{"EQ_Name":"Invalid","EQ_Num":""}]}"""
        )
        val client = DoorAccessClient(fake)
        val session = client.login("owner", "password")
        val doors = client.listDoors(session)
        assertEquals("https://rke.taichuan.net", session.serviceUrl)
        assertEquals(1, doors.size)
        assertEquals("door-1", doors.single().channel)
        assertEquals(3, fake.requests.size)
        assertFalse(fake.requests.any { it.first.endsWith("/MobileApi/Publisher/Publish") })
        assertTrue(fake.requests.all { it.first.startsWith("https://") })
    }

    @Test fun unlockFormatsOriginalProtocolOnlyOnExplicitCall() {
        val fake = FakeTransport("""{"State":true}""")
        val session = DoorAccessSession("token", "house-7", "https://rke.taichuan.net")
        assertTrue(DoorAccessClient(fake).unlock(session, DoorAccessDoor("Lobby", "channel-9", "Home"), 123456L))
        val (url, form) = fake.requests.single()
        assertEquals("https://haina.taichuan.net/MobileApi/Publisher/Publish", url)
        assertEquals("channel-9", form?.get("channel"))
        assertEquals("token", form?.get("token"))
        val message = JSONObject(form!!.getValue("message"))
        assertEquals(1, message.getInt("messageSenderType"))
        assertEquals("house-7", message.getString("formuid"))
        assertEquals("tc_20150330_unlock123456", message.getString("msg"))
    }

    @Test fun discoveryRejectsUntrustedHosts() {
        listOf("http://evil.example", "http://rke.taichuan.net.evil.example", "http://user@rke.taichuan.net")
            .forEach { value ->
                assertTrue(runCatching { DoorAccessClient.secureServiceUrl(value) }.isFailure)
            }
    }

    @Test fun distributedSkillManifestMatchesRegisteredTool() {
        val raw = manifestFile.readText()
        val manifest = requireNotNull(AgentSkillManifestCodec.decode(raw))
        val runtime = AgentSkillRuntime(availableNativeToolIds = AgentPhoneNativeToolCatalog.defaultToolIds)
        assertTrue(runtime.validate(manifest).issues.toString(), runtime.validate(manifest).isValid)
        assertFalse(manifest.steps.any { it.toolId.contains("unlock") })
        assertEquals("1.3.0", manifest.version)
        assertEquals("{{parameters.request}}", manifest.steps.single().input["request"])
        assertEquals(DoorAccessCommand.ListDoors, DoorAccessNativeTool.configuration(manifest)?.parse("打开门禁"))
    }

    @Test fun exactChineseCommandsDoNotMatchQuestionsOrLongerInstructions() {
        listOf("开门。", "开门 开门", "開門開門", "开门，开门", "開門，開門", "open the door", "Open The Door!")
            .forEach { assertEquals(it, DoorAccessCommand.Open(null), configuration.parse(it)) }
        listOf("单元门", "打开单元门", "單元門", "打開單元門")
            .forEach { assertEquals(it, DoorAccessCommand.Open("home"), configuration.parse(it)) }
        listOf("南门", "打开南门", "学校门", "打开学校门", "打開學校門", "打開南門")
            .forEach { assertEquals(it, DoorAccessCommand.Open("south"), configuration.parse(it)) }
        listOf("北门", "打开北门", "华润门", "打开华润门", "打開華潤門", "北門")
            .forEach { assertEquals(it, DoorAccessCommand.Open("north"), configuration.parse(it)) }
        listOf("侧门", "打开侧门", "市场门", "打开市场门", "打開市場門", "側門")
            .forEach { assertEquals(it, DoorAccessCommand.Open("side"), configuration.parse(it)) }
        listOf("小区门禁", "小區門禁", "門禁", "门禁列表", "打开门禁", "打开门禁列表", "打開門禁列表")
            .forEach { assertEquals(it, DoorAccessCommand.ListDoors, configuration.parse(it)) }
        listOf("开门是什么意思", "请分析如何打开南门", "打开微信", "不开门", "不要打开学校门", "先不要开门")
            .forEach { assertNull(it, configuration.parse(it)) }
    }

    @Test fun autoOpenRequiresExactlyOneMatchingDoor() {
        val unit = DoorAccessDoor("Test Unit", "unit-3", "Test Community")
        val south = DoorAccessDoor("Test South", "south", "Test Community")
        val north = DoorAccessDoor("Test North", "north", "Test Community")
        assertEquals(unit, configuration.select(DoorAccessCommand.Open(null), listOf(unit, south, north)))
        assertEquals(south, configuration.select(DoorAccessCommand.Open("south"), listOf(unit, south, north)))
        assertEquals(unit, configuration.select(DoorAccessCommand.Open("home"), listOf(unit, south)))
        assertNull(configuration.select(DoorAccessCommand.Open(null), listOf(unit, unit.copy(channel = "other"))))
        assertNull(configuration.select(DoorAccessCommand.Open("south"), listOf(south, south.copy(channel = "other"))))
        assertNull(configuration.select(DoorAccessCommand.Open("west"), listOf(unit, south)))
        assertNull(configuration.select(DoorAccessCommand.Open(null), listOf(unit.copy(name = "其他楼3单元"))))
    }

    @Test fun directUnlockAuthorizationIsScopedAndSingleUse() {
        DoorAccessNativeTool.authorize("conversation-a", "turn-1", "打开南门", configuration)
        assertFalse(DoorAccessNativeTool.consumeAuthorization("conversation-b", "turn-1", "打开南门"))
        assertFalse(DoorAccessNativeTool.consumeAuthorization("conversation-a", "turn-1", "开门"))
        DoorAccessNativeTool.authorize("conversation-a", "turn-2", "打开南门", configuration)
        assertTrue(DoorAccessNativeTool.consumeAuthorization("conversation-a", "turn-2", "打开南门"))
        assertFalse(DoorAccessNativeTool.consumeAuthorization("conversation-a", "turn-2", "打开南门"))
    }

    @Test fun doorPhrasesBuildUniqueLocalNativeActions() {
        val first = requireNotNull(DoorAccessNativeTool.actionFor("开门", "turn-1", configuration))
        val second = requireNotNull(DoorAccessNativeTool.actionFor("open the door", "turn-2", configuration))
        assertEquals(AgentActionKind.CALL_NATIVE_TOOL, first.kind)
        assertEquals(DoorAccessNativeTool.ID, first.parameters["tool_id"])
        assertEquals("开门", JSONObject(first.parameters.getValue("input_json")).getString("request"))
        assertFalse(first.id == second.id)
        assertNull(DoorAccessNativeTool.actionFor("门禁系统怎么设计", "turn-3", configuration))
    }

    @Test fun directOpeningLogsInSelectsThreeUnitAndSendsOnce() {
        val fake = openingTransport("""{"State":true}""")
        val result = DoorAccessClient(fake).openUnique("owner", "password", DoorAccessCommand.Open(null), 100L, configuration)
        assertEquals(DoorAccessOpenStatus.ACCEPTED, result.status)
        assertEquals("Test Unit", result.doorName)
        assertEquals(4, fake.requests.size)
        assertEquals("unit-3", fake.requests.last().second?.get("channel"))
    }

    @Test fun directOpeningSelectsSouthDoorAndNeverRetriesUnknownResult() {
        val fake = openingTransport("invalid-json")
        val result = DoorAccessClient(fake).openUnique("owner", "password", DoorAccessCommand.Open("south"), 100L, configuration)
        assertEquals(DoorAccessOpenStatus.UNCONFIRMED, result.status)
        assertEquals(4, fake.requests.size)
        assertEquals("south", fake.requests.last().second?.get("channel"))
    }

    @Test fun missingTargetNeverSendsUnlock() {
        val fake = openingTransport("""{"State":true}""")
        val result = DoorAccessClient(fake).openUnique("owner", "password", DoorAccessCommand.Open("west"), 100L, configuration)
        assertEquals(DoorAccessOpenStatus.NO_UNIQUE_MATCH, result.status)
        assertEquals(3, fake.requests.size)
    }

    @Test fun cancellationCheckpointStopsBeforeUnlock() {
        val fake = openingTransport("""{"State":true}""")
        var checkpoints = 0
        val outcome = runCatching {
            DoorAccessClient(fake).openUnique("owner", "password", DoorAccessCommand.Open(null), 100L, configuration) {
                if (++checkpoints == 3) error("cancelled")
            }
        }
        assertTrue(outcome.isFailure)
        assertEquals(3, fake.requests.size)
    }

    @Test fun allRequestedOpenAliasesSendOnlyTheConfiguredChannel() {
        val expected = mapOf(
            "开门" to "unit-3", "开门开门" to "unit-3", "单元门" to "unit-3", "打开单元门" to "unit-3",
            "南门" to "south", "打开南门" to "south", "学校门" to "south", "打开学校门" to "south",
            "北门" to "north", "打开北门" to "north", "华润门" to "north", "打开华润门" to "north",
            "侧门" to "side", "打开侧门" to "side", "市场门" to "side", "打开市场门" to "side"
        )
        expected.forEach { (phrase, channel) ->
            val fake = openingTransport("""{"State":true}""")
            val command = configuration.parse(phrase) as DoorAccessCommand.Open
            assertEquals(DoorAccessOpenStatus.ACCEPTED,
                DoorAccessClient(fake).openUnique("owner", "password", command, 100L, configuration).status)
            assertEquals(phrase, channel, fake.requests.last().second?.get("channel"))
            assertEquals(1, fake.requests.count { it.first.endsWith("/Publisher/Publish") })
        }
    }

    @Test fun configurationUpdatesCommandsDefaultDoorAndDisplayWithoutCodeChanges() {
        val updatedManifest = JSONObject(manifestFile.readText())
        val rules = updatedManifest.getJSONArray("steps").getJSONObject(0).getJSONObject("input").getJSONObject("door_config")
        rules.put("default_door", "north")
        rules.getJSONArray("default_open_commands").put("回家开门")
        rules.getJSONArray("doors").getJSONObject(2).put("display_name", "新北门")
        val updated = requireNotNull(DoorAccessConfiguration.fromManifest(updatedManifest.toString()))
        assertNull(configuration.parse("回家开门"))
        assertEquals(DoorAccessCommand.Open(null), updated.parse("回家开门"))
        val door = DoorAccessDoor("Test North", "north-channel", "Community")
        assertEquals(door, updated.select(DoorAccessCommand.Open(null), listOf(door)))
        assertEquals("新北门", updated.displayName(door))
        val manifest = requireNotNull(AgentSkillManifestCodec.decode(updatedManifest.toString()))
        val roundTrip = requireNotNull(AgentSkillManifestCodec.decode(AgentSkillManifestCodec.encode(manifest)))
        assertEquals(DoorAccessCommand.Open(null), DoorAccessNativeTool.configuration(roundTrip)?.parse("回家开门"))
    }

    @Test fun conflictingAliasesAndInvalidTargetsFailClosed() {
        val conflict = JSONObject(configuration.json)
        conflict.getJSONArray("list_commands").put("开门")
        assertNull(DoorAccessConfiguration.fromJson(conflict.toString()))
        val missingDefault = JSONObject(configuration.json).put("default_door", "unknown")
        assertNull(DoorAccessConfiguration.fromJson(missingDefault.toString()))
        val duplicateDoor = JSONObject(configuration.json)
        duplicateDoor.getJSONArray("doors").getJSONObject(1).put("service_name", "Test Unit")
        assertNull(DoorAccessConfiguration.fromJson(duplicateDoor.toString()))
        val malformed = requireNotNull(AgentSkillManifestCodec.decode(manifestFile.readText()))
            .copy(steps = listOf(AgentSkillStep("open", DoorAccessNativeTool.ID, mapOf("door_config" to mapOf("version" to 99)))))
        assertNull(DoorAccessNativeTool.configuration(malformed))
    }

    @Test fun standalonePackageSuppliesRulesWithoutBundledAssets() {
        val manifest = requireNotNull(AgentSkillManifestCodec.decode(manifestFile.readText()))
        val inspected = DoorAccessSkillPackage.inspect(AgentSkillPackageExporter.export(manifest))
        assertEquals("1.3.0", inspected.version)
        assertEquals(DoorAccessCommand.ListDoors, inspected.configuration.parse("打开门禁"))
        assertEquals(DoorAccessCommand.Open("north"), inspected.configuration.parse("打开华润门"))
        val legacy = manifest.copy(steps = manifest.steps.map { it.copy(input = it.input - "door_config") })
        assertNull(DoorAccessNativeTool.configuration(legacy))
        assertTrue(runCatching { DoorAccessSkillPackage.inspect(AgentSkillPackageExporter.export(legacy)) }.isFailure)
    }

    @Test fun watchPackageRejectsTamperedOrExecutableContent() {
        fun archive(entries: Map<String, String>): ByteArray = ByteArrayOutputStream().use { output ->
            ZipOutputStream(output).use { zip ->
                entries.forEach { (name, value) ->
                    zip.putNextEntry(ZipEntry(name))
                    zip.write(value.toByteArray())
                    zip.closeEntry()
                }
            }
            output.toByteArray()
        }
        assertTrue(runCatching { DoorAccessSkillPackage.inspect(archive(mapOf(
            "manifest.json" to manifestFile.readText(), "integrity.json" to """{"manifest_sha256":"invalid"}"""
        ))) }.isFailure)
        assertTrue(runCatching { DoorAccessSkillPackage.inspect(archive(mapOf("run.py" to "print('unsafe')"))) }.isFailure)
    }

    private fun openingTransport(unlockReply: String) = FakeTransport(
        """{"State":true,"Data":{"Token":"test-token","House":{"ID":"test-user"}}}""",
        """{"State":true,"Data":[{"SubSystem":1,"SubSystemHost":"http://rke.taichuan.net"}]}""",
        """{"State":true,"Data":[{"EQ_Name":"Test Unit","EQ_Num":"unit-3"},{"EQ_Name":"Test South","EQ_Num":"south"},{"EQ_Name":"Test North","EQ_Num":"north"},{"EQ_Name":"Test Side","EQ_Num":"side"}]}""",
        unlockReply
    )
}
