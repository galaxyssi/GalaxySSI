import Foundation

enum AgentIOSProjectRepositoryReadOperation: String, CaseIterable, Identifiable {
  case inspect
  case diff
  case log

  var id: String { rawValue }
}

enum AgentIOSProjectRepositoryReadToolCatalog {
  static let inspect = "signalasi.project.repository.inspect"
  static let diff = "signalasi.project.repository.diff"
  static let log = "signalasi.project.repository.log"

  static let executorId = "signalasi.ios_project_repository_read"
  static let readConsent = "signalasi.consent.project_read"
  static let maxOutputCharacters: Int64 = 256 * 1_024
  static let maxLogEntries: Int64 = 200
  static let toolIds: Set<String> = [inspect, diff, log]

  static func definitions(
    runtimeProvider: AgentIOSOnDeviceRuntimeToolProviding
  ) -> [AgentPhoneNativeToolDefinition] {
    AgentIOSProjectRepositoryReadOperation.allCases.map { operation in
      definition(operation, runtimeProvider: runtimeProvider)
    }
  }

  static func operation(for toolId: String) -> AgentIOSProjectRepositoryReadOperation? {
    switch toolId {
    case inspect: return .inspect
    case diff: return .diff
    case log: return .log
    default: return nil
    }
  }

  private static func definition(
    _ operation: AgentIOSProjectRepositoryReadOperation,
    runtimeProvider: AgentIOSOnDeviceRuntimeToolProviding
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: toolId(operation),
      version: AgentPhoneNativeToolCatalog.version,
      title: title(operation),
      description: description(operation),
      location: .application,
      inputSchema: inputSchema(operation),
      outputSchema: outputSchema(operation),
      risk: .low,
      capabilities: ["project.repository.read", "runtime.linux", "git.read"],
      requiredPermissions: [
        AgentNativePermissionRequirement(
          id: AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission,
          title: "iOS on-device runtime",
          description: "Runs Git inside the configured embedded Debian runtime."
        ),
        AgentNativePermissionRequirement(
          id: AgentIOSOnDeviceRuntimeNativeToolCatalog.workspacePermission,
          title: "Runtime project workspace",
          description: "Restricts repository reads to the current conversation project."
        )
      ],
      requiredConsents: [
        AgentNativeConsentRequirement(
          id: readConsent,
          title: "Read phone project repository",
          description: "Allows read-only Git metadata, diff, and history inspection.",
          required: false
        )
      ],
      timeoutMillis: 2 * 60_000,
      idempotency: .idempotent,
      availability: runtimeProvider.availability(operation: .execute)
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "platform": "ios",
        "compatibility_source": "AgentMobileProjectNativeTools",
        "runtime": runtimeProvider.implementationId,
        "scope": "conversation_project",
        "mutation": "none"
      ]
    )
  }

  private static func toolId(_ operation: AgentIOSProjectRepositoryReadOperation) -> String {
    switch operation {
    case .inspect: return inspect
    case .diff: return diff
    case .log: return log
    }
  }

  private static func title(_ operation: AgentIOSProjectRepositoryReadOperation) -> String {
    switch operation {
    case .inspect: return "Inspect the phone project repository"
    case .diff: return "Read the phone project diff"
    case .log: return "Read recent phone project commits"
    }
  }

  private static func description(_ operation: AgentIOSProjectRepositoryReadOperation) -> String {
    switch operation {
    case .inspect:
      return "Returns empty, partial, or ready repository state plus the current branch, commit, origin, upstream, and optional working-tree changes from the persistent iOS Linux project."
    case .diff:
      return "Returns a bounded staged and unstaged Git diff, or compares base_ref...head_ref, without allowing the model to invent shell Git commands."
    case .log:
      return "Returns bounded machine-readable Git history for a validated ref from the persistent iOS Linux project."
    }
  }

  private static func inputSchema(_ operation: AgentIOSProjectRepositoryReadOperation) -> AgentMcpJSONObject {
    var properties: [String: AgentMcpJSONValue] = [
      "workspace_id": .object(stringSchema(maxLength: 128))
    ]
    switch operation {
    case .inspect:
      properties["working_tree"] = .object(["type": .string("boolean")])
    case .diff:
      properties["base_ref"] = .object(stringSchema(maxLength: 256))
      properties["head_ref"] = .object(stringSchema(maxLength: 256))
      properties["max_characters"] = .object(integerSchema(minimum: 1_000, maximum: maxOutputCharacters))
    case .log:
      properties["ref"] = .object(stringSchema(maxLength: 256))
      properties["max_entries"] = .object(integerSchema(minimum: 1, maximum: maxLogEntries))
      properties["max_characters"] = .object(integerSchema(minimum: 1_000, maximum: maxOutputCharacters))
    }
    return objectSchema(properties: properties, required: ["workspace_id"])
  }

  private static func outputSchema(_ operation: AgentIOSProjectRepositoryReadOperation) -> AgentMcpJSONObject {
    switch operation {
    case .inspect:
      return objectSchema(properties: [
        "state": .object(stringSchema(maxLength: 32)),
        "git_available": .object(["type": .string("boolean")]),
        "branch": .object(stringSchema(maxLength: 256)),
        "head_commit": .object(stringSchema(maxLength: 128)),
        "repository_url": .object(stringSchema(maxLength: 2_048)),
        "upstream": .object(stringSchema(maxLength: 512)),
        "detached_head": .object(["type": .string("boolean")]),
        "working_tree_included": .object(["type": .string("boolean")]),
        "clean": .object(["type": .string("boolean")]),
        "staged": .object(stringArraySchema()),
        "modified": .object(stringArraySchema()),
        "untracked": .object(stringArraySchema()),
        "conflicting": .object(stringArraySchema())
      ], additionalProperties: true)
    case .diff:
      return objectSchema(properties: [
        "diff": .object(stringSchema(maxLength: maxOutputCharacters)),
        "truncated": .object(["type": .string("boolean")]),
        "max_characters": .object(integerSchema(minimum: 1_000, maximum: maxOutputCharacters))
      ], additionalProperties: true)
    case .log:
      return objectSchema(properties: [
        "ref": .object(stringSchema(maxLength: 256)),
        "commits": .object([
          "type": .string("array"),
          "items": .object(objectSchema(additionalProperties: true)),
          "maxItems": .int(maxLogEntries)
        ]),
        "truncated": .object(["type": .string("boolean")])
      ], additionalProperties: true)
    }
  }

  private static func objectSchema(
    properties: [String: AgentMcpJSONValue] = [:],
    required: [String] = [],
    additionalProperties: Bool = false
  ) -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object(properties),
      "required": .array(required.map(AgentMcpJSONValue.string)),
      "additionalProperties": .bool(additionalProperties)
    ]
  }

  private static func stringSchema(maxLength: Int64) -> AgentMcpJSONObject {
    ["type": .string("string"), "maxLength": .int(maxLength)]
  }

  private static func integerSchema(minimum: Int64, maximum: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("integer"),
      "minimum": .int(minimum),
      "maximum": .int(maximum)
    ]
  }

  private static func stringArraySchema() -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(stringSchema(maxLength: 4_096)),
      "maxItems": .int(10_000)
    ]
  }
}

struct AgentIOSProjectRepositoryReadToolExecutor {
  private let runtimeProvider: AgentIOSOnDeviceRuntimeToolProviding

  init(runtimeProvider: AgentIOSOnDeviceRuntimeToolProviding) {
    self.runtimeProvider = runtimeProvider
  }

  func executableDefinition(
    _ definition: AgentPhoneNativeToolDefinition
  ) -> AgentNativeToolExecutableDefinition {
    AgentNativeToolExecutableDefinition(
      definition: definition,
      executor: { invocation in
        try invocation.checkpoint()
        let result = self.execute(invocation)
        try invocation.checkpoint()
        return result
      }
    )
  }

  private func execute(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    guard let operation = AgentIOSProjectRepositoryReadToolCatalog.operation(for: invocation.descriptor.id) else {
      return .failure(code: "project_repository_unknown_tool", message: "Unknown project repository read tool.")
    }
    let requestedWorkspaceId = (invocation.input["workspace_id"]?.stringValue ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let workspaceId = [
      invocation.context.attributes["workspace_id"],
      invocation.context.turnId,
      invocation.context.conversationId
    ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? ""
    guard workspaceId.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil else {
      return .failure(code: "invalid_project_workspace", message: "Phone project workspace id is invalid.")
    }
    guard requestedWorkspaceId == "current" || requestedWorkspaceId == workspaceId else {
      return .failure(
        code: "project_workspace_scope_denied",
        message: "Phone project repository reads are restricted to the current conversation workspace."
      )
    }
    do {
      try invocation.reportProgress(
        stage: "repository_read",
        message: "Reading the iOS phone project repository",
        percent: 10
      )
      let execution = runtimeProvider.invoke(
        operation: .execute,
        input: try runtimeInput(operation: operation, input: invocation.input, invocation: invocation),
        invocation: runtimeInvocation(invocation, workspaceId: workspaceId)
      )
      guard execution.isSuccess else { return repositoryFailure(execution, operation: operation) }
      let exitCode = execution.output["exit_code"]?.intValue ?? -1
      guard exitCode == 0 else {
        return commandFailure(execution, operation: operation, exitCode: exitCode)
      }
      let stdout = execution.output["stdout"]?.stringValue ?? ""
      var output: AgentMcpJSONObject
      switch operation {
      case .inspect:
        output = parseInspection(stdout)
      case .diff:
        output = parseDiff(stdout, requestedLimit: boundedOutputLimit(invocation.input))
      case .log:
        output = parseLog(stdout, ref: validatedRef(invocation.input["ref"]?.stringValue, fallback: "HEAD"))
      }
      output["workspace_id"] = .string(workspaceId)
      var metadata = execution.metadata
      metadata["implementation"] = .string(AgentIOSProjectRepositoryReadToolCatalog.executorId)
      metadata["runtime"] = .string(runtimeProvider.implementationId)
      metadata["operation"] = .string(operation.rawValue)
      metadata["mutation"] = .string("none")
      try? invocation.reportProgress(
        stage: "repository_read",
        message: "iOS phone project repository read completed",
        percent: 100
      )
      return .success(output: output, message: successMessage(operation), metadata: metadata)
    } catch let error as AgentIOSProjectRepositoryReadError {
      return .failure(code: error.code, message: error.message)
    } catch {
      return .failure(
        code: "project_repository_read_failed",
        message: error.localizedDescription.ifBlank("The iOS phone project repository could not be read."),
        retryable: true
      )
    }
  }

  private func runtimeInvocation(
    _ invocation: AgentNativeToolInvocation,
    workspaceId: String
  ) -> AgentNativeToolInvocation {
    var copy = invocation
    copy.context.attributes["workspace_id"] = workspaceId
    return copy
  }

  private func runtimeInput(
    operation: AgentIOSProjectRepositoryReadOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) throws -> AgentMcpJSONObject {
    let arguments: [String]
    switch operation {
    case .inspect:
      arguments = [(input["working_tree"]?.boolValue ?? false) ? "true" : "false"]
    case .diff:
      let base = try validatedOptionalRef(input["base_ref"]?.stringValue)
      let head = try validatedOptionalRef(input["head_ref"]?.stringValue)
      guard !base.isEmpty || head.isEmpty else {
        throw AgentIOSProjectRepositoryReadError(
          code: "invalid_project_ref",
          message: "A Git diff head ref requires a base ref."
        )
      }
      arguments = [base, head.ifBlank("HEAD"), String(boundedOutputLimit(input))]
    case .log:
      let ref = try validatedRequiredRef(input["ref"]?.stringValue, fallback: "HEAD")
      let entries = max(1, min(input["max_entries"]?.intValue ?? 20, AgentIOSProjectRepositoryReadToolCatalog.maxLogEntries))
      arguments = [ref, String(entries), String(boundedOutputLimit(input))]
    }
    let timeout = max(100, min(invocation.remainingTimeMillis, 2 * 60_000))
    return [
      "language": .string(AgentRuntimeLanguage.shell.rawValue),
      "source": .string(script(operation)),
      "arguments": .array(arguments.map(AgentMcpJSONValue.string)),
      "timeout_ms": .int(timeout),
      "network_enabled": .bool(false),
      "allowed_network_domains": .array([]),
      "artifact_paths": .array([])
    ]
  }

  private func script(_ operation: AgentIOSProjectRepositoryReadOperation) -> String {
    switch operation {
    case .inspect:
      return Self.inspectScript
    case .diff:
      return Self.diffScript
    case .log:
      return Self.logScript
    }
  }

  private func parseInspection(_ stdout: String) -> AgentMcpJSONObject {
    let marker = "__SIGNALASI_STATUS__\n"
    let sections = stdout.components(separatedBy: marker)
    let headers = parseHeaders(sections.first ?? "")
    let includeWorkingTree = headers["working_tree_included"] == "true"
    var output: AgentMcpJSONObject = [
      "state": .string(headers["state"] ?? "empty"),
      "git_available": .bool(headers["git_available"] == "true"),
      "branch": .string(headers["branch"] ?? ""),
      "head_commit": .string(headers["head_commit"] ?? ""),
      "repository_url": .string(redactedRepositoryURL(headers["repository_url"] ?? "")),
      "upstream": .string(headers["upstream"] ?? ""),
      "detached_head": .bool(headers["detached_head"] == "true"),
      "working_tree_included": .bool(includeWorkingTree)
    ]
    guard includeWorkingTree else { return output }
    let changes = parsePorcelain(sections.dropFirst().joined(separator: marker))
    output["clean"] = .bool(changes.staged.isEmpty && changes.modified.isEmpty && changes.untracked.isEmpty && changes.conflicting.isEmpty)
    output["staged"] = .array(changes.staged.map(AgentMcpJSONValue.string))
    output["modified"] = .array(changes.modified.map(AgentMcpJSONValue.string))
    output["untracked"] = .array(changes.untracked.map(AgentMcpJSONValue.string))
    output["conflicting"] = .array(changes.conflicting.map(AgentMcpJSONValue.string))
    return output
  }

  private func parseHeaders(_ value: String) -> [String: String] {
    value.split(whereSeparator: { $0.isNewline }).reduce(into: [:]) { result, line in
      let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
      guard fields.count == 2 else { return }
      result[String(fields[0])] = String(fields[1])
    }
  }

  private func parsePorcelain(_ value: String) -> AgentIOSProjectWorkingTreeChanges {
    var result = AgentIOSProjectWorkingTreeChanges()
    let conflictCodes: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
    for lineValue in value.split(whereSeparator: { $0.isNewline }) {
      let line = String(lineValue)
      guard line.count >= 3 else { continue }
      let code = String(line.prefix(2))
      let path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !path.isEmpty else { continue }
      if code == "??" {
        result.untracked.append(path)
      } else if conflictCodes.contains(code) {
        result.conflicting.append(path)
      } else {
        if code.first != " " { result.staged.append(path) }
        if code.last != " " { result.modified.append(path) }
      }
    }
    result.staged = Array(Set(result.staged)).sorted()
    result.modified = Array(Set(result.modified)).sorted()
    result.untracked = Array(Set(result.untracked)).sorted()
    result.conflicting = Array(Set(result.conflicting)).sorted()
    return result
  }

  private func parseDiff(_ stdout: String, requestedLimit: Int64) -> AgentMcpJSONObject {
    let marker = "__SIGNALASI_DIFF__\n"
    let sections = stdout.components(separatedBy: marker)
    let headers = parseHeaders(sections.first ?? "")
    return [
      "diff": .string(sections.dropFirst().joined(separator: marker)),
      "truncated": .bool(headers["truncated"] == "true"),
      "max_characters": .int(requestedLimit)
    ]
  }

  private func parseLog(_ stdout: String, ref: String) -> AgentMcpJSONObject {
    let marker = "__SIGNALASI_LOG__\n"
    let sections = stdout.components(separatedBy: marker)
    let headers = parseHeaders(sections.first ?? "")
    let records = sections.dropFirst().joined(separator: marker).split(separator: "\u{1e}")
    let commits: [AgentMcpJSONValue] = records.compactMap { record in
      let fields = record.split(separator: "\u{1f}", maxSplits: 5, omittingEmptySubsequences: false)
      guard fields.count == 6 else { return nil }
      return .object([
        "commit": .string(String(fields[0])),
        "parents": .array(String(fields[1]).split(separator: " ").map { .string(String($0)) }),
        "author_name": .string(String(fields[2])),
        "author_email": .string(String(fields[3])),
        "authored_at": .string(String(fields[4])),
        "subject": .string(String(fields[5]))
      ])
    }
    return [
      "ref": .string(ref),
      "commits": .array(commits),
      "truncated": .bool(headers["truncated"] == "true")
    ]
  }

  private func repositoryFailure(
    _ execution: AgentNativeToolExecutionResult,
    operation: AgentIOSProjectRepositoryReadOperation
  ) -> AgentNativeToolExecutionResult {
    guard let error = execution.error else { return execution }
    var details = error.details
    details["operation"] = .string(operation.rawValue)
    details["runtime"] = .string(runtimeProvider.implementationId)
    return .failure(
      code: error.code,
      message: error.message,
      retryable: error.retryable,
      details: details
    )
  }

  private func commandFailure(
    _ execution: AgentNativeToolExecutionResult,
    operation: AgentIOSProjectRepositoryReadOperation,
    exitCode: Int64
  ) -> AgentNativeToolExecutionResult {
    let stderr = (execution.output["stderr"]?.stringValue ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let code: String
    let fallback: String
    switch exitCode {
    case 41:
      code = "project_git_unavailable"
      fallback = "Git is not installed in the iOS phone Linux runtime."
    case 42:
      code = "project_repository_unavailable"
      fallback = "The current iOS phone project is not a Git repository."
    default:
      code = "project_\(operation.rawValue)_failed"
      fallback = "The iOS phone project Git operation failed."
    }
    return .failure(
      code: code,
      message: stderr.ifBlank(fallback),
      retryable: exitCode == 41,
      details: [
        "exit_code": .int(exitCode),
        "operation": .string(operation.rawValue),
        "runtime": .string(runtimeProvider.implementationId)
      ]
    )
  }

  private func boundedOutputLimit(_ input: AgentMcpJSONObject) -> Int64 {
    max(1_000, min(
      input["max_characters"]?.intValue ?? 64 * 1_024,
      AgentIOSProjectRepositoryReadToolCatalog.maxOutputCharacters
    ))
  }

  private func validatedOptionalRef(_ value: String?) throws -> String {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !clean.isEmpty else { return "" }
    guard Self.isValidRevision(clean) else {
      throw AgentIOSProjectRepositoryReadError(code: "invalid_project_ref", message: "Git revision is invalid.")
    }
    return clean
  }

  private func validatedRequiredRef(_ value: String?, fallback: String) throws -> String {
    let clean = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(fallback)
    guard Self.isValidRevision(clean) else {
      throw AgentIOSProjectRepositoryReadError(code: "invalid_project_ref", message: "Git revision is invalid.")
    }
    return clean
  }

  private func validatedRef(_ value: String?, fallback: String) -> String {
    (try? validatedRequiredRef(value, fallback: fallback)) ?? fallback
  }

  private func successMessage(_ operation: AgentIOSProjectRepositoryReadOperation) -> String {
    switch operation {
    case .inspect: return "iOS phone project repository inspected"
    case .diff: return "iOS phone project diff read"
    case .log: return "iOS phone project history read"
    }
  }

  private func redactedRepositoryURL(_ value: String) -> String {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var components = URLComponents(string: clean), components.scheme != nil else {
      return clean
    }
    components.user = nil
    components.password = nil
    return components.string ?? clean
  }

  private static func isValidRevision(_ value: String) -> Bool {
    guard !value.hasPrefix("-"),
          value.count <= 256,
          !value.contains(".."),
          !value.contains("\\"),
          !value.contains("\u{0}") else { return false }
    return value.range(of: "^[A-Za-z0-9][A-Za-z0-9._/@{}~^:+-]{0,255}$", options: .regularExpression) != nil
  }

  private static let inspectScript = #"""
#!/bin/sh
set -u
print_value() {
  printf '%s\t' "$1"
  printf '%s' "$2" | tr '\t\r\n' '   '
  printf '\n'
}
if ! command -v git >/dev/null 2>&1; then
  print_value git_available false
  print_value state git_unavailable
  print_value working_tree_included false
  exit 0
fi
print_value git_available true
git() { command git -c safe.directory="$PWD" "$@"; }
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  if find . -mindepth 1 -maxdepth 1 ! -name '.signalasi-runtime' -print -quit | grep -q .; then
    print_value state partial
  else
    print_value state empty
  fi
  print_value working_tree_included false
  exit 0
fi
branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
head_commit="$(git rev-parse --verify HEAD 2>/dev/null || true)"
repository_url="$(git remote get-url origin 2>/dev/null || true)"
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
print_value state ready
print_value branch "$branch"
print_value head_commit "$head_commit"
print_value repository_url "$repository_url"
print_value upstream "$upstream"
if [ -z "$branch" ]; then print_value detached_head true; else print_value detached_head false; fi
if [ "${1-false}" = true ]; then
  print_value working_tree_included true
  printf '__SIGNALASI_STATUS__\n'
  git status --porcelain=v1 --untracked-files=all -- . ':(exclude).signalasi-runtime'
else
  print_value working_tree_included false
fi
"""#

  private static let diffScript = #"""
#!/bin/sh
set -eu
command -v git >/dev/null 2>&1 || exit 41
git() { command git -c safe.directory="$PWD" "$@"; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 42
base="${1-}"
head_ref="${2-HEAD}"
limit="${3-65536}"
output=".signalasi-runtime/project-diff-$$.txt"
trap 'rm -f "$output"' EXIT INT TERM
if [ -n "$base" ]; then
  git diff --no-ext-diff --no-color "$base...$head_ref" -- . ':(exclude).signalasi-runtime' >"$output"
else
  {
    git diff --no-ext-diff --no-color --cached -- . ':(exclude).signalasi-runtime'
    git diff --no-ext-diff --no-color -- . ':(exclude).signalasi-runtime'
  } >"$output"
fi
bytes="$(wc -c <"$output" | tr -d ' ')"
if [ "$bytes" -gt "$limit" ]; then truncated=true; else truncated=false; fi
printf 'truncated\t%s\n' "$truncated"
printf '__SIGNALASI_DIFF__\n'
head -c "$limit" "$output"
"""#

  private static let logScript = #"""
#!/bin/sh
set -eu
command -v git >/dev/null 2>&1 || exit 41
git() { command git -c safe.directory="$PWD" "$@"; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 42
ref="${1-HEAD}"
entries="${2-20}"
limit="${3-65536}"
output=".signalasi-runtime/project-log-$$.txt"
trap 'rm -f "$output"' EXIT INT TERM
git log "$ref" --max-count="$entries" --date=iso-strict --pretty=format:'%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%s%x1e' -- >"$output"
bytes="$(wc -c <"$output" | tr -d ' ')"
if [ "$bytes" -gt "$limit" ]; then truncated=true; else truncated=false; fi
printf 'truncated\t%s\n' "$truncated"
printf '__SIGNALASI_LOG__\n'
head -c "$limit" "$output"
"""#
}

private struct AgentIOSProjectWorkingTreeChanges {
  var staged: [String] = []
  var modified: [String] = []
  var untracked: [String] = []
  var conflicting: [String] = []
}

private struct AgentIOSProjectRepositoryReadError: Error {
  var code: String
  var message: String
}
