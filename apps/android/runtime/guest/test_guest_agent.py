import hashlib
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import galaxyssi_guest_agent as guest


class GuestProtocolTest(unittest.TestCase):
    def envelope(self):
        return {
            "protocol_version": 1,
            "message_id": "message-1",
            "request_id": "request-1",
            "type": "execute",
            "sequence": 2,
            "timestamp_millis": 1_700_000_000_000,
            "payload": {
                "arguments": ["alpha"],
                "language": "python",
                "limits": {"wall_clock_ms": 1000},
                "workspace_path": "/workspace/a/b",
            },
            "mac": "",
        }

    def test_canonical_payload_contract(self):
        digest = hashlib.sha256(guest.unsigned_payload(self.envelope())).hexdigest()
        self.assertEqual(
            "abfc19846ceaf0b2d26a67314e51dc04c333131ae8a146bec2b29f1960f7b639",
            digest,
        )
        self.assertEqual(
            "bQOnaC5JTWzoMgk+2beIwM/kTTghus6R73k6P1hopg8=",
            guest.sign_envelope(self.envelope(), bytes(range(32)))["mac"],
        )

    def test_sign_verify_and_tamper_detection(self):
        key = bytes(range(32))
        signed = guest.sign_envelope(self.envelope(), key)
        self.assertTrue(guest.verify_envelope(signed, key, now_millis=1_700_000_000_000))
        signed["payload"]["language"] = "shell"
        self.assertFalse(guest.verify_envelope(signed, key, now_millis=1_700_000_000_000))

    def test_unicode_canonicalization_and_float_rejection(self):
        self.assertEqual(
            '{"emoji":"\U0001F600","slash":"a/b","text":"\u4e2d\u6587\\n\\"x\\""}',
            guest.canonical_json(
                {"text": '\u4e2d\u6587\n"x"', "slash": "a/b", "emoji": "\U0001F600"}
            ),
        )
        with self.assertRaises(ValueError):
            guest.canonical_json({"value": 1.5})

    def test_frame_round_trip(self):
        stream = io.BytesIO()
        envelope = guest.sign_envelope(self.envelope(), bytes(range(32)))
        guest.write_frame(stream, envelope)
        stream.seek(0)
        self.assertEqual(envelope, guest.read_frame(stream))

    def test_resource_limits_reject_invalid_wall_clock(self):
        with self.assertRaises(ValueError):
            guest.ExecutionLimits.from_payload({"limits": {"wall_clock_ms": 99}})

    def test_launcher_plan_applies_identity_and_resource_limits(self):
        limits = guest.ExecutionLimits.from_payload({"limits": {}})
        with mock.patch.object(guest, "LAUNCHER_PATH", Path(sys.executable)):
            plan = guest.launcher_plan(
                {"workspace_uid": 10123, "workspace_gid": 10123},
                Path("/workspace/a/request"),
                limits,
                ["/usr/bin/python3", "/work/main.py"],
            )

        self.assertEqual(sys.executable, plan[0])
        self.assertEqual("10123", plan[plan.index("--uid") + 1])
        self.assertEqual("10123", plan[plan.index("--gid") + 1])
        self.assertEqual(
            ["/usr/bin/python3", "/work/main.py"],
            plan[plan.index("--") + 1 :],
        )
        self.assertEqual("isolated", plan[plan.index("--network-mode") + 1])

    def test_launcher_plan_allows_only_the_authenticated_proxy_network_mode(self):
        limits = guest.ExecutionLimits.from_payload({"limits": {}})
        with mock.patch.object(guest, "LAUNCHER_PATH", Path(sys.executable)):
            plan = guest.launcher_plan(
                {"workspace_uid": 10123, "workspace_gid": 10123},
                Path("/workspace/a/request"),
                limits,
                ["/usr/bin/python3", "/work/main.py"],
                allow_network_proxy=True,
            )
        self.assertEqual("proxy", plan[plan.index("--network-mode") + 1])

    def test_full_access_execution_plan_runs_every_command_inside_persistent_userspace(self):
        command = ["/usr/bin/python3", "/workspace/project/main.py"]
        plan = guest.execution_plan(
            {"execution_mode": "full_access", "execution_principal": "root"},
            Path("/workspace/project"),
            guest.ExecutionLimits.from_payload({"limits": {}}),
            command,
        )

        self.assertEqual(
            [
                "chroot",
                str(guest.PERSISTENT_USERSPACE_ROOT),
                "/bin/sh",
                "-c",
                'cd "$1" && shift && exec "$@"',
                "galaxyssi",
                str(Path("/workspace/project")),
                *command,
            ],
            plan,
        )
        self.assertTrue(guest.full_access_enabled({
            "execution_mode": "full_access",
            "execution_principal": "root",
        }))

    def test_full_access_pack_binary_uses_the_same_persistent_userspace_as_shell(self):
        command = ["/opt/galaxyssi/packs/node-js/bin/node", "--version"]

        plan = guest.execution_plan(
            {"execution_mode": "full_access", "execution_principal": "root"},
            Path("/workspace/project"),
            guest.ExecutionLimits.from_payload({"limits": {}}),
            command,
        )

        self.assertEqual("chroot", plan[0])
        self.assertEqual(str(guest.PERSISTENT_USERSPACE_ROOT), plan[1])
        self.assertEqual(command, plan[-len(command):])

    def test_command_plan_resolves_executables_from_mounted_pack_path(self):
        with tempfile.TemporaryDirectory() as directory:
            pack_root = Path(directory) / "python-uv"
            pack_bin = pack_root / "bin"
            pack_bin.mkdir(parents=True)
            uv = pack_bin / "uv"
            uv.touch(mode=0o755)
            uv.chmod(0o755)
            with mock.patch.object(guest, "PACK_ROOT", Path(directory)):
                environment = guest.runtime_environment()
                plan = guest.command_plan("uv", Path("/work"), [], environment["PATH"])

        self.assertEqual(str(uv), plan[0][0])
        self.assertEqual(
            [
                "run",
                "--no-cache",
                "--offline",
                str(Path("/work") / guest.RUNTIME_CONTROL_DIRECTORY / "main.py"),
            ],
            plan[0][1:],
        )

    def test_command_plan_exposes_ffprobe_as_a_separate_read_only_operation(self):
        with tempfile.TemporaryDirectory() as directory:
            pack_bin = Path(directory) / "ffmpeg" / "bin"
            pack_bin.mkdir(parents=True)
            ffprobe = pack_bin / "ffprobe"
            ffprobe.touch(mode=0o755)
            ffprobe.chmod(0o755)
            with mock.patch.object(guest, "PACK_ROOT", Path(directory)):
                environment = guest.runtime_environment()
                plan = guest.command_plan(
                    "ffprobe",
                    Path("/work"),
                    ["-show_format", "input.mp4"],
                    environment["PATH"],
                )

        self.assertEqual(
            [[str(ffprobe), "-show_format", "input.mp4"]],
            plan,
        )

    def test_command_plan_executes_browser_source_with_the_installed_launcher(self):
        with tempfile.TemporaryDirectory() as directory:
            pack_bin = Path(directory) / "browser-automation" / "bin"
            pack_bin.mkdir(parents=True)
            launcher = pack_bin / "galaxyssi-browser"
            launcher.touch(mode=0o755)
            launcher.chmod(0o755)
            with mock.patch.object(guest, "PACK_ROOT", Path(directory)):
                environment = guest.runtime_environment()
                plan = guest.command_plan(
                    "browser",
                    Path("/work"),
                    ["--trace"],
                    environment["PATH"],
                )

        self.assertEqual(
            [[
                str(launcher),
                str(Path("/work") / guest.RUNTIME_CONTROL_DIRECTORY / "main.browser.js"),
                "--trace",
            ]],
            plan,
        )

    def test_all_source_drivers_execute_from_the_hidden_control_directory(self):
        workspace = Path("/work")
        control = workspace / guest.RUNTIME_CONTROL_DIRECTORY
        source_names = {
            "shell": "main.sh",
            "python": "main.py",
            "uv": "main.py",
            "javascript": "main.js",
            "typescript": "main.ts",
            "go": "main.go",
            "rust": "main.rs",
            "c": "main.c",
            "cpp": "main.cpp",
            "java": "Main.java",
            "browser": "main.browser.js",
        }
        with mock.patch.object(
            guest,
            "executable",
            side_effect=lambda name, search_path=None: f"/bin/{name}",
        ):
            plans = {
                language: guest.command_plan(language, workspace, [])
                for language in source_names
            }

        for language, source_name in source_names.items():
            flattened = [item for command in plans[language] for item in command]
            self.assertIn(str(control / source_name), flattened)
            self.assertNotIn(str(workspace / source_name), flattened)

    def test_runtime_environment_keeps_mutable_language_caches_in_private_task_temp(self):
        environment = guest.runtime_environment()
        task_temp = guest.ISOLATED_WORKSPACE_ROOT / ".tmp"
        self.assertEqual("true", environment["CARGO_NET_OFFLINE"])
        self.assertEqual("1", environment["UV_NO_CACHE"])
        self.assertEqual(str(task_temp / "uv-cache"), environment["UV_CACHE_DIR"])
        self.assertEqual(str(task_temp / "cargo"), environment["CARGO_HOME"])
        self.assertEqual(
            str(task_temp / "zig-global-cache"),
            environment["ZIG_GLOBAL_CACHE_DIR"],
        )
        self.assertEqual(str(guest.PACK_ROOT / "java"), environment["JAVA_HOME"])
        self.assertEqual(str(guest.PACK_ROOT / "gradle"), environment["GRADLE_HOME"])
        self.assertEqual(
            str(guest.PACK_ROOT / "python-uv" / "bin" / "python3"),
            environment["UV_PYTHON"],
        )
        self.assertEqual(str(task_temp / "gradle"), environment["GRADLE_USER_HOME"])
        self.assertEqual(str(guest.PACK_ROOT / "android-sdk" / "sdk"), environment["ANDROID_HOME"])
        self.assertEqual(environment["ANDROID_HOME"], environment["ANDROID_SDK_ROOT"])
        self.assertIn("org.gradle.project.android.aapt2FromMavenOverride", environment["GRADLE_OPTS"])

    def test_full_access_runtime_environment_allows_dependency_downloads(self):
        workspace = Path("/workspace/project")
        environment = guest.runtime_environment(workspace, full_access=True)

        self.assertEqual(str(Path("/root")), environment["HOME"])
        self.assertEqual(str(Path("/root") / ".cache" / "tmp"), environment["TMPDIR"])
        self.assertEqual("noninteractive", environment["DEBIAN_FRONTEND"])
        self.assertEqual("none", environment["APT_LISTCHANGES_FRONTEND"])
        self.assertEqual("automatic", environment["UV_PYTHON_DOWNLOADS"])
        self.assertEqual("false", environment["CARGO_NET_OFFLINE"])
        self.assertNotIn("UV_OFFLINE", environment)
        self.assertNotIn("UV_NO_CACHE", environment)
        self.assertNotIn("PYTHONNOUSERSITE", environment)

    def test_full_access_runtime_creates_persistent_cache_and_temp_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            task_temp = Path(directory) / ".cache" / "tmp"
            guest.prepare_runtime_temp_directories({"TMPDIR": str(task_temp)}, full_access=True)

            self.assertTrue(task_temp.parent.is_dir())
            self.assertTrue(task_temp.is_dir())

    def test_repository_fingerprint_uses_the_guest_execution_boundary(self):
        fingerprint = "a" * 64
        limits = guest.ExecutionLimits.from_payload({"limits": {}})
        with mock.patch.object(guest, "execution_plan", return_value=["fingerprint"]) as plan:
            with mock.patch.object(
                guest.subprocess,
                "run",
                return_value=guest.subprocess.CompletedProcess(
                    args=["fingerprint"],
                    returncode=0,
                    stdout=(fingerprint + "\n").encode("ascii"),
                ),
            ):
                result, checked = guest.capture_repository_fingerprint(
                    {},
                    Path("/workspace/project"),
                    {"PATH": "/usr/bin"},
                    limits,
                )

        self.assertEqual(fingerprint, result)
        self.assertTrue(checked)
        command = plan.call_args.args[3]
        self.assertEqual(["/bin/sh", "-c"], command[:2])
        self.assertIn("git status --porcelain=v2", command[2])
        self.assertIn("git diff --no-ext-diff --binary", command[2])

    def test_repository_fingerprint_distinguishes_no_repository_from_capture_failure(self):
        limits = guest.ExecutionLimits.from_payload({"limits": {}})
        with mock.patch.object(guest, "execution_plan", return_value=["fingerprint"]):
            with mock.patch.object(
                guest.subprocess,
                "run",
                return_value=guest.subprocess.CompletedProcess(
                    args=["fingerprint"], returncode=0, stdout=b""
                ),
            ):
                self.assertEqual(
                    ("", True),
                    guest.capture_repository_fingerprint({}, Path("/workspace/plain"), {}, limits),
                )
            with mock.patch.object(
                guest.subprocess,
                "run",
                return_value=guest.subprocess.CompletedProcess(
                    args=["fingerprint"], returncode=127, stdout=b""
                ),
            ):
                self.assertEqual(
                    ("", False),
                    guest.capture_repository_fingerprint({}, Path("/workspace/broken"), {}, limits),
                )

    def test_isolated_runtime_does_not_create_host_temp_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            task_temp = Path(directory) / ".cache" / "tmp"
            guest.prepare_runtime_temp_directories({"TMPDIR": str(task_temp)}, full_access=False)

            self.assertFalse(task_temp.parent.exists())

    def test_persistent_home_is_shared_by_guest_and_runtime_packs(self):
        commands = []

        def run(command, **kwargs):
            commands.append(command)
            return guest.subprocess.CompletedProcess(command, 0, "", "")

        with (
            mock.patch.object(guest.os.path, "ismount", return_value=False),
            mock.patch.object(guest.shutil, "copyfile"),
            mock.patch.object(guest.Path, "mkdir"),
            mock.patch.object(guest.subprocess, "run", side_effect=run),
        ):
            guest.bind_persistent_userspace()

        self.assertIn(
            ["mount", "--rbind", str(guest.PERSISTENT_SYSTEM_ROOT / "root"), str(Path("/root"))],
            commands,
        )
        self.assertIn(
            ["mount", "--rbind", str(Path("/root")), str(guest.PERSISTENT_USERSPACE_ROOT / "root")],
            commands,
        )

    def test_persistent_system_disk_is_formatted_and_mounted_once(self):
        config = {
            "system_disk": {
                "serial": "sa-system",
                "filesystem": "ext4",
                "mount_path": str(guest.PERSISTENT_SYSTEM_ROOT),
                "logical_bytes": 30 * 1024 * 1024 * 1024,
            }
        }
        device = Path("/dev/vda")
        commands = []

        def run(command, **kwargs):
            commands.append(command)
            if command[0] == "blkid":
                return guest.subprocess.CompletedProcess(command, 2, "", "")
            return guest.subprocess.CompletedProcess(command, 0, "", "")

        with (
            mock.patch.object(guest, "wait_for_block_device", return_value=device),
            mock.patch.object(guest.os.path, "ismount", return_value=False),
            mock.patch.object(guest.Path, "mkdir"),
            mock.patch.object(guest.Path, "chmod"),
            mock.patch.object(guest.subprocess, "run", side_effect=run),
        ):
            guest.mount_persistent_system(config)

        self.assertTrue(any(command[0] == "mke2fs" for command in commands))
        self.assertTrue(any(command[0] == "e2fsck" for command in commands))
        self.assertTrue(any(command[:3] == ["mount", "-t", "ext4"] for command in commands))

    def test_shell_execution_enters_persistent_userspace(self):
        plan = guest.execution_plan(
            {"execution_mode": "full_access", "execution_principal": "root"},
            Path("/workspace/project"),
            guest.ExecutionLimits.from_payload({"limits": {"wall_clock_ms": 1_000, "cpu_ms": 750}}),
            ["/bin/bash", "main.sh"],
        )

        self.assertEqual("chroot", plan[0])
        self.assertEqual(str(guest.PERSISTENT_USERSPACE_ROOT), plan[1])
        self.assertIn(str(Path("/workspace/project")), plan)
        self.assertEqual(["/bin/bash", "main.sh"], plan[-2:])

    def test_persistent_userspace_receives_shared_runtime_libraries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            host = root / "host-libs"
            userspace = root / "userspace"
            host.mkdir()
            for name in guest.PERSISTENT_RUNTIME_LIBRARY_NAMES:
                (host / name).write_bytes(f"runtime:{name}".encode())
            with (
                mock.patch.object(guest, "HOST_RUNTIME_LIBRARY_DIRECTORIES", (host,)),
                mock.patch.object(guest, "PERSISTENT_USERSPACE_ROOT", userspace),
            ):
                guest.install_persistent_runtime_libraries()
                guest.install_persistent_runtime_libraries()

            for name in guest.PERSISTENT_RUNTIME_LIBRARY_NAMES:
                self.assertEqual(
                    f"runtime:{name}".encode(),
                    (userspace / "usr" / "lib" / name).read_bytes(),
                )

    def test_persistent_userspace_exposes_host_development_tools_through_wrappers(self):
        with tempfile.TemporaryDirectory() as directory:
            userspace = Path(directory) / "userspace"
            host = Path(directory) / "host"
            host_bin = host / "usr" / "bin"
            host_git_core = host / "usr" / "libexec" / "git-core"
            host_bin.mkdir(parents=True)
            host_git_core.mkdir(parents=True)
            for name in guest.PERSISTENT_HOST_TOOL_NAMES:
                executable = host_bin / name
                executable.write_bytes(b"\x7fELF")
                executable.chmod(0o755)
            helper = host_git_core / "git-remote-https"
            helper.write_bytes(b"\x7fELF")
            helper.chmod(0o755)

            def which(name, path=None):
                self.assertIn(name, guest.PERSISTENT_HOST_TOOL_NAMES)
                return str(host_bin / name)

            def run(command, **kwargs):
                self.assertEqual(["git", "--exec-path"], command)
                return guest.subprocess.CompletedProcess(command, 0, f"{host_git_core}\n", "")

            with (
                mock.patch.object(guest, "PERSISTENT_USERSPACE_ROOT", userspace),
                mock.patch.object(guest.shutil, "which", side_effect=which),
                mock.patch.object(guest.subprocess, "run", side_effect=run),
            ):
                guest.install_persistent_host_tool_wrappers()

            for name in guest.PERSISTENT_HOST_TOOL_NAMES:
                wrapper = (userspace / "usr" / "local" / "bin" / name).read_text()
                self.assertIn("/run/galaxyssi-host/", wrapper)
                self.assertIn("ld-linux-aarch64.so.1", wrapper)
                self.assertIn('"$@"', wrapper)
                self.assertTrue(os.access(userspace / "usr" / "local" / "bin" / name, os.X_OK))
            git_wrapper = (userspace / "usr" / "local" / "bin" / "git").read_text()
            self.assertIn("GIT_EXEC_PATH=/usr/local/libexec/galaxyssi-git-core", git_wrapper)
            self.assertIn("GIT_SSL_CAINFO=/run/galaxyssi-host/etc/ssl/certs/ca-certificates.crt", git_wrapper)
            helper_wrapper = userspace / "usr" / "local" / "libexec" / "galaxyssi-git-core" / helper.name
            self.assertTrue(os.access(helper_wrapper, os.X_OK))
            self.assertIn("ld-linux-aarch64.so.1", helper_wrapper.read_text())

    def test_non_shell_runtime_pack_execution_enters_persistent_userspace(self):
        command = ["/opt/galaxyssi/packs/python-uv/bin/python3", "main.py"]
        plan = guest.execution_plan(
            {"execution_mode": "full_access", "execution_principal": "root"},
            Path("/workspace/project"),
            guest.ExecutionLimits.from_payload({"limits": {"wall_clock_ms": 1_000, "cpu_ms": 750}}),
            command,
        )

        self.assertEqual("chroot", plan[0])
        self.assertEqual(str(guest.PERSISTENT_USERSPACE_ROOT), plan[1])
        self.assertEqual(command, plan[-len(command):])

    def test_secret_environment_is_memory_only_and_strictly_bounded(self):
        environment = {"PATH": "/usr/bin"}
        guest.inject_secret_environment(environment, {"ACCESS_TOKEN": "secret-value"})

        self.assertEqual("secret-value", environment["ACCESS_TOKEN"])
        with self.assertRaises(ValueError):
            guest.inject_secret_environment(environment, {"invalid-name": "value"})
        with self.assertRaises(ValueError):
            guest.inject_secret_environment(environment, {"TOKEN": "x" * 4097})

    def test_guest_clock_bootstraps_from_trusted_host_epoch(self):
        host_epoch_millis = 1_784_385_257_000
        with (
            mock.patch.object(guest.time, "time", side_effect=[10.0, host_epoch_millis / 1000]),
            mock.patch.object(guest.time, "CLOCK_REALTIME", 0, create=True),
            mock.patch.object(guest.time, "clock_settime", create=True) as set_clock,
        ):
            guest.synchronize_guest_clock({"host_epoch_millis": host_epoch_millis})

        set_clock.assert_called_once_with(0, host_epoch_millis / 1000)

    def test_guest_clock_rejects_untrusted_host_epoch(self):
        with self.assertRaises(ValueError):
            guest.synchronize_guest_clock({"host_epoch_millis": 0})

    def test_runtime_readiness_requires_launcher_and_workspace_identity(self):
        with mock.patch.object(guest, "LAUNCHER_PATH", Path(sys.executable)):
            self.assertEqual(
                (True, ""),
                guest.runtime_readiness({"workspace_uid": 10123, "workspace_gid": 10123}),
            )
            ready, reason = guest.runtime_readiness({"workspace_uid": 0, "workspace_gid": 10123})
        self.assertFalse(ready)
        self.assertIn("workspace_uid", reason)

    def test_full_access_runtime_is_ready_without_the_restricted_launcher(self):
        with mock.patch.object(guest, "LAUNCHER_PATH", Path("/missing/launcher")):
            self.assertEqual(
                (True, ""),
                guest.runtime_readiness({
                    "execution_mode": "full_access",
                    "execution_principal": "root",
                }),
            )

    def test_guest_dns_uses_direct_public_resolvers(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "resolv.conf"
            guest.configure_guest_dns(
                {"dns_servers": ["1.1.1.1", "223.5.5.5", "1.1.1.1"]},
                target,
            )

            self.assertEqual(
                "nameserver 1.1.1.1\n"
                "nameserver 223.5.5.5\n"
                "options timeout:1 attempts:2 rotate\n",
                target.read_text(encoding="utf-8"),
            )

    def test_guest_dns_rejects_non_public_or_malformed_servers(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "resolv.conf"
            for server in ("192.168.3.1", "resolver.invalid"):
                with self.subTest(server=server), self.assertRaises(ValueError):
                    guest.configure_guest_dns({"dns_servers": [server]}, target)

    def test_task_network_firewall_blocks_direct_egress_for_the_sandbox_uid(self):
        completed = [
            mock.Mock(returncode=0, stdout="", stderr=""),
            mock.Mock(returncode=0, stdout="", stderr=""),
            mock.Mock(returncode=0, stdout="", stderr=""),
            mock.Mock(returncode=0, stdout="", stderr=""),
            mock.Mock(returncode=1, stdout="", stderr="rule missing"),
            mock.Mock(returncode=0, stdout="", stderr=""),
        ]
        with mock.patch.object(guest.subprocess, "run", side_effect=completed) as run:
            guest.install_task_network_firewall({"workspace_uid": 10123})

        commands = [call.args[0] for call in run.call_args_list]
        self.assertIn(
            ["iptables", "-w", "-A", "GALAXYSSI_TASK_OUT", "-j", "REJECT"],
            commands,
        )
        self.assertEqual("-I", commands[-1][2])
        self.assertIn("10123", commands[-1])

    def test_task_network_firewall_reports_the_failed_command_and_kernel_diagnostic(self):
        completed = [
            mock.Mock(returncode=0, stdout="", stderr=""),
            mock.Mock(returncode=3, stdout="", stderr="iptables: Table does not exist\n"),
        ]
        with (
            mock.patch.object(guest.subprocess, "run", side_effect=completed),
            self.assertRaisesRegex(
                RuntimeError,
                r"iptables -w -F GALAXYSSI_TASK_OUT failed with exit 3: iptables: Table does not exist",
            ),
        ):
            guest.install_task_network_firewall({"workspace_uid": 10123})

    def test_runtime_channel_is_discovered_without_udev_named_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            class_root = root / "sys" / "class" / "virtio-ports"
            device_root = root / "dev"
            port = class_root / "vport0p1"
            port.mkdir(parents=True)
            device_root.mkdir()
            (port / "name").write_text(guest.CHANNEL_NAME + "\n", encoding="utf-8")
            (port / "uevent").write_text("DEVNAME=vport0p1\n", encoding="utf-8")
            device = device_root / "vport0p1"
            device.touch()

            self.assertEqual(
                device,
                guest.wait_for_runtime_channel(
                    timeout_seconds=0.1,
                    class_root=class_root,
                    device_root=device_root,
                ),
            )

    def test_runtime_channel_rejects_unsafe_uevent_device_name(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            class_root = root / "sys" / "class" / "virtio-ports"
            device_root = root / "dev"
            port = class_root / "port-entry"
            port.mkdir(parents=True)
            device_root.mkdir()
            (port / "name").write_text(guest.CHANNEL_NAME, encoding="utf-8")
            (port / "uevent").write_text("DEVNAME=../outside\n", encoding="utf-8")

            with self.assertRaises(FileNotFoundError):
                guest.wait_for_runtime_channel(
                    timeout_seconds=0.01,
                    class_root=class_root,
                    device_root=device_root,
                )

    def test_mounted_pack_requires_matching_descriptor_capabilities_and_entrypoints(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            (target / "bin").mkdir()
            for executable_name in ("python3", "uv"):
                executable_path = target / "bin" / executable_name
                executable_path.touch()
                executable_path.chmod(0o755)
            descriptor = {
                "format_version": 1,
                "id": "python-uv",
                "version": "1.2.3",
                "capabilities": ["python.execute", "uv.sync"],
            }
            (target / guest.PACK_DESCRIPTOR_NAME).write_text(
                guest.canonical_json(descriptor), encoding="utf-8"
            )

            guest.validate_mounted_pack(target, descriptor)

            descriptor["capabilities"] = ["python.execute"]
            with self.assertRaises(ValueError):
                guest.validate_mounted_pack(target, descriptor)

    def test_resource_limits_reject_invalid_disk_and_artifact_bounds(self):
        with self.assertRaises(ValueError):
            guest.ExecutionLimits.from_payload({"limits": {"disk_bytes": 1}})
        with self.assertRaises(ValueError):
            guest.ExecutionLimits.from_payload({"limits": {"max_artifact_bytes": 1}})


if __name__ == "__main__":
    unittest.main()
