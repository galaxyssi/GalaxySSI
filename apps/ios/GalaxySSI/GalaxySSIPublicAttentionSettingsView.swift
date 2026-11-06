import SwiftUI

struct GalaxySSIPublicAttentionSettingsView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var editing: PublicAttentionCatalog.Topic?

  private var preferences: PublicAttentionPreferences {
    store.globalAgentSettings.publicAttention ?? PublicAttentionPreferences()
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(title: t("attention_title", "Proactive attention"), leading: { GalaxySSIBackButton() },
        trailing: {
          Button {
            editing = .init(id: UUID().uuidString, group: .custom, title: "", scope: "")
          } label: {
            Image(systemName: "plus").frame(width: 44, height: 44)
          }
          .accessibilityLabel(t("attention_add_topic", "Add topic"))
        })
      List {
        Section {
          Toggle(t("attention_collect", "Monitor public topics"), isOn: Binding(
            get: { preferences.enabled }, set: { value in store.updatePublicAttention { $0.enabled = value } }))
          Toggle(t("attention_allow_paired", "Allow paired Agent for public research"), isOn: Binding(
            get: { preferences.allowPairedModel == true }, set: { value in
              store.updatePublicAttention { $0.allowPairedModel = value }
            }))
          Toggle(t("attention_allow_cloud", "Allow cloud model for public research"), isOn: Binding(
            get: { preferences.allowCloudModel }, set: { value in
              store.updatePublicAttention { $0.allowCloudModel = value }
            }))
          Picker(t("attention_alerts", "Notifications"), selection: Binding(
            get: { preferences.alertMode }, set: { value in store.updatePublicAttention { $0.alertMode = value } })) {
            Text(t("attention_filter_important", "Important")).tag(PublicAttentionAlertMode.important)
            Text(t("attention_filter_all", "All")).tag(PublicAttentionAlertMode.all)
            Text(t("attention_alert_silent", "Silent")).tag(PublicAttentionAlertMode.silent)
          }
          NavigationLink {
            GalaxySSIGlobalAgentInsightInboxView()
          } label: {
            Label(t("attention_discoveries", "Discoveries"), systemImage: "sparkles")
          }
        }
        ForEach(PublicAttentionGroup.allCases) { group in
          let topics = preferences.catalog.filter { $0.group == group }
          if !topics.isEmpty {
            Section(groupTitle(group)) {
              ForEach(topics) { definition in
                let topic = preferences.topic(definition, language: language)
                HStack {
                  Button {
                    editing = topic
                  } label: {
                    VStack(alignment: .leading, spacing: 4) {
                      Text(topic.title).foregroundColor(.primary)
                      Text(topic.scope).font(.footnote).foregroundColor(.secondary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  Toggle(topic.title, isOn: Binding(get: { topic.enabled }, set: { enabled in
                    store.updatePublicAttention { $0.setEnabled(enabled, topic: topic) }
                  }))
                  .labelsHidden()
                  .accessibilityLabel(topic.title)
                }
              }
            }
          }
        }
      }
      .listStyle(.insetGrouped)
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(item: $editing) { topic in
      GalaxySSIPublicAttentionTopicEditor(topic: topic, language: language) { edited in
        let definition = PublicAttentionCatalog.defaults.first { $0.id == edited.id }
        let localized = definition.map { PublicAttentionPreferences().topic($0, language: language) }
        store.updatePublicAttention { $0.setTopic(edited, relativeTo: localized) }
      } delete: {
        store.updatePublicAttention { $0.removeCustomTopic(topic.id) }
      }
    }
  }

  private func groupTitle(_ group: PublicAttentionGroup) -> String {
    switch group {
    case .finance: return t("attention_group_finance", "Finance")
    case .technology: return t("attention_group_technology", "Technology and products")
    case .galaxySSI: return "GalaxySSI"
    case .research: return t("attention_group_research", "Research and innovation")
    case .custom: return t("attention_group_custom", "Custom")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

private struct GalaxySSIPublicAttentionTopicEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State var topic: PublicAttentionCatalog.Topic
  let language: String
  let save: (PublicAttentionCatalog.Topic) -> Void
  let delete: () -> Void

  var body: some View {
    NavigationView {
      Form {
        TextField(t("attention_topic_name", "Topic name"), text: $topic.title)
        Section(t("attention_topic_scope", "Research scope")) {
          TextEditor(text: $topic.scope).frame(minHeight: 120)
            .accessibilityLabel(t("attention_topic_scope", "Research scope"))
        }
        if topic.group == .custom && !topic.title.isEmpty {
          Button(role: .destructive) { delete(); dismiss() } label: {
            Text(t("attention_remove_topic", "Remove topic"))
          }
        }
      }
      .navigationTitle(t("attention_edit_topic", "Edit topic"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("attention_cancel", "Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("attention_save", "Save")) { save(topic); dismiss() }
            .disabled(topic.title.trimmed().isEmpty || topic.scope.trimmed().isEmpty)
        }
      }
    }
    .navigationViewStyle(.stack)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
