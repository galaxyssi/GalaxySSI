"""Runtime snapshots and Android candidate verification with unconditional stable restore."""
from __future__ import annotations

import os
import shutil
import subprocess
import tarfile
import tempfile
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Iterable

from .common import atomic_write_json, now_millis, sha256_file


@dataclass
class AndroidSnapshot:
    snapshot_id: str
    serial: str
    package_name: str
    root: str
    stable_apks: list[str]
    stable_sha256: dict[str, str]
    data_archive: str = ""
    data_sha256: str = ""
    screenshot_before: str = ""
    created_at_millis: int = 0

    def public(self) -> dict[str, Any]:
        return asdict(self)


class AndroidCandidateError(RuntimeError):
    pass


class AndroidCandidateTester:
    def __init__(
        self,
        snapshot_root: Path,
        *,
        package_name: str = "com.galaxyssi.chat",
        adb: str = "adb",
        serial: str = "",
    ) -> None:
        self.snapshot_root = Path(snapshot_root)
        self.snapshot_root.mkdir(parents=True, exist_ok=True)
        self.package_name = package_name
        self.adb = adb
        self.serial = serial or str(os.environ.get("ANDROID_SERIAL") or "").strip()

    def run(self, candidate_apk: Path, *, launch_wait_seconds: int = 8) -> dict[str, Any]:
        candidate = Path(candidate_apk).resolve()
        if not candidate.is_file():
            raise AndroidCandidateError(f"Candidate APK does not exist: {candidate}")
        serial = self._choose_device()
        snapshot = self._snapshot(serial)
        candidate_install_attempted = False
        result: dict[str, Any] = {
            "passed": False,
            "serial": serial,
            "candidate_apk": str(candidate),
            "candidate_sha256": sha256_file(candidate),
            "snapshot": snapshot.public(),
        }
        restore_error = ""
        candidate_error: Exception | None = None
        try:
            self._adb(serial, "logcat", "-c", timeout=30)
            candidate_install_attempted = True
            install = self._adb(serial, "install", "-r", "-t", str(candidate), timeout=300)
            if install.returncode != 0:
                raise AndroidCandidateError(install.stdout[-2_000:])
            self._adb(serial, "shell", "am", "force-stop", self.package_name, timeout=30)
            activity = self._resolve_activity(serial)
            launch = self._adb(serial, "shell", "am", "start", "-W", "-n", activity, timeout=90)
            if launch.returncode != 0 or "Error:" in launch.stdout:
                raise AndroidCandidateError(f"App launch failed: {launch.stdout[-2_000:]}")
            time.sleep(max(1, min(int(launch_wait_seconds), 30)))
            logcat_result = self._adb(
                serial,
                "logcat",
                "-d",
                "-v",
                "threadtime",
                timeout=60,
            )
            if logcat_result.returncode != 0:
                raise AndroidCandidateError(
                    f"Android log capture failed: {logcat_result.stdout[-2_000:]}"
                )
            logcat = logcat_result.stdout
            logcat_path = Path(snapshot.root) / "candidate-logcat.txt"
            logcat_path.write_text(logcat, encoding="utf-8")
            fatal_lines = _fatal_android_lines(logcat, self.package_name)
            screenshot = Path(snapshot.root) / "candidate.png"
            self._screenshot(serial, screenshot)
            if (
                not screenshot.is_file()
                or not screenshot.read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
            ):
                raise AndroidCandidateError(
                    "Android candidate screenshot was not captured."
                )
            result.update({
                "activity": activity,
                "launch_output": launch.stdout[-4_000:],
                "fatal_lines": fatal_lines,
                "logcat": str(logcat_path),
                "logcat_sha256": sha256_file(logcat_path),
                "screenshot": str(screenshot),
                "screenshot_sha256": sha256_file(screenshot),
            })
            if fatal_lines:
                raise AndroidCandidateError("Android fatal/ANR markers detected: " + " | ".join(fatal_lines[:8]))
        except Exception as exc:
            candidate_error = exc
            result["error"] = str(exc)[:4_000]
        finally:
            try:
                self._restore(
                    serial,
                    snapshot,
                    uninstall_only=candidate_install_attempted and not snapshot.stable_apks,
                )
            except Exception as exc:
                restore_error = str(exc)[:2_000]
                result["restore_error"] = restore_error
        result["stable_restored"] = not restore_error
        result["passed"] = candidate_error is None and not restore_error
        manifest = self._write_evidence_manifest(result, snapshot)
        result["evidence_manifest"] = str(manifest)
        result["evidence_sha256"] = sha256_file(manifest)
        if restore_error:
            raise AndroidCandidateError(f"Stable Android restore failed: {restore_error}")
        if candidate_error is not None:
            raise candidate_error
        return result

    def _write_evidence_manifest(
        self,
        result: dict[str, Any],
        snapshot: AndroidSnapshot,
    ) -> Path:
        root = Path(snapshot.root).resolve()
        artifacts: dict[str, dict[str, str]] = {}
        candidates = {
            "candidate_apk": result.get("candidate_apk"),
            "candidate_screenshot": result.get("screenshot"),
            "candidate_logcat": result.get("logcat"),
            "stable_screenshot_before": snapshot.screenshot_before,
            "stable_data": snapshot.data_archive,
        }
        for name, raw in candidates.items():
            path = Path(str(raw or "")).resolve() if raw else None
            if path is not None and path.is_file():
                artifacts[name] = {
                    "path": str(path),
                    "sha256": sha256_file(path),
                }
        for index, raw in enumerate(snapshot.stable_apks):
            path = Path(raw).resolve()
            if path.is_file():
                artifacts[f"stable_apk_{index}"] = {
                    "path": str(path),
                    "sha256": sha256_file(path),
                }
        manifest = root / "candidate-evidence.json"
        atomic_write_json(
            manifest,
            {
                "protocol": "galaxyssi.evolution.android-evidence.v1",
                "created_at_millis": now_millis(),
                "package_name": self.package_name,
                "serial": result.get("serial", ""),
                "activity": result.get("activity", ""),
                "passed": bool(result.get("passed")),
                "stable_restored": bool(result.get("stable_restored")),
                "fatal_lines": list(result.get("fatal_lines") or []),
                "error": str(result.get("error") or "")[:4_000],
                "restore_error": str(result.get("restore_error") or "")[:2_000],
                "artifacts": artifacts,
            },
        )
        return manifest

    def _choose_device(self) -> str:
        result = self._adb("", "devices", timeout=30)
        devices = []
        for line in result.stdout.splitlines()[1:]:
            columns = line.strip().split()
            if len(columns) >= 2 and columns[1] == "device":
                devices.append(columns[0])
        if self.serial:
            if self.serial not in devices:
                raise AndroidCandidateError(f"Requested Android device is not online: {self.serial}")
            return self.serial
        if len(devices) != 1:
            raise AndroidCandidateError(f"Exactly one Android device is required, found {len(devices)}")
        return devices[0]

    def _snapshot(self, serial: str) -> AndroidSnapshot:
        snapshot_id = f"android-{now_millis()}"
        root = self.snapshot_root / snapshot_id
        root.mkdir(parents=True, exist_ok=True)
        stable_apks: list[str] = []
        paths = self._adb(serial, "shell", "pm", "path", self.package_name, timeout=30)
        if any(line.strip().startswith("package:/") for line in paths.stdout.splitlines()):
            self._adb(
                serial,
                "shell",
                "am",
                "force-stop",
                self.package_name,
                timeout=30,
            )
        for index, line in enumerate(paths.stdout.splitlines()):
            remote = line.strip().removeprefix("package:")
            if not remote.startswith("/"):
                continue
            local = root / f"stable-{index}-{Path(remote).name}"
            pulled = self._adb(serial, "pull", remote, str(local), timeout=180)
            if pulled.returncode == 0 and local.is_file():
                stable_apks.append(str(local))
        data_archive = root / "app-data.tar"
        if stable_apks:
            self._backup_app_data(serial, data_archive)
        stable_sha256 = {
            Path(path).name: sha256_file(Path(path))
            for path in stable_apks
        }
        screenshot = root / "before.png"
        self._screenshot(serial, screenshot)
        return AndroidSnapshot(
            snapshot_id=snapshot_id,
            serial=serial,
            package_name=self.package_name,
            root=str(root),
            stable_apks=stable_apks,
            stable_sha256=stable_sha256,
            data_archive=str(data_archive) if data_archive.is_file() else "",
            data_sha256=sha256_file(data_archive) if data_archive.is_file() else "",
            screenshot_before=str(screenshot) if screenshot.is_file() else "",
            created_at_millis=now_millis(),
        )

    def _restore(self, serial: str, snapshot: AndroidSnapshot, *, uninstall_only: bool) -> None:
        if snapshot.stable_apks:
            self._verify_snapshot_files(snapshot)
            command = ["install-multiple", "-r", "-d", *snapshot.stable_apks] if len(snapshot.stable_apks) > 1 else ["install", "-r", "-d", snapshot.stable_apks[0]]
            installed = self._adb(serial, *command, timeout=300)
            if installed.returncode != 0:
                raise AndroidCandidateError(installed.stdout[-2_000:])
            if snapshot.data_archive and Path(snapshot.data_archive).is_file():
                self._restore_app_data(serial, Path(snapshot.data_archive))
            activity = self._resolve_activity(serial)
            launched = self._adb(
                serial,
                "shell",
                "am",
                "start",
                "-W",
                "-n",
                activity,
                timeout=90,
            )
            if launched.returncode != 0 or "Error:" in launched.stdout:
                raise AndroidCandidateError(
                    f"Restored stable App did not launch: {launched.stdout[-2_000:]}"
                )
        elif uninstall_only:
            removed = self._adb(serial, "uninstall", self.package_name, timeout=120)
            if removed.returncode != 0 and "Unknown package" not in removed.stdout:
                raise AndroidCandidateError(removed.stdout[-2_000:])

    @staticmethod
    def _verify_snapshot_files(snapshot: AndroidSnapshot) -> None:
        for raw in snapshot.stable_apks:
            path = Path(raw)
            if not path.is_file():
                raise AndroidCandidateError(f"Stable APK snapshot is missing: {path}")
            expected = snapshot.stable_sha256.get(path.name, "")
            if not expected or sha256_file(path) != expected:
                raise AndroidCandidateError(f"Stable APK snapshot hash mismatch: {path}")
        if snapshot.data_archive:
            archive = Path(snapshot.data_archive)
            if not archive.is_file():
                raise AndroidCandidateError(
                    f"Stable data snapshot is missing: {archive}"
                )
            if (
                not snapshot.data_sha256
                or sha256_file(archive) != snapshot.data_sha256
            ):
                raise AndroidCandidateError(
                    f"Stable data snapshot hash mismatch: {archive}"
                )

    def _backup_app_data(self, serial: str, target: Path) -> None:
        command = self._adb_argv(serial, "exec-out", "run-as", self.package_name, "tar", "-C", f"/data/data/{self.package_name}", "-cf", "-", ".")
        try:
            completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180, check=False)
        except (OSError, subprocess.TimeoutExpired):
            return
        if completed.returncode == 0 and completed.stdout:
            target.write_bytes(completed.stdout)

    def _restore_app_data(self, serial: str, archive: Path) -> None:
        command = self._adb_argv(serial, "exec-in", "run-as", self.package_name, "tar", "-C", f"/data/data/{self.package_name}", "-xf", "-")
        completed = subprocess.run(command, input=archive.read_bytes(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180, check=False)
        if completed.returncode != 0:
            raise AndroidCandidateError(completed.stdout.decode("utf-8", errors="replace")[-2_000:])

    def _resolve_activity(self, serial: str) -> str:
        result = self._adb(
            serial,
            "shell", "cmd", "package", "resolve-activity", "--brief",
            "-a", "android.intent.action.MAIN",
            "-c", "android.intent.category.LAUNCHER",
            self.package_name,
            timeout=30,
        )
        for line in reversed(result.stdout.splitlines()):
            value = line.strip()
            if "/" in value and "No activity" not in value:
                return value
        raise AndroidCandidateError("Could not resolve Android launcher activity")

    def _screenshot(self, serial: str, target: Path) -> None:
        command = self._adb_argv(serial, "exec-out", "screencap", "-p")
        try:
            completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60, check=False)
        except (OSError, subprocess.TimeoutExpired):
            return
        if completed.returncode == 0 and completed.stdout.startswith(b"\x89PNG"):
            target.write_bytes(completed.stdout)

    def _adb(self, serial: str, *args: str, timeout: int = 120) -> subprocess.CompletedProcess[str]:
        command = self._adb_argv(serial, *args)
        try:
            return subprocess.run(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout,
                shell=False,
                check=False,
            )
        except FileNotFoundError as exc:
            raise AndroidCandidateError("adb is not installed or not on PATH") from exc
        except subprocess.TimeoutExpired as exc:
            raise AndroidCandidateError(f"adb command timed out: {' '.join(command)}") from exc

    def _adb_argv(self, serial: str, *args: str) -> list[str]:
        return [self.adb, *(["-s", serial] if serial else []), *[str(value) for value in args]]


class DesktopStateSnapshot:
    """Conservative snapshot of selected Desktop state files, never the whole profile."""

    def __init__(self, snapshot_root: Path, *, maximum_bytes: int = 256 * 1024 * 1024) -> None:
        self.snapshot_root = Path(snapshot_root)
        self.snapshot_root.mkdir(parents=True, exist_ok=True)
        self.maximum_bytes = maximum_bytes

    def create(self, state_root: Path, relative_paths: Iterable[str]) -> Path:
        destination = self.snapshot_root / f"desktop-{now_millis()}"
        destination.mkdir(parents=True, exist_ok=True)
        used = 0
        for relative in relative_paths:
            source = (Path(state_root) / relative).resolve()
            try:
                source.relative_to(Path(state_root).resolve())
            except ValueError:
                continue
            if not source.exists():
                continue
            size = _tree_size(source)
            if used + size > self.maximum_bytes:
                continue
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                shutil.copytree(source, target, dirs_exist_ok=True)
            else:
                shutil.copy2(source, target)
            used += size
        return destination


def _fatal_android_lines(logcat: str, package_name: str) -> list[str]:
    lines = []
    capture = False
    for line in str(logcat or "").splitlines():
        lowered = line.casefold()
        if "fatal exception" in lowered or f"anr in {package_name}".casefold() in lowered:
            capture = True
        if capture and (package_name.casefold() in lowered or "fatal exception" in lowered or "androidruntime" in lowered):
            lines.append(line.strip()[:1_000])
        if len(lines) >= 30:
            break
    return lines


def _tree_size(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    total = 0
    for child in path.rglob("*"):
        try:
            if child.is_file():
                total += child.stat().st_size
        except OSError:
            continue
    return total
