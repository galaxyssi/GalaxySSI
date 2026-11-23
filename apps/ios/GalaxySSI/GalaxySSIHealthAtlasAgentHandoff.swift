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
    guard research || selection.tab != .values else { return "" }
    func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
    #if GALAXYSSI_ATLAS_AGENT_CONTEXT
    let screen: GalaxySSIHealthAtlasAgentContext.Screen
    if research {
      switch selection.research { case .physiology: screen = .physiology; case .drugs: screen = .drugs; case .aging: screen = .aging }
    } else {
      switch selection.tab { case .structure: screen = .structure; case .function: screen = .function; case .values: screen = .values; case .simulation: screen = .simulation }
    }
    let anatomy = entry.map { item in
      GalaxySSIHealthAtlasAgentContext.Anatomy(id: item.id, name: GalaxySSIHealthAtlasText.get(item.name, language),
        description: GalaxySSIHealthAtlasText.get(item.description, language),
        mechanism: GalaxySSIHealthAtlasText.get(atlas.model(item).title, language),
        stages: atlas.model(item).stages.map { GalaxySSIHealthAtlasText.get($0, language) }, source: atlas.model(item).source,
        tissueContext: atlas.tissueContext(item, language: language),
        valveContext: GalaxySSIHealthAtlasHeartSection.context(item.id, stage: selection.simulation.stage, atlas: atlas, language: language))
    }
    var quantitative: GalaxySSIHealthAtlasAgentContext.Quantitative? = nil
    #if GALAXYSSI_ATLAS_PHYSIOLOGY
    if let entry, screen.includesPhysiology,
       let model = GalaxySSIHealthAtlasPhysiology.resolved(entry.id, inputs: selection.physiologyInputs,
         legacyVentilation: ["lungs", "respiratory"].contains(entry.id) ? [selection.simulation.first, selection.simulation.second] : nil) {
      quantitative = .init(entryID: entry.id, context: GalaxySSIHealthAtlasPhysiologyText.context(model, language: language))
    }
    #endif
    let simulation = entry.flatMap { item in
      GalaxySSIHealthAtlasAgentContext.Simulation(entryID: item.id, phase: selection.simulation.phase,
        first: selection.simulation.first, second: selection.simulation.second)
    }
    let elimination = GalaxySSIHealthAtlasAgentContext.Elimination(halfLife: selection.elimination.halfLife, elapsed: selection.elimination.elapsed)
    let illustration = entry.flatMap { item in
      atlas.plate(for: item.id, viewKey: selection.artworkView).flatMap { plate in
        GalaxySSIHealthAtlasAgentContext.Illustration(entryID: item.id,
          caption: atlas.caption(plate, selected: item, language: language), source: plate.source,
          featureContext: plate.featureContext(language: language))
      }
    }
    return GalaxySSIHealthAtlasAgentContext.prompt(anatomy: anatomy, screen: screen, simulation: simulation,
      quantitative: quantitative, elimination: elimination, illustration: illustration,
      drugs: GalaxySSIHealthAtlasDrugState.restore(selection.drugInputs),
      aging: selection.aging, language: language,
      locale: GalaxySSILocalization.interfaceLocale(language: language), text: t) ?? ""
    #else
    guard let entry else { return t("ask_whole_context") }
    let model = atlas.model(entry)
    var prompt = String(format: t("ask_context"), GalaxySSIHealthAtlasText.get(entry.name, language),
      GalaxySSIHealthAtlasText.get(entry.description, language), GalaxySSIHealthAtlasText.get(model.title, language), model.source.absoluteString)
    if entry.kind == .tissue { prompt += "\n" + atlas.tissueContext(entry, language: language).joined(separator: "\n") }
    if research || selection.tab != .values, let plate = atlas.plate(for: entry.id, viewKey: selection.artworkView) {
      prompt += "\n" + atlas.caption(plate, selected: entry, language: language) + "\n" + t("art_note")
      if let source = plate.source { prompt += "\n" + source.absoluteString }
      if let features = plate.featureContext(language: language) { prompt += "\n" + features }
    }
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
    if ((!research && selection.tab == .simulation) || (research && selection.research == .physiology)),
       let counts = GalaxySSIHealthAtlasGermline.counts(entry.id, stage: selection.simulation.stage) {
      prompt += "\n" + GalaxySSIHealthAtlasGermline.context(counts, language: language)
    }
    if ((!research && selection.tab == .simulation) || (research && selection.research == .physiology)),
       let context = GalaxySSIHealthAtlasHeartSection.context(entry.id, stage: selection.simulation.stage, atlas: atlas, language: language) {
      prompt += "\n" + context
    }
    if entry.id == GalaxySSIHealthAtlasFiltrationStage.owner,
       ((!research && selection.tab == .simulation) || (research && selection.research == .physiology)) {
      prompt += "\n" + t("podocyte_scope")
    }
    if entry.id == GalaxySSIHealthAtlas.ImmunePack.phagocytosisOwner,
       ((!research && selection.tab == .simulation) || (research && selection.research == .physiology)) {
      prompt += "\n" + t("phagocytosis_scope")
    }
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
        if let drugs = GalaxySSIHealthAtlasDrugState.restore(selection.drugInputs), drugs.mode == .two {
          prompt += "\n" + t("drug_models") + "\n" +
            drugs.distribution.context(locale: GalaxySSILocalization.interfaceLocale(language: language), text: t)
        } else {
        prompt += "\n" + t("drug_note") + "\n" + t("elimination_assumptions") + "\n" + t("elimination_formula")
        prompt += "\n" + String(format: t("elimination_summary"), Int64(selection.elimination.halfLife), Int64(selection.elimination.elapsed),
          String(format: "%.1f", selection.elimination.percent(at: selection.elimination.elapsed)))
        }
        prompt += "\nhttps://openstax.org/books/pharmacology/pages/2-2-pharmacokinetics-and-pharmacodynamics"
        prompt += "\nhttps://pharmacologyeducation.org/clinical-pharmacokinetics/"
      case .aging:
        prompt += "\n" + GalaxySSIHealthAtlasAgingSelection.resolved(selection.aging, entryID: entry.id).context(language: language)
        prompt += "\n" + t("aging_evidence") + "\n" + GalaxySSIHealthAtlasAgingTopic.source.absoluteString
      }
    }
    return prompt
    #endif
  }
}

@MainActor
struct GalaxySSIHealthAtlasAsk: View {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry?
  let selection: GalaxySSIHealthAtlasState.Selection
  var includesResearch = false
  var selectionSnapshot: (() -> GalaxySSIHealthAtlasState.Selection)? = nil
  var onPreviewStateChange: ((Bool) -> Void)? = nil
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @State private var preview: String?
  @State private var token: UUID?
  @State private var failed = false
  private var isPreviewPresented: Binding<Bool> { Binding(get: { preview != nil }, set: { if !$0 { preview = nil } }) }
  var body: some View {
    Button(t("ask")) {
      onPreviewStateChange?(true)
      let question = GalaxySSIHealthAtlasQuestion.build(atlas: atlas, entry: entry, selection: selectionSnapshot?() ?? selection,
        research: includesResearch, language: language)
      if question.isEmpty { onPreviewStateChange?(false) } else { preview = question }
    }.frame(maxWidth: .infinity, minHeight: 48).disabled(scene != .active)
    .buttonStyle(GalaxySSIHealthCommandStyle())
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
    .onChange(of: preview != nil) { onPreviewStateChange?($0) }
    .onDisappear { onPreviewStateChange?(false) }
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
