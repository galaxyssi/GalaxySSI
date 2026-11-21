import SwiftUI
import UIKit

/// Capability stays in this process; URLs and external apps cannot inject an atlas prompt.
@MainActor
final class GalaxySSIHealthAtlasAgentHandoff {
  struct Request {
    let owner: String
    let conversation: String
    let prompt: String
    let created: TimeInterval
  }
  static let shared = GalaxySSIHealthAtlasAgentHandoff()
  private var pending: [UUID: Request] = [:]
  func prepare(owner: String, conversation: String, prompt: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> UUID? {
    pending = pending.filter { now >= $0.value.created && now - $0.value.created <= 120 }
    guard !owner.isEmpty, !conversation.isEmpty, !prompt.isEmpty, prompt.utf8.count <= 32_000, pending.count < 8 else { return nil }
    let token = UUID()
    pending[token] = Request(owner: owner, conversation: conversation, prompt: prompt, created: now)
    return token
  }
  func consume(_ token: UUID, owner: String, conversation: String,
               now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Request? {
    guard let request = pending.removeValue(forKey: token), request.owner == owner, request.conversation == conversation,
      now >= request.created, now - request.created <= 120 else { return nil }
    return request
  }
  func discard(_ token: UUID) { pending.removeValue(forKey: token) }
}

enum GalaxySSIHealthAtlasQuestion {
  static func build(atlas: GalaxySSIHealthAtlas, entry: GalaxySSIHealthAtlas.Entry?,
                    selection: GalaxySSIHealthAtlasState.Selection, research: Bool, language: String) -> String {
    func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
    guard let entry else { return t("ask_whole_context") }
    let model = atlas.model(entry)
    var prompt = String(format: t("ask_context"), GalaxySSIHealthAtlasText.get(entry.name, language),
      GalaxySSIHealthAtlasText.get(entry.description, language), GalaxySSIHealthAtlasText.get(model.title, language), model.source.absoluteString)
    #if GALAXYSSI_ATLAS_PHYSIOLOGY
    let physiology = ((!research && selection.tab == .simulation) || (research && selection.research == .physiology))
      ? GalaxySSIHealthAtlasPhysiology.resolved(entry.id, inputs: selection.physiologyInputs,
          legacyVentilation: ["lungs", "respiratory"].contains(entry.id) ? [selection.simulation.first, selection.simulation.second] : nil) : nil
    let hasAssociatedPhysiology = physiology != nil
    if let physiology {
      prompt += "\n" + GalaxySSIHealthAtlasPhysiologyText.context(physiology, language: language)
    }
    #else
    let hasAssociatedPhysiology = false
    #endif
    if research {
      switch selection.research {
      case .physiology:
        prompt += "\n" + t("teaching_note") + "\n" + t("process_note")
        if !hasAssociatedPhysiology, ["heart", "cardio", "lungs", "respiratory"].contains(entry.id) {
          let cardiac = ["heart", "cardio"].contains(entry.id)
          prompt += "\n" + t(cardiac ? "cardiac_formula" : "ventilation_formula")
          prompt += "\n" + t(cardiac ? "heart_rate" : "rate") + ": \(Int(selection.simulation.first))"
          prompt += "\n" + t(cardiac ? "stroke_volume" : "tidal") + ": \(Int(selection.simulation.second)) mL"
        } else if !hasAssociatedPhysiology { prompt += "\n" + t("qualitative_note") }
      case .drugs:
        prompt += "\n" + t("drug_note") + "\n" + t("elimination_assumptions") + "\n" + t("elimination_formula")
        prompt += "\n" + String(format: t("elimination_summary"), Int64(selection.elimination.halfLife), Int64(selection.elimination.elapsed),
          String(format: "%.1f", selection.elimination.percent(at: selection.elimination.elapsed)))
        prompt += "\nhttps://openstax.org/books/pharmacology/pages/2-2-pharmacokinetics-and-pharmacodynamics"
        prompt += "\nhttps://pharmacologyeducation.org/clinical-pharmacokinetics/"
      case .aging:
        prompt += "\n" + t("aging_scope") + "\n" + t("aging_evidence") + "\nhttps://pubmed.ncbi.nlm.nih.gov/36599349/"
      }
    }
    return prompt
  }
}

@MainActor
struct GalaxySSIHealthAtlasAsk: View {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry?
  let selection: GalaxySSIHealthAtlasState.Selection
  var includesResearch = false
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @State private var preview: String?
  @State private var token: UUID?
  @State private var failed = false
  private var isPreviewPresented: Binding<Bool> { Binding(get: { preview != nil }, set: { if !$0 { preview = nil } }) }
  var body: some View {
    Button(t("ask")) {
      preview = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: entry, selection: selection, research: includesResearch, language: language)
    }.frame(minHeight: 44)
    .sheet(isPresented: isPreviewPresented) {
      NavigationView {
        ScrollView { Text(preview ?? "").frame(maxWidth: .infinity, alignment: .leading).padding() }
          .navigationTitle(t("ask_ready")).navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button { preview = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel(GalaxySSILocalization.string("galaxyssi.cancel", fallback: "Cancel", language: language))
            }
            ToolbarItem(placement: .confirmationAction) { Button(t("ask"), action: open).disabled(scene != .active) }
          }
      }.navigationViewStyle(.stack)
    }
    .background(NavigationLink(isActive: Binding(get: { token != nil }, set: { active in
      if !active { if let token { GalaxySSIHealthAtlasAgentHandoff.shared.discard(token) }; token = nil }
    })) {
      if let token { AgentHomeView(atlasHandoffToken: token) }
    } label: { EmptyView() }.hidden())
    .alert(t("load_error"), isPresented: $failed) { Button(t("retry")) { failed = false } }
    .onChange(of: scene) { value in if value != .active { preview = nil } }
  }
  private func open() {
    guard scene == .active, UIApplication.shared.isProtectedDataAvailable, let prompt = preview,
      !store.profile.identityFingerprint.isBlank else { failed = true; return }
    let session = store.createAgentSession(title: entry.map { GalaxySSIHealthAtlasText.get($0.name, language) } ?? t("whole"), globalTopicKey: "body-atlas")
    guard store.switchAgentSession(session.id),
      let ticket = GalaxySSIHealthAtlasAgentHandoff.shared.prepare(owner: store.profile.identityFingerprint, conversation: session.id, prompt: prompt)
    else { failed = true; return }
    preview = nil
    // Let the confirmation sheet finish dismissing before pushing the existing Agent page.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      guard scene == .active, store.activeAgentConversationId == session.id else {
        GalaxySSIHealthAtlasAgentHandoff.shared.discard(ticket); return
      }
      token = ticket
    }
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}

extension AgentHomeView {
  func consumeHealthAtlasHandoff() {
    guard let atlasHandoffToken, homeVisible, scenePhase == .active, UIApplication.shared.isProtectedDataAvailable,
      store.agentSession(id: store.activeAgentConversationId)?.globalTopicKey == "body-atlas",
      let request = GalaxySSIHealthAtlasAgentHandoff.shared.consume(atlasHandoffToken,
        owner: store.profile.identityFingerprint, conversation: store.activeAgentConversationId) else { return }
    Task { @MainActor in
      guard homeVisible, scenePhase == .active, UIApplication.shared.isProtectedDataAvailable,
        request.owner == store.profile.identityFingerprint, request.conversation == store.activeAgentConversationId else { return }
      attachments.wipeSensitive()
      draft = ""
      let sent = await coordinator.send(request.prompt, to: contact, attachments: [],
        requiredAgentConversationID: request.conversation, requestKind: .conversation)
      if !sent, request.owner == store.profile.identityFingerprint, request.conversation == store.activeAgentConversationId {
        // A failed public-only handoff is recoverable without replaying the capability or attaching composer files.
        draft = request.prompt
        attachmentError = GalaxySSIHealthAtlasText.get("health_atlas_retry", interfaceLanguage)
      }
    }
  }
}
