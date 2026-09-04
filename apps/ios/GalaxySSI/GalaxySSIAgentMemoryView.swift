import SwiftUI

struct GalaxySSIAgentMemoryView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var searchText = ""
  @State private var filterKind: AgentMemoryKind?
  @State private var editingItem: AgentMemoryItem?
  @State private var selectedConflict: AgentMemoryConflict?
  @State private var showingNewMemory = false
  @State private var statusText = ""

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.agent_memory.title", "Personal Memory"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Button {
            showingNewMemory = true
          } label: {
            Image(systemName: "plus")
              .font(.system(size: 21, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
          }
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          AgentMemoryHeroView(
            title: t("galaxyssi.agent_memory.hero_title", "Encrypted Agent Memory"),
            subtitle: String(
              format: t(
                "galaxyssi.agent_memory.hero_subtitle",
                "%d active / %d conflicts / %d previous versions"
              ),
              snapshot.activeCount,
              snapshot.conflicts.count,
              snapshot.historyCount
            ),
            systemImage: "brain",
            tint: .purple,
            badge: store.agentSafetySettings.memoryCapture
              ? t("galaxyssi.status.on", "On")
              : t("galaxyssi.status.off", "Off")
          )

          VStack(spacing: 8) {
            AgentMemoryToggleRow(
              title: t("galaxyssi.on_device_agent.memory_capture", "Memory Capture"),
              subtitle: t(
                "galaxyssi.on_device_agent.memory_capture_subtitle",
                "Allow explicit notes to update encrypted long-term memory; task context stays session-scoped"
              ),
              systemImage: "lock.shield",
              tint: .galaxySSIAccent,
              isOn: store.agentSafetySettings.memoryCapture
            ) {
              store.updateAgentSafetySettings { $0.memoryCapture.toggle() }
            }
            AgentMemorySearchFilterRow(
              searchText: $searchText,
              filterTitle: filterKind.map(kindLabel) ?? t("galaxyssi.agent_memory.filter_all", "All"),
              placeholder: t("galaxyssi.agent_memory.search_placeholder", "Search saved memory")
            ) {
              filterMenu
            }
            if !statusText.isEmpty {
              Text(statusText)
                .font(.system(size: 12))
                .foregroundColor(.galaxySSITextSecondary)
                .padding(.horizontal, 4)
            }
          }

          sectionTitle(t("galaxyssi.agent_memory.section_conflicts", "Needs Review"))
          if filteredSnapshot.conflicts.isEmpty {
            AgentMemoryStatusRow(
              title: t("galaxyssi.agent_memory.no_conflicts", "Memory is consistent"),
              subtitle: t(
                "galaxyssi.agent_memory.no_conflicts_subtitle",
                "No unresolved facts or preference conflicts"
              ),
              systemImage: "shield",
              tint: .galaxySSIAccent,
              badge: ""
            )
          } else {
            VStack(spacing: 8) {
              ForEach(filteredSnapshot.conflicts) { conflict in
                AgentMemoryActionRow(
                  title: conflict.key.ifBlank(kindLabel(conflict.kind)),
                  subtitle: String(
                    format: t("galaxyssi.agent_memory.conflict_subtitle", "%@ / %d versions disagree"),
                    kindLabel(conflict.kind),
                    conflict.candidates.count
                  ),
                  systemImage: "exclamationmark.shield",
                  tint: .orange,
                  badge: t("galaxyssi.agent_memory.review", "Review")
                ) {
                  selectedConflict = conflict
                }
              }
            }
          }

          sectionTitle(t("galaxyssi.agent_memory.section_saved", "Saved Memory"))
          if filteredSnapshot.activeItems.isEmpty {
            AgentMemoryStatusRow(
              title: t("galaxyssi.agent_memory.empty", "No saved memory"),
              subtitle: t(
                "galaxyssi.agent_memory.empty_subtitle",
                "Use an explicit remember command to add long-term memory"
              ),
              systemImage: "brain",
              tint: .purple,
              badge: ""
            )
          } else {
            VStack(spacing: 8) {
              ForEach(filteredSnapshot.activeItems) { item in
                AgentMemoryActionRow(
                  title: compact(item.value),
                  subtitle: itemSubtitle(item),
                  systemImage: item.important ? "pin.fill" : "brain",
                  tint: item.important ? .orange : .purple,
                  badge: item.important
                    ? t("galaxyssi.agent_memory.pinned", "Pinned")
                    : t("galaxyssi.common.edit", "Edit")
                ) {
                  editingItem = item
                }
              }
            }
          }

          if !filteredSnapshot.historyItems.isEmpty {
            sectionTitle(t("galaxyssi.agent_memory.section_history", "Previous Versions"))
            VStack(spacing: 8) {
              ForEach(Array(filteredSnapshot.historyItems.prefix(20))) { item in
                AgentMemoryStatusRow(
                  title: compact(item.value),
                  subtitle: historySubtitle(item),
                  systemImage: "clock.arrow.circlepath",
                  tint: .blue,
                  badge: ""
                )
              }
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(isPresented: $showingNewMemory) {
      AgentMemoryEditorSheet(item: nil) { message in
        statusText = message
      }
      .environmentObject(store)
    }
    .sheet(item: $editingItem) { item in
      AgentMemoryEditorSheet(item: item) { message in
        statusText = message
      }
      .environmentObject(store)
    }
    .sheet(item: $selectedConflict) { conflict in
      AgentMemoryConflictSheet(conflict: conflict) { message in
        statusText = message
      }
      .environmentObject(store)
    }
  }

  private var snapshot: AgentMemorySnapshot {
    store.agentMemorySnapshot()
  }

  private var filteredSnapshot: AgentMemorySnapshot {
    AgentMemorySnapshot(
      activeItems: filteredItems(snapshot.activeItems),
      conflicts: snapshot.conflicts.filter { conflict in
        if let filterKind, conflict.kind != filterKind { return false }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return conflict.key.localizedCaseInsensitiveContains(query) ||
          conflict.candidates.contains { memoryMatches($0, query: query) }
      },
      historyItems: filteredItems(snapshot.historyItems)
    )
  }

  private var filterMenu: some View {
    Menu {
      Button(t("galaxyssi.agent_memory.filter_all", "All")) {
        filterKind = nil
      }
      ForEach(AgentMemoryKind.allCases) { kind in
        Button(kindLabel(kind)) {
          filterKind = kind
        }
      }
    } label: {
      HStack(spacing: 4) {
        Text(filterKind.map(kindLabel) ?? t("galaxyssi.agent_memory.filter_all", "All"))
          .font(.system(size: 12, weight: .semibold))
        Image(systemName: "chevron.down")
          .font(.system(size: 10, weight: .bold))
      }
      .foregroundColor(.galaxySSIAccent)
      .padding(.horizontal, 9)
      .frame(minHeight: 30)
      .background(Color.galaxySSIAccent.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private func filteredItems(_ items: [AgentMemoryItem]) -> [AgentMemoryItem] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return items.filter { item in
      if let filterKind, item.kind != filterKind { return false }
      if query.isEmpty { return true }
      return memoryMatches(item, query: query)
    }
  }

  private func memoryMatches(_ item: AgentMemoryItem, query: String) -> Bool {
    item.value.localizedCaseInsensitiveContains(query) ||
      item.key.localizedCaseInsensitiveContains(query) ||
      item.source.localizedCaseInsensitiveContains(query) ||
      kindLabel(item.kind).localizedCaseInsensitiveContains(query)
  }

  private func itemSubtitle(_ item: AgentMemoryItem) -> String {
    String(
      format: t("galaxyssi.agent_memory.item_subtitle", "%@ / v%d / %@"),
      kindLabel(item.kind),
      item.version,
      item.key.ifBlank(t("galaxyssi.agent_memory.key_none", "Unkeyed"))
    )
  }

  private func historySubtitle(_ item: AgentMemoryItem) -> String {
    String(
      format: t("galaxyssi.agent_memory.history_subtitle", "%@ / v%d / %@"),
      kindLabel(item.kind),
      item.version,
      sourceLabel(item.source)
    )
  }

  private func kindLabel(_ kind: AgentMemoryKind) -> String {
    switch kind {
    case .identity:
      return t("galaxyssi.agent_memory.kind_identity", "Profile")
    case .contact:
      return t("galaxyssi.agent_memory.kind_contact", "Contact")
    case .task:
      return t("galaxyssi.agent_memory.kind_task", "Task")
    case .preference:
      return t("galaxyssi.agent_memory.kind_preference", "Preference")
    case .workflow:
      return t("galaxyssi.agent_memory.kind_workflow", "Workflow")
    case .knowledge:
      return t("galaxyssi.agent_memory.kind_knowledge", "Knowledge")
    case .safety:
      return t("galaxyssi.agent_memory.kind_safety", "Security")
    }
  }

  private func sourceLabel(_ source: String) -> String {
    switch source {
    case "explicit_save":
      return t("galaxyssi.agent_memory.source_explicit", "Explicit save")
    case "memory_edit":
      return t("galaxyssi.agent_memory.source_edit", "Edited")
    case "memory_conflict_selection", "memory_conflict_merge":
      return t("galaxyssi.agent_memory.source_resolution", "Conflict resolution")
    default:
      return t("galaxyssi.agent_memory.source_agent", "Agent")
    }
  }

  private func compact(_ value: String) -> String {
    String(value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(100))
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentMemoryEditorSheet: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: GalaxySSIStore
  let item: AgentMemoryItem?
  var onStatus: (String) -> Void
  @State private var kind: AgentMemoryKind
  @State private var value: String
  @State private var key: String
  @State private var important: Bool

  init(item: AgentMemoryItem?, onStatus: @escaping (String) -> Void) {
    self.item = item
    self.onStatus = onStatus
    _kind = State(initialValue: item?.kind ?? .knowledge)
    _value = State(initialValue: item?.value ?? "")
    _key = State(initialValue: item?.key ?? "")
    _important = State(initialValue: item?.important ?? false)
  }

  var body: some View {
    NavigationView {
      Form {
        Section(t("galaxyssi.agent_memory.editor_section", "Memory")) {
          Picker(t("galaxyssi.agent_memory.editor_kind", "Kind"), selection: $kind) {
            ForEach(AgentMemoryKind.allCases) { kind in
              Text(kindLabel(kind)).tag(kind)
            }
          }
          .disabled(item != nil)
          TextField(t("galaxyssi.agent_memory.editor_key", "Stable key"), text: $key)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
          TextEditor(text: $value)
            .frame(minHeight: 120)
          Toggle(t("galaxyssi.agent_memory.pinned", "Pinned"), isOn: $important)
        }
        if let item {
          Section(t("galaxyssi.agent_memory.editor_metadata", "Metadata")) {
            Text(String(format: t("galaxyssi.agent_memory.item_subtitle", "%@ / v%d / %@"), kindLabel(item.kind), item.version, item.key.ifBlank(t("galaxyssi.agent_memory.key_none", "Unkeyed"))))
              .font(.caption)
              .foregroundColor(.secondary)
            Button(role: .destructive) {
              if store.deleteAgentMemory(id: item.id) {
                onStatus(t("galaxyssi.agent_memory.deleted", "Memory deleted"))
              }
              dismiss()
            } label: {
              Label(t("galaxyssi.agent_memory.delete_title", "Delete Memory"), systemImage: "trash")
            }
          }
        }
      }
      .navigationTitle(item == nil ? t("galaxyssi.agent_memory.new_title", "Add Memory") : t("galaxyssi.agent_memory.edit_title", "Edit Memory"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.cancel", "Cancel")) {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("galaxyssi.common.save", "Save")) {
            save()
          }
          .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  private func save() {
    let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    if let item {
      if cleanValue == item.value && cleanKey == item.key {
        _ = store.setAgentMemoryImportant(id: item.id, important: important)
      } else {
        let result = store.updateAgentMemory(id: item.id, value: cleanValue, key: cleanKey)
        _ = store.setAgentMemoryImportant(id: result?.item?.id ?? item.id, important: important)
      }
      onStatus(t("galaxyssi.agent_memory.updated", "Memory updated"))
    } else {
      var memory = AgentMemoryItem(
        kind: kind,
        value: cleanValue,
        source: "explicit_save",
        key: cleanKey,
        important: important,
        lastConfirmedAtMillis: AgentMemoryClock.nowMillis()
      )
      if memory.key.isEmpty {
        memory.key = AgentMemoryKeyPolicy.inferKey(from: cleanValue)
      }
      _ = store.rememberAgentMemory(memory)
      onStatus(t("galaxyssi.agent_memory.updated", "Memory updated"))
    }
    dismiss()
  }

  private func kindLabel(_ kind: AgentMemoryKind) -> String {
    switch kind {
    case .identity:
      return t("galaxyssi.agent_memory.kind_identity", "Profile")
    case .contact:
      return t("galaxyssi.agent_memory.kind_contact", "Contact")
    case .task:
      return t("galaxyssi.agent_memory.kind_task", "Task")
    case .preference:
      return t("galaxyssi.agent_memory.kind_preference", "Preference")
    case .workflow:
      return t("galaxyssi.agent_memory.kind_workflow", "Workflow")
    case .knowledge:
      return t("galaxyssi.agent_memory.kind_knowledge", "Knowledge")
    case .safety:
      return t("galaxyssi.agent_memory.kind_safety", "Security")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentMemoryConflictSheet: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: GalaxySSIStore
  let conflict: AgentMemoryConflict
  var onStatus: (String) -> Void
  @State private var mergedValue: String

  init(conflict: AgentMemoryConflict, onStatus: @escaping (String) -> Void) {
    self.conflict = conflict
    self.onStatus = onStatus
    _mergedValue = State(initialValue: conflict.candidates.map(\.value).joined(separator: "\n"))
  }

  var body: some View {
    NavigationView {
      Form {
        Section(t("galaxyssi.agent_memory.conflict_title", "Memory Conflict")) {
          Text(String(format: t("galaxyssi.agent_memory.conflict_subtitle", "%@ / %d versions disagree"), kindLabel(conflict.kind), conflict.candidates.count))
            .font(.caption)
            .foregroundColor(.secondary)
          ForEach(conflict.candidates) { candidate in
            Button {
              resolve(selectedItemId: candidate.id, mergedValue: nil)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(String(format: t("galaxyssi.agent_memory.use_candidate", "Use v%d: %@"), candidate.version, String(candidate.value.prefix(80))))
                Text(candidate.key.ifBlank(t("galaxyssi.agent_memory.key_none", "Unkeyed")))
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        }
        Section(t("galaxyssi.agent_memory.merge_title", "Merge Memory")) {
          TextEditor(text: $mergedValue)
            .frame(minHeight: 140)
          Button {
            resolve(selectedItemId: conflict.candidates.last?.id ?? "", mergedValue: mergedValue)
          } label: {
            Label(t("galaxyssi.agent_memory.merge_values", "Merge values"), systemImage: "arrow.triangle.branch")
          }
          .disabled(conflict.candidates.isEmpty || mergedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .navigationTitle(t("galaxyssi.agent_memory.review", "Review"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.cancel", "Cancel")) {
            dismiss()
          }
        }
      }
    }
  }

  private func resolve(selectedItemId: String, mergedValue: String?) {
    guard !selectedItemId.isEmpty else { return }
    if store.resolveAgentMemoryConflict(groupId: conflict.groupId, selectedItemId: selectedItemId, mergedValue: mergedValue) != nil {
      onStatus(t("galaxyssi.agent_memory.merge_saved", "Memory conflict resolved"))
    } else {
      onStatus(t("galaxyssi.agent_memory.conflict_resolution_failed", "Memory was not changed"))
    }
    dismiss()
  }

  private func kindLabel(_ kind: AgentMemoryKind) -> String {
    switch kind {
    case .identity:
      return t("galaxyssi.agent_memory.kind_identity", "Profile")
    case .contact:
      return t("galaxyssi.agent_memory.kind_contact", "Contact")
    case .task:
      return t("galaxyssi.agent_memory.kind_task", "Task")
    case .preference:
      return t("galaxyssi.agent_memory.kind_preference", "Preference")
    case .workflow:
      return t("galaxyssi.agent_memory.kind_workflow", "Workflow")
    case .knowledge:
      return t("galaxyssi.agent_memory.kind_knowledge", "Knowledge")
    case .safety:
      return t("galaxyssi.agent_memory.kind_safety", "Security")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentMemoryHeroView: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(subtitle)
          .font(.system(size: 14))
          .foregroundColor(.galaxySSITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

private struct AgentMemorySearchFilterRow<Filter: View>: View {
  @Binding var searchText: String
  var filterTitle: String
  var placeholder: String
  let filter: Filter

  init(
    searchText: Binding<String>,
    filterTitle: String,
    placeholder: String,
    @ViewBuilder filter: () -> Filter
  ) {
    _searchText = searchText
    self.filterTitle = filterTitle
    self.placeholder = placeholder
    self.filter = filter()
  }

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundColor(.galaxySSITextSecondary)
      TextField(placeholder, text: $searchText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
      filter
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 48)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AgentMemoryToggleRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var isOn: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      AgentMemoryRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: isOn ? "ON" : "OFF",
        showsDisclosure: false
      )
    }
    .buttonStyle(.plain)
  }
}

private struct AgentMemoryActionRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      AgentMemoryRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsDisclosure: true
      )
    }
    .buttonStyle(.plain)
  }
}

private struct AgentMemoryStatusRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    AgentMemoryRowContent(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: badge,
      showsDisclosure: false
    )
  }
}

private struct AgentMemoryRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var showsDisclosure: Bool

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(2)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      if !badge.isEmpty {
        Text(badge)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.65)
          .padding(.horizontal, 8)
          .frame(minHeight: 28)
          .background(tint.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      if showsDisclosure {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
