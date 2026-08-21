import Foundation

/// Converts the Android-compatible Debian package operations into bounded guest scripts.
enum AgentIOSQemuLinuxSoftware {
  private static let maximumResults = 50
  private static let maximumDescriptionLength = 500
  private static let linuxSource = AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSourceLinuxPackage

  static func executionInput(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    input: AgentMcpJSONObject
  ) throws -> AgentMcpJSONObject {
    let script = try script(operation: operation, input: input)
    let timeout: Int64
    switch operation {
    case .softwareInstall, .softwareRemove:
      timeout = 30 * 60_000
    case .softwareCatalog, .softwareSearch, .softwareInspect:
      timeout = 60_000
    default:
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("Unsupported Debian software operation.")
    }
    return [
      "language": .string("shell"),
      "source": .string(script),
      "timeout_ms": .int(timeout),
      "network_enabled": .bool(operation != .softwareCatalog),
      "allowed_network_domains": .array([
        .string("deb.debian.org"),
        .string("security.debian.org")
      ])
    ]
  }

  static func result(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    input: AgentMcpJSONObject,
    guestResult: AgentMcpJSONObject
  ) throws -> AgentMcpJSONObject {
    let exitCode = guestResult["exit_code"]?.intValue ?? -1
    let stdout = guestResult["stdout"]?.stringValue ?? ""
    let stderr = guestResult["stderr"]?.stringValue ?? ""
    guard exitCode == 0 else {
      throw AgentIOSRuntimeBrokerError.remote(
        code: failureCode(operation),
        message: stderr.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(
          "Debian package operation exited with \(exitCode)."
        ),
        retryable: exitCode == 100
      )
    }

    switch operation {
    case .softwareCatalog:
      let architecture = stdout
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .ifBlank("arm64")
      return [
        "architecture": .string(architecture),
        "linux_ready": .bool(true),
        "sources": .array([
          .object([
            "id": .string(linuxSource),
            "trusted": .bool(false),
            "searchable": .bool(true),
            "install_tool_id": .string(AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareInstall)
          ])
        ]),
        "software": .array([]),
        "message": .string("Embedded Debian package source is ready")
      ]
    case .softwareSearch:
      return [
        "query": .string(input["query"]?.stringValue ?? ""),
        "architecture": .string("arm64"),
        "linux_ready": .bool(true),
        "source_errors": .array([]),
        "results": .array(packageRecords(stdout).map { .object($0) }),
        "message": .string("Embedded Debian software searched")
      ]
    case .softwareInspect:
      return packageRecords(stdout).first ?? unavailablePackage(input)
    case .softwareInstall:
      var value = packageRecords(stdout).last ?? installedPackage(input)
      value["message"] = .string("Embedded Debian software installed and verified")
      return value
    case .softwareRemove:
      let description = fields.count > 3 ? String(fields[3]) : ""
      return [
        "software_id": .string(packageId(input)),
        "source": .string(linuxSource),
        "installed": .bool(false),
        "compatible": .bool(true),
        "message": .string("Embedded Debian software removed and verified")
      ]
    default:
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("Unsupported Debian software operation.")
    }
  }

  private static func script(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    input: AgentMcpJSONObject
  ) throws -> String {
    switch operation {
    case .softwareCatalog:
      return """
        set -eu
        export LC_ALL=C
        command -v apt-get >/dev/null 2>&1 || { echo 'apt-get is unavailable' >&2; exit 127; }
        dpkg --print-architecture 2>/dev/null || uname -m
        """
    case .softwareSearch:
      let query = try requiredQuery(input)
      let limit = max(1, min(Int(input["limit"]?.intValue ?? 10), maximumResults))
      return """
        set -eu
        export LC_ALL=C
        command -v apt-cache >/dev/null 2>&1 || { echo 'apt-cache is unavailable' >&2; exit 127; }
        \(ensurePackageIndexScript())
        apt-cache search --names-only -- \(shellQuote(query)) | head -n \(limit) | while IFS= read -r line; do
          package=${line%% - *}
          description=${line#* - }
          version=$(apt-cache policy "$package" | sed -n 's/^  Candidate: //p' | head -n 1)
          installed=no
          dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null | grep -q '^ii ' && installed=installed || true
          printf '%s\\t%s\\t%s\\t%s\\n' "$package" "$version" "$installed" "$description"
        done
        """
    case .softwareInspect:
      let package = try requiredPackageId(input)
      return """
        set -eu
        export LC_ALL=C
        command -v apt-cache >/dev/null 2>&1 || { echo 'apt-cache is unavailable' >&2; exit 127; }
        \(ensurePackageIndexScript())
        package=\(shellQuote(package))
        version=$(apt-cache policy "$package" | sed -n 's/^  Candidate: //p' | head -n 1)
        installed=no
        installed_version=$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)
        [ -n "$installed_version" ] && installed=installed && version=$installed_version
        description=$(apt-cache show "$package" 2>/dev/null | sed -n 's/^Description-en: //p; s/^Description: //p' | head -n 1)
        printf '%s\\t%s\\t%s\\t%s\\n' "$package" "$version" "$installed" "$description"
        """
    case .softwareInstall, .softwareRemove:
      let package = try requiredPackageId(input)
      let action = operation == .softwareInstall ? "install" : "remove"
      let verify = operation == .softwareInstall
        ? "dpkg-query -W -f='${binary:Package}\\t${Version}\\tinstalled\\t\\n' \"$package\""
        : "! dpkg-query -W \"$package\" >/dev/null 2>&1"
      return """
        set -eu
        export LC_ALL=C DEBIAN_FRONTEND=noninteractive
        command -v apt-get >/dev/null 2>&1 || { echo 'apt-get is unavailable' >&2; exit 127; }
        package=\(shellQuote(package))
        apt-get update
        apt-get \(action) -y --no-install-recommends "$package"
        \(verify)
        """
    default:
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("Unsupported Debian software operation.")
    }
  }

  private static func packageRecords(_ stdout: String) -> [AgentMcpJSONObject] {
    var seen = Set<String>()
    return stdout.split(whereSeparator: \.isNewline).compactMap { line in
      let fields = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
      guard let id = fields.first.map(String.init), isPackageId(id), seen.insert(id).inserted else { return nil }
      return [
        "software_id": .string(id),
        "source": .string(linuxSource),
        "version": .string(fields.count > 1 ? String(fields[1]) : ""),
        "installed": .bool(fields.count > 2 && fields[2] == "installed"),
        "compatible": .bool(true),
        "description": .string(String(description.prefix(maximumDescriptionLength)),
        "install_tool_id": .string(AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareInstall)
      ]
    }
  }

  private static func unavailablePackage(_ input: AgentMcpJSONObject) -> AgentMcpJSONObject {
    [
      "software_id": .string(packageId(input)),
      "source": .string(linuxSource),
      "installed": .bool(false),
      "compatible": .bool(false),
      "reason": .string("No Debian package candidate is available")
    ]
  }

  private static func installedPackage(_ input: AgentMcpJSONObject) -> AgentMcpJSONObject {
    [
      "software_id": .string(packageId(input)),
      "source": .string(linuxSource),
      "installed": .bool(true),
      "compatible": .bool(true)
    ]
  }

  private static func ensurePackageIndexScript() -> String {
    """
      if ! find /var/lib/apt/lists -maxdepth 1 -type f -name '*_Packages' -print -quit 2>/dev/null | grep -q .; then
        command -v apt-get >/dev/null 2>&1 || { echo 'apt-get is unavailable' >&2; exit 127; }
        apt-get update >&2
      fi
      """
  }

  private static func requiredQuery(_ input: AgentMcpJSONObject) throws -> String {
    let query = (input["query"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty, query.utf8.count <= 160 else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("A Debian software search query is required.")
    }
    return query
  }

  private static func requiredPackageId(_ input: AgentMcpJSONObject) throws -> String {
    let id = packageId(input)
    guard isPackageId(id) else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("A valid Debian package id is required.")
    }
    return id
  }

  private static func packageId(_ input: AgentMcpJSONObject) -> String {
    (input["software_id"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isPackageId(_ value: String) -> Bool {
    value.range(of: "^[a-z0-9][a-z0-9+.-]{0,127}$", options: .regularExpression) != nil
  }

  private static func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
  }

  private static func failureCode(_ operation: AgentIOSOnDeviceRuntimeToolOperation) -> String {
    switch operation {
    case .softwareCatalog: return "software_catalog_failed"
    case .softwareSearch: return "software_search_failed"
    case .softwareInspect: return "software_inspect_failed"
    case .softwareInstall: return "software_install_failed"
    case .softwareRemove: return "software_remove_failed"
    default: return "software_operation_failed"
    }
  }
}
