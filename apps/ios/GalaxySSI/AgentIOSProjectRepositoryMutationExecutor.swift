import Foundation

struct AgentIOSProjectRepositoryMutationToolExecutor {
  private let runtimeProvider: AgentIOSOnDeviceRuntimeToolProviding
  private let credentials: AgentIOSWebIntelligenceCredentials

  init(
    runtimeProvider: AgentIOSOnDeviceRuntimeToolProviding,
    credentials: AgentIOSWebIntelligenceCredentials = AgentIOSWebIntelligenceCredentials()
  ) {
    self.runtimeProvider = runtimeProvider
    self.credentials = credentials
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
    guard let operation = AgentIOSProjectRepositoryMutationToolCatalog.operation(for: invocation.descriptor.id) else {
      return .failure(code: "project_repository_unknown_tool", message: "Unknown project repository mutation tool.")
    }
    let requestedWorkspaceId = (invocation.input["workspace_id"]?.stringValue ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let workspaceId = currentWorkspaceId(invocation)
    guard workspaceId.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil else {
      return .failure(code: "invalid_project_workspace", message: "Phone project workspace id is invalid.")
    }
    guard requestedWorkspaceId == "current" || requestedWorkspaceId == workspaceId else {
      return .failure(
        code: "project_workspace_scope_denied",
        message: "Phone project repository mutations are restricted to the current conversation workspace."
      )
    }

    let token = Self.requiresNetwork(operation) ? credentials.credential(.githubToken) : ""
    do {
      try invocation.reportProgress(
        stage: "repository_\(operation.rawValue)",
        message: "Running the iOS phone project Git operation",
        percent: 10
      )
      let execution = runtimeProvider.invoke(
        operation: .execute,
        input: try runtimeInput(operation, invocation: invocation, token: token),
        invocation: runtimeInvocation(invocation, workspaceId: workspaceId)
      )
      guard execution.isSuccess else {
        return repositoryFailure(execution, operation: operation, token: token)
      }
      let exitCode = execution.output["exit_code"]?.intValue ?? -1
      guard exitCode == 0 else {
        return commandFailure(execution, operation: operation, exitCode: exitCode, token: token)
      }
      var output = parseOutput(execution.output["stdout"]?.stringValue ?? "", operation: operation)
      output["workspace_id"] = .string(workspaceId)
      var metadata = execution.metadata
      metadata["implementation"] = .string(AgentIOSProjectRepositoryMutationToolCatalog.executorId)
      metadata["runtime"] = .string(runtimeProvider.implementationId)
      metadata["operation"] = .string(operation.rawValue)
      metadata["credential_source"] = .string(token.isEmpty ? "anonymous" : "ios_keychain")
      try? invocation.reportProgress(
        stage: "repository_\(operation.rawValue)",
        message: "iOS phone project Git operation completed",
        percent: 100
      )
      return .success(output: output, message: successMessage(operation), metadata: metadata)
    } catch let error as AgentIOSProjectRepositoryMutationError {
      return .failure(code: error.code, message: error.message)
    } catch {
      return .failure(
        code: "project_repository_mutation_failed",
        message: redact(error.localizedDescription, token: token)
          .ifBlank("The iOS phone project repository could not be updated."),
        retryable: true
      )
    }
  }

  private func currentWorkspaceId(_ invocation: AgentNativeToolInvocation) -> String {
    [
      invocation.context.attributes["workspace_id"],
      invocation.context.turnId,
      invocation.context.conversationId
    ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? ""
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
    _ operation: AgentIOSProjectRepositoryMutationOperation,
    invocation: AgentNativeToolInvocation,
    token: String
  ) throws -> AgentMcpJSONObject {
    let arguments: [String]
    switch operation {
    case .clone:
      let featureBranch = try validatedOptionalRef(invocation.input["feature_branch"]?.stringValue)
      let requestedBranch = try validatedOptionalRef(invocation.input["branch"]?.stringValue)
      arguments = [
        try trustedRepositoryURL(invocation.input["repository_url"]?.stringValue),
        requestedBranch.ifBlank(featureBranch.isEmpty ? "" : "main"),
        featureBranch,
        String(max(1, min(invocation.input["depth"]?.intValue ?? 1, 100))),
        (invocation.input["replace_existing"]?.boolValue ?? false) ? "true" : "false"
      ]
    case .fetch:
      arguments = [
        try validatedRemote(invocation.input["remote"]?.stringValue),
        try validatedOptionalRef(invocation.input["ref"]?.stringValue)
      ]
    case .checkout:
      arguments = [
        try validatedRequiredRef(invocation.input["branch"]?.stringValue),
        (invocation.input["create"]?.boolValue ?? true) ? "true" : "false",
        try validatedOptionalRef(invocation.input["base_ref"]?.stringValue)
      ]
    case .commit:
      arguments = [
        try validatedCommitMessage(invocation.input["message"]?.stringValue),
        try validatedAuthorName(invocation.input["author_name"]?.stringValue),
        try validatedAuthorEmail(invocation.input["author_email"]?.stringValue)
      ]
    case .pull:
      arguments = [
        try validatedRemote(invocation.input["remote"]?.stringValue),
        try validatedOptionalRef(invocation.input["branch"]?.stringValue)
      ]
    case .push:
      guard !token.isEmpty else {
        throw AgentIOSProjectRepositoryMutationError(
          code: "project_github_credential_required",
          message: "Configure a GitHub token before publishing the iOS phone project."
        )
      }
      arguments = [
        try validatedRemote(invocation.input["remote"]?.stringValue),
        try validatedOptionalRef(invocation.input["branch"]?.stringValue),
        (invocation.input["force"]?.boolValue ?? false) ? "true" : "false",
        try validatedObjectId(invocation.input["expected_head"]?.stringValue)
      ]
    }
    let networkEnabled = Self.requiresNetwork(operation)
    let maximumTimeout: Int64 = networkEnabled ? 30 * 60_000 : 5 * 60_000
    var input: AgentMcpJSONObject = [
      "language": .string(AgentRuntimeLanguage.shell.rawValue),
      "source": .string(script(operation)),
      "arguments": .array(arguments.map(AgentMcpJSONValue.string)),
      "timeout_ms": .int(max(100, min(invocation.remainingTimeMillis, maximumTimeout))),
      "network_enabled": .bool(networkEnabled),
      "allowed_network_domains": .array(networkEnabled ? Self.githubNetworkDomains.map(AgentMcpJSONValue.string) : []),
      "artifact_paths": .array([]),
      AgentIOSRuntimeBrokerInternalInput.resourceProfile: .string(
        AgentIOSRuntimeBrokerInternalInput.projectGitResourceProfile
      )
    ]
    if networkEnabled && !token.isEmpty {
      input[AgentIOSRuntimeBrokerInternalInput.secretEnvironment] = .object([
        "GALAXYSSI_GITHUB_TOKEN": .string(token)
      ])
    }
    return input
  }

  private func script(_ operation: AgentIOSProjectRepositoryMutationOperation) -> String {
    switch operation {
    case .clone: return Self.cloneScript
    case .fetch: return Self.fetchScript
    case .checkout: return Self.checkoutScript
    case .commit: return Self.commitScript
    case .pull: return Self.pullScript
    case .push: return Self.pushScript
    }
  }

  private func parseOutput(
    _ stdout: String,
    operation: AgentIOSProjectRepositoryMutationOperation
  ) -> AgentMcpJSONObject {
    var headers: [String: String] = [:]
    var remoteRefs: [String] = []
    var changedFiles: [String] = []
    var remoteMessages: [String] = []
    for line in stdout.split(whereSeparator: { $0.isNewline }) {
      let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
      guard fields.count == 2 else { continue }
      if fields[0] == "remote_ref" {
        remoteRefs.append(String(fields[1]))
      } else if fields[0] == "changed_file",
                let data = Data(base64Encoded: String(fields[1])),
                let path = String(data: data, encoding: .utf8),
                !path.isEmpty {
        changedFiles.append(path)
      } else if fields[0] == "remote_message",
                let data = Data(base64Encoded: String(fields[1])),
                let message = String(data: data, encoding: .utf8),
                !message.isEmpty {
        remoteMessages.append(String(message.prefix(4_096)))
      } else {
        headers[String(fields[0])] = String(fields[1])
      }
    }
    var output: AgentMcpJSONObject = [
      "state": .string(headers["state"] ?? "ready"),
      "repository_url": .string(redactedRepositoryURL(headers["repository_url"] ?? "")),
      "branch": .string(headers["branch"] ?? ""),
      "head_commit": .string(headers["head_commit"] ?? ""),
      "clean": .bool(headers["clean"] == "true")
    ]
    if operation == .fetch {
      output["remote_refs"] = .array(Array(Set(remoteRefs)).sorted().prefix(256).map(AgentMcpJSONValue.string))
    }
    if operation == .commit {
      output["commit"] = .string(headers["head_commit"] ?? "")
      output["changed_files"] = .array(Array(Set(changedFiles)).sorted().map(AgentMcpJSONValue.string))
    }
    if operation == .push {
      output["remote_messages"] = .array(remoteMessages.suffix(64).map(AgentMcpJSONValue.string))
    }
    return output
  }

  private func repositoryFailure(
    _ execution: AgentNativeToolExecutionResult,
    operation: AgentIOSProjectRepositoryMutationOperation,
    token: String
  ) -> AgentNativeToolExecutionResult {
    guard let error = execution.error else { return execution }
    return .failure(
      code: error.code,
      message: redact(error.message, token: token),
      retryable: error.retryable,
      details: [
        "operation": .string(operation.rawValue),
        "runtime": .string(runtimeProvider.implementationId)
      ]
    )
  }

  private func commandFailure(
    _ execution: AgentNativeToolExecutionResult,
    operation: AgentIOSProjectRepositoryMutationOperation,
    exitCode: Int64,
    token: String
  ) -> AgentNativeToolExecutionResult {
    let detail = redact([
      execution.output["stderr"]?.stringValue ?? "",
      execution.output["stdout"]?.stringValue ?? ""
    ].joined(separator: "\n"), token: token)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = detail.lowercased()
    let code: String
    let fallback: String
    switch exitCode {
    case 41, 127:
      code = "project_git_unavailable"
      fallback = "Git could not be provisioned in the iOS phone Linux runtime."
    case 42:
      code = "project_repository_unavailable"
      fallback = "The current iOS phone project is not a Git repository."
    case 43:
      code = "project_worktree_not_clean"
      fallback = "Uncommitted project changes prevent this Git operation."
    case 64:
      code = "project_no_changes"
      fallback = "The iOS phone project has no changes to commit."
    case 65:
      code = "project_remote_not_trusted"
      fallback = "The configured project remote is not a trusted GitHub repository."
    case 66:
      code = "project_merge_conflicts"
      fallback = "Resolve the iOS phone project conflicts before committing."
    case 67:
      code = "project_branch_changed"
      fallback = "The current iOS phone project branch does not match the branch requested for publication."
    case 68:
      code = "project_head_changed"
      fallback = "The iOS phone project HEAD changed after it was inspected and cannot be published."
    default:
      if normalized.contains("authentication failed") || normalized.contains("could not read username") {
        code = "project_github_authentication_failed"
        fallback = "GitHub authentication failed. Update the GitHub credential in GalaxySSI and retry."
      } else if normalized.contains("repository not found") {
        code = "project_repository_not_found"
        fallback = "The GitHub repository was not found or the configured account cannot access it."
      } else {
        code = "project_\(operation.rawValue)_failed"
        fallback = "The iOS phone project Git operation failed."
      }
    }
    return .failure(
      code: code,
      message: detail.ifBlank(fallback),
      retryable: exitCode == 41 || exitCode == 127,
      details: [
        "exit_code": .int(exitCode),
        "operation": .string(operation.rawValue),
        "runtime": .string(runtimeProvider.implementationId)
      ]
    )
  }

  private func trustedRepositoryURL(_ value: String?) throws -> String {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard var components = URLComponents(string: clean),
          components.scheme?.lowercased() == "https",
          components.host?.lowercased() == "github.com",
          components.user == nil,
          components.password == nil,
          components.port == nil,
          components.query == nil,
          components.fragment == nil,
          components.percentEncodedPath == components.path else {
      throw AgentIOSProjectRepositoryMutationError(
        code: "invalid_project_repository_url",
        message: "Only canonical HTTPS GitHub repository URLs are allowed."
      )
    }
    let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard parts.count == 2,
          parts.allSatisfy({
            $0.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil
          }),
          !parts[0].isEmpty,
          !parts[1].replacingOccurrences(of: ".git", with: "").isEmpty else {
      throw AgentIOSProjectRepositoryMutationError(
        code: "invalid_project_repository_url",
        message: "The GitHub repository URL must contain exactly one owner and repository."
      )
    }
    components.scheme = "https"
    components.host = "github.com"
    components.path = "/\(parts[0])/\(parts[1])"
    return components.string ?? clean
  }

  private func validatedRemote(_ value: String?) throws -> String {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("origin") ?? "origin"
    guard clean.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", options: .regularExpression) != nil else {
      throw AgentIOSProjectRepositoryMutationError(code: "invalid_project_remote", message: "Git remote is invalid.")
    }
    return clean
  }

  private func validatedCommitMessage(_ value: String?) throws -> String {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !clean.isEmpty, clean.utf8.count <= 4_000, !clean.contains("\u{0}") else {
      throw AgentIOSProjectRepositoryMutationError(
        code: "invalid_project_commit_message",
        message: "Git commit message is invalid."
      )
    }
    return clean
  }

  private func validatedObjectId(_ value: String?) throws -> String {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard clean.range(of: "^[0-9a-fA-F]{40,64}$", options: .regularExpression) != nil else {
      throw AgentIOSProjectRepositoryMutationError(
        code: "invalid_project_commit",
        message: "Expected Git commit id is invalid."
      )
    }
    return clean.lowercased()
  }

  private func validatedAuthorName(_ value: String?) throws -> String {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("GalaxySSI") ?? "GalaxySSI"
    guard clean.utf8.count <= 120,
          !clean.contains("\n"),
          !clean.contains("\r"),
          !clean.contains("\u{0}") else {
      throw AgentIOSProjectRepositoryMutationError(
        code: "invalid_project_commit_author",
        message: "Git commit author name is invalid."
      )
    }
    return clean
  }

  private func validatedAuthorEmail(_ value: String?) throws -> String {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank("galaxyssi@hotmail.com") ?? "galaxyssi@hotmail.com"
    guard clean.utf8.count <= 254,
          clean.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil else {
      throw AgentIOSProjectRepositoryMutationError(
        code: "invalid_project_commit_author",
        message: "Git commit author email is invalid."
      )
    }
    return clean
  }

  private func validatedRequiredRef(_ value: String?) throws -> String {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard Self.isValidRef(clean) else {
      throw AgentIOSProjectRepositoryMutationError(code: "invalid_project_ref", message: "Git ref is invalid.")
    }
    return clean
  }

  private func validatedOptionalRef(_ value: String?, fallback: String = "") throws -> String {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(fallback) ?? fallback
    guard clean.isEmpty || Self.isValidRef(clean) else {
      throw AgentIOSProjectRepositoryMutationError(code: "invalid_project_ref", message: "Git ref is invalid.")
    }
    return clean
  }

  private static func isValidRef(_ value: String) -> Bool {
    guard !value.contains(".."),
          !value.hasSuffix("."),
          !value.hasSuffix("/"),
          !value.hasPrefix("/"),
          !value.contains("//"),
          !value.contains("@{") else { return false }
    return value.range(of: "^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$", options: .regularExpression) != nil
  }

  private func redactedRepositoryURL(_ value: String) -> String {
    guard var components = URLComponents(string: value), components.scheme != nil else { return value }
    components.user = nil
    components.password = nil
    return components.string ?? value
  }

  private func redact(_ value: String, token: String) -> String {
    guard !token.isEmpty else { return value }
    return value.replacingOccurrences(of: token, with: "[REDACTED]")
  }

  private func successMessage(_ operation: AgentIOSProjectRepositoryMutationOperation) -> String {
    switch operation {
    case .clone: return "iOS phone project repository prepared"
    case .fetch: return "iOS phone project remote refs fetched"
    case .checkout: return "iOS phone project branch switched"
    case .commit: return "iOS phone project changes committed"
    case .pull: return "iOS phone project updated"
    case .push: return "iOS phone project branch published"
    }
  }

  private static func requiresNetwork(_ operation: AgentIOSProjectRepositoryMutationOperation) -> Bool {
    operation == .clone || operation == .fetch || operation == .pull || operation == .push
  }

  private static let githubNetworkDomains = [
    "github.com",
    "api.github.com",
    "codeload.github.com",
    "objects.githubusercontent.com"
  ]

  private static let cloneScript = #"""
#!/bin/sh
set -eu
export LC_ALL=C GIT_TERMINAL_PROMPT=0
github_token="${GALAXYSSI_GITHUB_TOKEN-}"
unset GALAXYSSI_GITHUB_TOKEN
repository_url="$1"
base_branch="$2"
feature_branch="$3"
depth="$4"
replace_existing="$5"
local_branch="${base_branch:-main}"
control_dir='.galaxyssi-runtime'
askpass="$control_dir/git-askpass.sh"
metadata_root="${GALAXYSSI_GIT_METADATA_ROOT:-/var/lib/galaxyssi/git}"
workspace_key="$(basename "$PWD")"
case "$PWD" in /workspace/*) ;; *) printf '%s\n' 'Invalid project workspace' >&2; exit 2 ;; esac
case "$workspace_key" in *[!A-Za-z0-9._-]*|'') printf '%s\n' 'Invalid project workspace' >&2; exit 2 ;; esac
metadata_dir="$metadata_root/$workspace_key"
print_value() { printf '%s\t' "$1"; printf '%s' "$2" | tr '\t\r\n' '   '; printf '\n'; }
reset_workspace() {
  find . -mindepth 1 -maxdepth 1 ! -name "$control_dir" ! -name '.galaxyssi-tools' \
    ! -name '.galaxyssi-inputs' ! -name '.tmp' ! -name 'request.json' ! -name 'status.json' \
    ! -name '.galaxyssi-checkpoint.json' ! -name '.galaxyssi-stdout' ! -name '.galaxyssi-stderr' \
    ! -name '.galaxyssi-main' -exec rm -rf -- {} +
}
mkdir -p "$control_dir"
if ! command -v git >/dev/null 2>&1; then
  command -v apt-get >/dev/null 2>&1 || exit 127
  apt-get update
  apt-get install -y --no-install-recommends git openssh-client ca-certificates
fi
command -v git >/dev/null 2>&1 || exit 127
git() { command git -c safe.directory="$PWD" "$@"; }
cat >"$askpass" <<'GALAXYSSI_ASKPASS'
#!/bin/sh
case "$1" in *Username*) printf '%s\n' 'x-access-token' ;; *) printf '%s\n' "${GALAXYSSI_GITHUB_TOKEN-}" ;; esac
GALAXYSSI_ASKPASS
chmod 700 "$askpass"
export GIT_ASKPASS="$PWD/$askpass"
cleanup() { status=$?; rm -f "$askpass"; trap - EXIT INT TERM; exit "$status"; }
trap cleanup EXIT INT TERM
configure_excludes() {
  exclude_file="$(git rev-parse --git-path info/exclude)"
  mkdir -p "$(dirname "$exclude_file")"
  for pattern in '.galaxyssi-runtime/' '.galaxyssi-tools/' '.galaxyssi-inputs/' '.tmp/' \
    'request.json' 'status.json' '.galaxyssi-checkpoint.json' '.galaxyssi-stdout' \
    '.galaxyssi-stderr' '.galaxyssi-main'; do
    grep -Fqx "$pattern" "$exclude_file" 2>/dev/null || printf '%s\n' "$pattern" >>"$exclude_file"
  done
}
existing=false
if git rev-parse --git-dir >/dev/null 2>&1; then
  configure_excludes
  current_origin="$(git remote get-url origin 2>/dev/null || true)"
  if [ "${current_origin%/}" = "${repository_url%/}" ]; then
    existing=true
  elif [ "$replace_existing" = true ]; then
    reset_workspace
    rm -rf -- "$metadata_dir"
  else
    printf '%s\n' 'Existing phone workspace belongs to a different repository' >&2
    exit 2
  fi
fi
if [ -n "$base_branch" ]; then remote_ref="refs/heads/$base_branch"; else remote_ref='HEAD'; fi
if [ "$existing" = true ]; then
  GALAXYSSI_GITHUB_TOKEN="$github_token" git -c credential.helper= fetch --depth "$depth" origin "$remote_ref"
  if [ -n "$(git status --porcelain --untracked-files=all -- . ':(exclude).galaxyssi-runtime')" ]; then
    current_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [ -z "$feature_branch" ] || [ "$current_branch" = "$feature_branch" ] || exit 43
  elif [ -n "$feature_branch" ]; then
    if git show-ref --verify --quiet "refs/heads/$feature_branch"; then
      git checkout -q "$feature_branch"
      git merge --no-edit FETCH_HEAD
    else
      git checkout -q -b "$feature_branch" FETCH_HEAD
    fi
  else
    git checkout -q -B "$local_branch" FETCH_HEAD
  fi
else
  reset_workspace
  rm -rf -- "$metadata_dir"
  mkdir -p "$metadata_root"
  git init -q --separate-git-dir="$metadata_dir" .
  configure_excludes
  git remote add origin "$repository_url"
  GALAXYSSI_GITHUB_TOKEN="$github_token" git -c credential.helper= fetch --depth "$depth" origin "$remote_ref"
  if [ -n "$feature_branch" ]; then
    git checkout -q -B "$feature_branch" FETCH_HEAD
  else
    git checkout -q -B "$local_branch" FETCH_HEAD
  fi
fi
origin="$(git remote get-url origin 2>/dev/null || true)"
branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
head_commit="$(git rev-parse --verify HEAD 2>/dev/null || true)"
print_value state ready
print_value repository_url "$origin"
print_value branch "$branch"
print_value head_commit "$head_commit"
if [ -z "$(git status --porcelain --untracked-files=all -- . ':(exclude).galaxyssi-runtime')" ]; then
  print_value clean true
else
  print_value clean false
fi
"""#

  private static let fetchScript = authenticatedPrelude + #"""
remote="$1"
ref="$2"
require_trusted_remote "$remote"
if [ -n "$ref" ]; then
  source_ref="$ref"
  case "$source_ref" in refs/*) ;; *) source_ref="refs/heads/$source_ref" ;; esac
  case "$source_ref" in
    refs/heads/*) tracking="refs/remotes/$remote/${source_ref#refs/heads/}"; refspec="+$source_ref:$tracking" ;;
    *) refspec="$source_ref" ;;
  esac
  GALAXYSSI_GITHUB_TOKEN="$github_token" git -c credential.helper= fetch --prune "$remote" "$refspec"
else
  GALAXYSSI_GITHUB_TOKEN="$github_token" git -c credential.helper= fetch --prune "$remote"
fi
git for-each-ref --format='remote_ref%09%(refname:short)' "refs/remotes/$remote/"
emit_repository
"""#

  private static let checkoutScript = repositoryPrelude + #"""
branch="$1"
create="$2"
base_ref="$3"
require_clean
if [ "$create" = true ]; then
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout -q "$branch"
  elif [ -n "$base_ref" ]; then
    git checkout -q -b "$branch" "$base_ref"
  else
    git checkout -q -b "$branch"
  fi
else
  git checkout -q "$branch"
fi
emit_repository
"""#

  private static let commitScript = repositoryPrelude + #"""
message="$1"
author_name="$2"
author_email="$3"
if [ -z "$(git status --porcelain --untracked-files=all -- . ':(exclude).galaxyssi-runtime')" ]; then
  exit 64
fi
if [ -n "$(git diff --name-only --diff-filter=U -- . ':(exclude).galaxyssi-runtime')" ]; then
  exit 66
fi
emit_changed_files() {
  {
    git diff --cached --name-only --no-renames -- . ':(exclude).galaxyssi-runtime'
    git diff --name-only --no-renames -- . ':(exclude).galaxyssi-runtime'
    git ls-files --others --exclude-standard -- . ':(exclude).galaxyssi-runtime'
  } | sort -u | while IFS= read -r path; do
    [ -n "$path" ] || continue
    encoded="$(printf '%s' "$path" | base64 | tr -d '\n')"
    printf 'changed_file\t%s\n' "$encoded"
  done
}
emit_changed_files
git config user.name "$author_name"
git config user.email "$author_email"
git add -A -- . ':(exclude).galaxyssi-runtime'
git -c core.hooksPath=/dev/null -c commit.gpgSign=false commit -q -m "$message"
emit_repository
"""#

  private static let pullScript = authenticatedPrelude + #"""
remote="$1"
branch="$2"
require_trusted_remote "$remote"
require_clean
if [ -z "$branch" ]; then branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"; fi
[ -n "$branch" ] || { printf '%s\n' 'A branch is required for pull' >&2; exit 2; }
GALAXYSSI_GITHUB_TOKEN="$github_token" git -c credential.helper= fetch --prune "$remote" "refs/heads/$branch"
git merge --ff-only FETCH_HEAD
emit_repository
"""#

  private static let pushScript = authenticatedPrelude + #"""
remote="$1"
branch="$2"
force="$3"
expected_head="$4"
require_trusted_remote "$remote"
require_clean
current_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [ -z "$branch" ]; then branch="$current_branch"; fi
[ -n "$branch" ] || { printf '%s\n' 'A branch is required for push' >&2; exit 67; }
[ "$current_branch" = "$branch" ] || exit 67
current_head="$(git rev-parse --verify HEAD 2>/dev/null || true)"
[ -n "$current_head" ] || exit 42
[ "$current_head" = "$expected_head" ] || exit 68
push_output=".galaxyssi-runtime/project-push-$$.txt"
trap 'rm -f "$askpass" "$push_output"' EXIT INT TERM
set +e
if [ "$force" = true ]; then
  GALAXYSSI_GITHUB_TOKEN="$github_token" git push --porcelain --force-with-lease \
    "$remote" "refs/heads/$branch:refs/heads/$branch" >"$push_output" 2>&1
else
  GALAXYSSI_GITHUB_TOKEN="$github_token" git push --porcelain \
    "$remote" "refs/heads/$branch:refs/heads/$branch" >"$push_output" 2>&1
fi
push_status=$?
set -e
if [ "$push_status" -ne 0 ]; then
  cat "$push_output" >&2
  exit "$push_status"
fi
while IFS= read -r line; do
  [ -n "$line" ] || continue
  encoded="$(printf '%s' "$line" | base64 | tr -d '\n')"
  printf 'remote_message\t%s\n' "$encoded"
done <"$push_output"
emit_repository
"""#

  private static let authenticatedPrelude = repositoryPrelude + #"""
control_dir='.galaxyssi-runtime'
askpass="$control_dir/git-askpass.sh"
github_token="${GALAXYSSI_GITHUB_TOKEN-}"
unset GALAXYSSI_GITHUB_TOKEN
mkdir -p "$control_dir"
cat >"$askpass" <<'GALAXYSSI_ASKPASS'
#!/bin/sh
case "$1" in *Username*) printf '%s\n' 'x-access-token' ;; *) printf '%s\n' "${GALAXYSSI_GITHUB_TOKEN-}" ;; esac
GALAXYSSI_ASKPASS
chmod 700 "$askpass"
export GIT_ASKPASS="$PWD/$askpass"
trap 'rm -f "$askpass"' EXIT INT TERM
"""#

  private static let repositoryPrelude = #"""
#!/bin/sh
set -eu
export LC_ALL=C GIT_TERMINAL_PROMPT=0
command -v git >/dev/null 2>&1 || exit 41
git() { command git -c safe.directory="$PWD" "$@"; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 42
print_value() { printf '%s\t' "$1"; printf '%s' "$2" | tr '\t\r\n' '   '; printf '\n'; }
require_trusted_remote() {
  remote_url="$(git remote get-url "$1" 2>/dev/null || true)"
  case "$remote_url" in https://github.com/*/*) ;; *) exit 65 ;; esac
  remote_path="${remote_url#https://github.com/}"
  case "$remote_path" in */*/*|*'?'*|*'#'*|*@*|:*|/*|*/|'') exit 65 ;; esac
  remote_owner="${remote_path%%/*}"
  remote_repository="${remote_path#*/}"
  case "$remote_owner" in *[!A-Za-z0-9_.-]*|'') exit 65 ;; esac
  case "$remote_repository" in *[!A-Za-z0-9_.-]*|'') exit 65 ;; esac
}
require_clean() {
  [ -z "$(git status --porcelain --untracked-files=all -- . ':(exclude).galaxyssi-runtime')" ] || exit 43
}
emit_repository() {
  print_value state ready
  print_value repository_url "$(git remote get-url origin 2>/dev/null || true)"
  print_value branch "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  print_value head_commit "$(git rev-parse --verify HEAD 2>/dev/null || true)"
  if [ -z "$(git status --porcelain --untracked-files=all -- . ':(exclude).galaxyssi-runtime')" ]; then
    print_value clean true
  else
    print_value clean false
  fi
}
"""#
}

private struct AgentIOSProjectRepositoryMutationError: Error {
  var code: String
  var message: String
}
