package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class AgentQemuRuntimeEngineTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `qemu memory policy uses device memory instead of the dalvik heap class`() {
        assertEquals(
            1_536,
            AgentQemuMemoryPolicy.resolve(
                totalRamBytes = 10_857_076L * 1024L,
                availableRamBytes = 4_271_440L * 1024L,
                profileMaximumMegabytes = 1_536
            )
        )
        assertEquals(
            512,
            AgentQemuMemoryPolicy.resolve(
                totalRamBytes = 3L * 1024L * 1024L * 1024L,
                availableRamBytes = 700L * 1024L * 1024L,
                profileMaximumMegabytes = 512
            )
        )
    }

    @Test
    fun `launch plan keeps credentials off the command line and exposes isolated guest networking`() {
        val root = temporaryFolder.newFolder("runtime plan")
        val spec = AgentRuntimeEngineLaunchSpec(
            engineFile = File(root, "libsignalasi_qemu.so"),
            baseImageFile = File(root, "linux-base.img"),
            socketFile = File(root, "guest.sock"),
            packsDirectory = File(root, "packs"),
            workspacesDirectory = File(root, "workspaces"),
            architecture = "arm64-v8a",
            packAttachments = listOf(
                AgentRuntimePackAttachment(
                    "python-uv",
                    "1.0.0",
                    setOf("python.execute", "uv.sync"),
                    File(root, "python.img")
                ),
                AgentRuntimePackAttachment(
                    "ffmpeg",
                    "1.0.0",
                    setOf("ffmpeg.execute", "ffprobe.inspect"),
                    File(root, "ffmpeg.img")
                )
            ),
            sessionKey = ByteArray(32) { 0x5a }
        )
        val sessionFile = File(root, "guest-session.key")
        val configFile = File(root, "guest-config.json")
        val plan = AgentQemuLaunchPlanBuilder.build(
            spec = spec,
            sessionFile = sessionFile,
            configFile = configFile,
            logFile = File(root, "qemu.log"),
            memoryMegabytes = 512,
            cpuCount = 6
        )

        val command = plan.command.joinToString(" ")
        assertTrue(command.contains("-smp 6"))
        assertTrue(command.contains("user,id=signalasi_net,restrict=off,ipv6=off"))
        assertFalse(command.contains("dns="))
        assertTrue(command.contains("virtio-net-device,netdev=signalasi_net"))
        assertTrue(command.contains("server=on,wait=on"))
        assertFalse(command.contains("server=on,wait=off"))
        assertTrue(command.contains("readonly=on"))
        assertTrue(command.contains("mount_tag=signalasi_workspaces"))
        assertTrue(command.contains("id=signalasi_system"))
        assertTrue(command.contains("serial=${AgentRuntimePersistentDisk.SERIAL}"))
        assertTrue(command.contains("name=opt/com.signalasi/runtime-session,file=${sessionFile.absolutePath}"))
        assertFalse(command.contains("Wlpa"))
        assertFalse(command.contains("5a5a5a"))
        assertTrue(command.indexOf("ffmpeg.img") < command.indexOf("python.img"))
        assertEquals("C", plan.environment["LC_ALL"])
        assertEquals(spec.engineFile.parentFile?.absolutePath, plan.environment["LD_LIBRARY_PATH"])
        assertFalse(plan.environment.containsKey("PATH"))
        val guestConfig = AgentQemuRuntimeConfigBuilder.build(
            spec,
            userNetworkBackendAvailable = true,
            dnsServers = listOf("1.1.1.1", "223.5.5.5"),
            workspaceUid = 10_427
        )
        assertEquals("full_access", guestConfig.getString("execution_mode"))
        assertEquals("root", guestConfig.getString("execution_principal"))
        assertEquals(
            listOf("1.1.1.1", "223.5.5.5"),
            List(guestConfig.getJSONArray("dns_servers").length()) { index ->
                guestConfig.getJSONArray("dns_servers").getString(index)
            }
        )
        assertEquals(
            AgentRuntimePersistentDisk.LOGICAL_BYTES,
            guestConfig.getJSONObject("system_disk").getLong("logical_bytes")
        )
    }

    @Test
    fun `pack serials are stable and bounded`() {
        assertEquals("sa-python-uv", AgentQemuLaunchPlanBuilder.packSerial("python-uv"))
        assertTrue(AgentQemuLaunchPlanBuilder.packSerial("a".repeat(80)).length <= 20)
    }

    @Test
    fun `launch plan keeps local runtime available when user networking is absent`() {
        val root = temporaryFolder.newFolder("offline runtime")
        val plan = AgentQemuLaunchPlanBuilder.build(
            spec = AgentRuntimeEngineLaunchSpec(
                engineFile = File(root, "libsignalasi_qemu.so"),
                baseImageFile = File(root, "linux-base.img"),
                socketFile = File(root, "guest.sock"),
                packsDirectory = File(root, "packs"),
                workspacesDirectory = File(root, "workspaces"),
                architecture = "arm64-v8a",
                sessionKey = ByteArray(32)
            ),
            sessionFile = File(root, "guest-session.key"),
            configFile = File(root, "guest-config.json"),
            logFile = File(root, "qemu.log"),
            memoryMegabytes = 512,
            cpuCount = 2,
            userNetworkBackendAvailable = false
        )

        val command = plan.command.joinToString(" ")
        assertTrue(command.contains("-nic none"))
        assertFalse(command.contains("signalasi_net"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `launch plan rejects qemu key value delimiter in paths`() {
        val root = File("build/runtime,unsafe")
        AgentQemuLaunchPlanBuilder.build(
            spec = AgentRuntimeEngineLaunchSpec(
                engineFile = File(root, "engine"),
                baseImageFile = File(root, "base"),
                socketFile = File(root, "socket"),
                packsDirectory = File(root, "packs"),
                workspacesDirectory = File(root, "workspaces"),
                architecture = "arm64-v8a",
                sessionKey = ByteArray(32)
            ),
            sessionFile = File(root, "session"),
            configFile = File(root, "config"),
            logFile = File(root, "log"),
            memoryMegabytes = 512,
            cpuCount = 2
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun `guest config rejects a non IPv4 DNS server`() {
        val root = temporaryFolder.newFolder("invalid dns")
        AgentQemuRuntimeConfigBuilder.build(
            spec = AgentRuntimeEngineLaunchSpec(
                engineFile = File(root, "engine"),
                baseImageFile = File(root, "base"),
                socketFile = File(root, "socket"),
                packsDirectory = File(root, "packs"),
                workspacesDirectory = File(root, "workspaces"),
                architecture = "arm64-v8a",
                sessionKey = ByteArray(32)
            ),
            userNetworkBackendAvailable = true,
            dnsServers = listOf("resolver.invalid"),
            workspaceUid = 10_427
        )
    }
}
