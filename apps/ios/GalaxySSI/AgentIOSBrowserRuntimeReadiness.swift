import Foundation

enum AgentIOSBrowserRuntimeReadiness {
  private static let helpers = ["browser-session-engine", "browser-runtime-readiness"]

  static func source(bundle: Bundle = .main) -> String? {
    var staging = ""
    for helper in helpers {
      guard let url = bundle.url(forResource: helper, withExtension: "cjs"),
            let data = try? Data(contentsOf: url), data.count <= 192 * 1_024 else { return nil }
      staging += "printf '%s' '\(data.base64EncodedString())' | base64 -d > \"$probe/\(helper).cjs\" || fail browser_probe_setup_failed\n"
    }
    let prelude = #"""
    set -eu
    fail() {
      printf '{"ok":false,"error":{"code":"%s"}}\n' "$1"
      exit 0
    }
    root=/opt/galaxyssi/packs
    if ! command -v node >/dev/null 2>&1; then
      [ ! -x "$root/node-js/bin/node" ] || fail node_path_missing
      fail node_missing
    fi
    node --version >/dev/null 2>&1 || fail node_start_failed
    launcher=$(command -v galaxyssi-browser || command -v signalasi-browser || true)
    if [ -z "$launcher" ]; then
      [ -d "$root/browser-automation/bin" ] || fail browser_pack_not_mounted
      for name in galaxyssi-browser signalasi-browser; do
        [ ! -x "$root/browser-automation/bin/$name" ] || fail browser_launcher_path_missing
      done
      fail browser_launcher_missing
    fi
    probe=$(mktemp -d) || fail browser_probe_setup_failed
    trap 'rm -rf -- "$probe"' EXIT
    export GALAXYSSI_BROWSER_STATE_ROOT="$probe/state"
    """#
    let launch = #"""
    "$launcher" "$probe/browser-runtime-readiness.cjs" || fail browser_launcher_start_failed
    """#
    let script = prelude + "\n" + staging + launch + "\n"
    return script.utf8.count <= 512 * 1_024 ? script : nil
  }

  static func interpret(_ output: AgentMcpJSONObject) -> AgentNativeToolExecutionResult {
    guard output["exit_code"]?.intValue == 0, output["output_truncated"]?.boolValue != true,
          let stdout = output["stdout"]?.strictStringValue, stdout.utf8.count <= 16_384,
          let envelope = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(stdout.utf8))
    else { return failure("browser_readiness_unobserved") }
    if envelope["ok"]?.boolValue == true, let result = envelope["result"]?.objectValue,
       result["browser_ready"]?.boolValue == true, result["tls_initialized"]?.boolValue == true,
       result.string("verification") == "chromium_local_page",
       result["website_verified"]?.boolValue == false, result["goal_terminal"]?.boolValue == false {
      return .success(output: [
        "browser_ready": .bool(true), "tls_initialized": .bool(true), "verification": .string("chromium_local_page"),
        "website_verified": .bool(false), "goal_terminal": .bool(false)
      ], message: "Chromium rendered a local page and initialized TLS; no website was verified.")
    }
    guard envelope["ok"]?.boolValue == false, let error = envelope["error"]?.objectValue else {
      return failure("browser_readiness_unobserved")
    }
    let code = error.string("code")
    return failure(messages[code] == nil ? "browser_readiness_unobserved" : code)
  }

  static func failure(_ code: String) -> AgentNativeToolExecutionResult {
    .failure(code: code, message: messages[code] ?? "Chromium readiness was not verified.", retryable: true,
      details: ["browser_ready": .bool(false), "website_verified": .bool(false), "goal_terminal": .bool(false)])
  }

  private static let messages = [
    "browser_pack_not_ready": "Install the signed browser-automation pack before running the browser probe.",
    "browser_pack_not_mounted": "The installed browser pack is not mounted in this guest. Reopen the app to boot the guest with the current signed packs.",
    "browser_probe_setup_failed": "The bundled browser probe could not be staged.",
    "node_missing": "Node.js is missing from the mounted guest packs.",
    "node_path_missing": "Node.js exists in the mounted pack but is absent from the guest PATH.",
    "node_start_failed": "Node.js was found but could not start. Inspect the guest native libraries.",
    "browser_launcher_missing": "No supported Chromium launcher is visible in the guest.",
    "browser_launcher_path_missing": "The browser launcher exists in the mounted pack but is absent from the guest PATH.",
    "browser_launcher_start_failed": "The browser launcher was found but could not start.",
    "browser_module_missing": "Playwright could not be loaded by the guest browser launcher.",
    "browser_executable_missing": "Playwright could not find the Chromium executable.",
    "browser_native_library_missing": "Chromium is missing native libraries. Check the signed pack and Debian NSS libraries; do not disable TLS validation.",
    "browser_text_rendering_failed": "Chromium started but visible body text did not render. Inspect the browser pack fonts.",
    "browser_readiness_unobserved": "The probe did not verify both visible text and TLS initialization."
  ]
}
