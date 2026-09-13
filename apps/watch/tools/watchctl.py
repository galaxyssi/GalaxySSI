"""Install, inspect, and provision the debug watch app without logging pairing data."""
import argparse
import getpass
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.request

PACKAGE = "com.galaxyssi.watch"
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sdk_adb = Path(os.environ.get("LOCALAPPDATA", "")) / "Android/Sdk/platform-tools/adb.exe"
    parser.add_argument("--adb", default=str(sdk_adb) if sdk_adb.exists() else shutil.which("adb"))
    parser.add_argument("--server-port", default="5037")
    parser.add_argument("--serial", required=True)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("install")
    offer = commands.add_parser("offer")
    source = offer.add_mutually_exclusive_group(required=True)
    source.add_argument("--file", type=Path)
    source.add_argument("--url", help="Trusted local Desktop pairing payload endpoint")
    api = commands.add_parser("api", help="Privately import API configuration; key input is hidden")
    api_source = api.add_mutually_exclusive_group(required=True)
    api_source.add_argument("--file", type=Path)
    api_source.add_argument("--endpoint")
    api.add_argument("--model")
    api.add_argument("--api-style", choices=["openai", "anthropic", "gemini"], default="openai")
    screen = commands.add_parser("screenshot")
    screen.add_argument("output", type=Path)
    commands.add_parser("test")
    args = parser.parse_args()
    base = [args.adb, "-P", args.server_port, "-s", args.serial]

    def adb(*parts, data=None, timeout=120):
        result = subprocess.run(base + list(parts), input=data, capture_output=True, timeout=timeout)
        if result.returncode:
            # Do not echo a failed provisioning process's stdout or input.
            raise RuntimeError(f"ADB operation failed ({result.returncode})")
        return result.stdout

    if args.command == "install":
        abi = adb("shell", "getprop", "ro.product.cpu.abi").decode().strip()
        if abi not in {"armeabi-v7a", "arm64-v8a", "x86_64"}:
            raise RuntimeError(f"Unsupported ABI: {abi}")
        apk = ROOT / f"app/build/outputs/apk/debug/app-{abi}-debug.apk"
        if not apk.is_file():
            raise RuntimeError("Build the debug APK first")
        result = adb("install", "-r", str(apk))
        if b"Success" not in result:
            raise RuntimeError("ADB did not confirm installation")
        adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
        print(f"Installed debug watch app for {abi}")
    elif args.command in {"offer", "api"}:
        if args.file:
            data = args.file.read_bytes()
        elif args.command == "api":
            if not args.model:
                raise ValueError("Supply --model with --endpoint")
            key = getpass.getpass("API Key (hidden): ")
            data = json.dumps({"endpoint": args.endpoint, "model": args.model, "api_key": key, "api_style": args.api_style}).encode()
        else:
            with urllib.request.urlopen(args.url, timeout=10) as response:
                data = response.read(32001)
        if len(data) > 32000:
            raise ValueError("Pairing offer exceeds size limit")
        if not isinstance(json.loads(data), dict):
            raise ValueError("Pairing offer must be a JSON object")
        adb("shell", "run-as", PACKAGE, "mkdir", "-p", "files")
        filename = "api-profile.json" if args.command == "api" else "pairing-offer.json"
        adb("exec-in", "run-as", PACKAGE, "tee", "files/" + filename, data=data)
        adb("shell", "am", "force-stop", PACKAGE)
        adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
        print("Configuration imported privately. Review and confirm the destination on the watch.")
    elif args.command == "screenshot":
        data = adb("exec-out", "screencap", "-p")
        if not data.startswith(b"\x89PNG"):
            raise RuntimeError("Device did not return a PNG")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(data)
        print(str(args.output.resolve()))
    elif args.command == "test":
        apk = ROOT / "app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
        adb("install", "-r", "-t", str(apk))
        output = adb("shell", "am", "instrument", "-w", PACKAGE + ".test/androidx.test.runner.AndroidJUnitRunner", timeout=180)
        print(output.decode(errors="replace"))
        if b"FAILURES" in output or b"OK (" not in output:
            raise RuntimeError("Instrumentation tests did not pass")


if __name__ == "__main__":
    main()
