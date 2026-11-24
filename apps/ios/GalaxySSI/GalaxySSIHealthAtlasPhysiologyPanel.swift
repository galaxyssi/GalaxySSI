import SwiftUI

struct GalaxySSIHealthAtlasPhysiologyPanel: View {
  let entryID: String
  @Binding var inputs: [Int]?
  let language: String
  var legacyVentilation: [Double]? = nil
  private var model: GalaxySSIHealthAtlasPhysiology? {
    GalaxySSIHealthAtlasPhysiology.resolved(entryID, inputs: inputs, legacyVentilation: legacyVentilation)
  }
  var body: some View {
    if let model {
      VStack(alignment: .leading, spacing: 14) {
        Text(t("model_" + model.kind.rawValue)).font(.headline)
        Text(t("model_synthetic")).font(.footnote).foregroundColor(.secondary)
        Text(GalaxySSIHealthAtlasPhysiologyText.result(model, language: language)).font(.title3).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("atlas-physiology-output")
        Text(GalaxySSIHealthAtlasPhysiologyText.companion(model, language: language)).font(.subheadline).foregroundColor(.secondary)
          .accessibilityIdentifier("atlas-physiology-companion")
        if let amounts = model.renalAmounts { renalBalance(amounts) }
        if let ear = model.middleEar { GalaxySSIHealthAtlasMiddleEarView(model: ear, language: language) }
        if model.kind == .alveolarSurface { GalaxySSIHealthAtlasAlveolarSurfaceView(model: model, language: language) }
        if model.kind == .villusArea {
          GalaxySSIHealthAtlasVillusAreaView(model: model, language: language)
          Text(t("gut_section_area_views")).font(.footnote).foregroundColor(.secondary)
        }
        if model.kind.hasMaterialResponse {
          GalaxySSIHealthAtlasMaterialResponseView(model: model, language: language)
          Text(GalaxySSIHealthAtlasMaterialResponseView.description(model.kind, language: language))
            .font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if let forces = model.elbowForces { GalaxySSIHealthAtlasElbowView(forces: forces, language: language) }
        if let flow = model.vesselFlow { GalaxySSIHealthAtlasVesselFlowView(flow: flow, language: language) }
        if let eye = model.eyeOptics {
          GalaxySSIHealthAtlasEyeOpticsView(eye: eye, language: language)
          Button {
            inputs = model.changing(1, to: eye.targetPowerSteps)?.inputs
          } label: {
            Label(t("eye_match_plane"), systemImage: "scope").frame(minHeight: 44)
          }.accessibilityIdentifier("atlas-eye-match-plane")
        }
        if model.kind != .photonCapture && model.kind != .alveolarSurface && model.kind != .villusArea && !model.kind.hasMaterialResponse { chartAndAxis(model) }
        ForEach(Array(model.kind.inputs.enumerated()), id: \.offset) { index, spec in
          VStack(alignment: .leading, spacing: 4) {
            Text(GalaxySSIHealthAtlasPhysiologyText.input(model, index: index, language: language))
              .fixedSize(horizontal: false, vertical: true)
            Slider(value: binding(index, model: model), in: Double(spec.range.lowerBound)...Double(spec.range.upperBound), step: 1)
              .accessibilityIdentifier("atlas-physiology-" + spec.key)
              .accessibilityLabel(t(spec.key))
              .accessibilityValue(GalaxySSIHealthAtlasPhysiologyText.inputNumber(model.input(index), key: spec.key, language: language) +
                (spec.unit.isEmpty ? "" : " " + GalaxySSIHealthAtlasPhysiologyText.displayUnit(spec.unit, language: language)))
          }
        }
        if model.kind == .photonCapture || model.kind == .alveolarSurface || model.kind == .villusArea || model.kind.hasMaterialResponse { chartAndAxis(model) }
        Button { inputs = GalaxySSIHealthAtlasPhysiology(kind: model.kind).inputs } label: {
          Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
        }.accessibilityLabel(t("reset")).help(t("reset"))
          .accessibilityIdentifier("atlas-physiology-reset")
        Text(t("model_" + model.kind.rawValue + "_formula")).font(.footnote)
        Text(t("model_" + model.kind.rawValue + "_scope")).font(.footnote).foregroundColor(.secondary)
        ForEach(Array(model.kind.sources.enumerated()), id: \.offset) { index, source in
          Link(GalaxySSIHealthAtlasPhysiologyText.sourceTitle(model.kind, index: index, language: language), destination: source)
            .frame(minHeight: 44)
        }
      }
      .onAppear { inputs = model.inputs }
    }
  }
  private func chartAndAxis(_ model: GalaxySSIHealthAtlasPhysiology) -> some View {
    let spec = model.kind.inputs[model.kind.axis]
    return Group {
      chart(model).accessibilityIdentifier("atlas-physiology-curve")
      Text(spec.unit.isEmpty ? t(spec.key) : String(format: t("model_axis"), t(spec.key), GalaxySSIHealthAtlasPhysiologyText.displayUnit(spec.unit, language: language)))
        .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
  private func binding(_ index: Int, model: GalaxySSIHealthAtlasPhysiology) -> Binding<Double> {
    Binding(get: {
      guard let latest = self.model, latest.kind == model.kind, latest.inputs.indices.contains(index) else {
        return Double(model.inputs[index])
      }
      return Double(latest.inputs[index])
    }, set: { value in
      let range = model.kind.inputs[index].range
      guard value.isFinite, value >= Double(range.lowerBound), value <= Double(range.upperBound),
        let updated = self.model?.changing(index, to: Int(value.rounded())) else { return }
      inputs = updated.inputs
    })
  }
  private func renalBalance(_ amounts: GalaxySSIHealthAtlasRenalAmounts) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(GalaxySSIHealthAtlasText.get("health_atlas_renal_balance_title", language)).font(.headline)
      ForEach(0..<4) { index in
        VStack(alignment: .leading, spacing: 4) {
          Text(GalaxySSIHealthAtlasPhysiologyText.renalTransfer(amounts, index: index, language: language)).bold()
            .fixedSize(horizontal: false, vertical: true)
          HStack(alignment: .center, spacing: 8) {
            Text(GalaxySSIHealthAtlasText.get(index == 3 ? "health_atlas_renal_lumen" : "health_atlas_renal_blood", language))
              .frame(maxWidth: .infinity)
            Image(systemName: index == 1 ? "arrow.left" : "arrow.right")
              .frame(width: 32, height: 32).opacity(amounts.transfers[index] == 0 ? 0.2 : 1).accessibilityHidden(true)
            Text(GalaxySSIHealthAtlasText.get(index == 3 ? "health_atlas_renal_urine" : "health_atlas_renal_lumen", language))
              .frame(maxWidth: .infinity)
          }.font(.caption).accessibilityElement(children: .ignore)
            .accessibilityLabel(GalaxySSIHealthAtlasPhysiologyText.renalDirection(index, language: language))
        }.accessibilityIdentifier("atlas-renal-amount-" + String(index))
      }
      Text(GalaxySSIHealthAtlasText.get("health_atlas_renal_balance_scope", language)).font(.footnote).foregroundColor(.secondary)
    }.accessibilityIdentifier("atlas-renal-balance")
  }
  private func chart(_ model: GalaxySSIHealthAtlasPhysiology) -> some View {
    let low = model.kind.bounds.lowerBound, high = model.plotMaximum
    let left = model.axisRange.lowerBound, right = model.axisRange.upperBound
    let output = { GalaxySSIHealthAtlasPhysiologyText.resultNumber($0, kind: model.kind, language: language) }
    let input = { GalaxySSIHealthAtlasPhysiologyText.inputNumber($0, key: model.kind.inputs[model.kind.axis].key, language: language) }
    return VStack(alignment: .leading, spacing: 8) {
      Text(GalaxySSIHealthAtlasPhysiologyText.displayUnit(model.kind.unit, language: language)).font(.caption)
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .trailing) {
          Text(output(high)); Spacer(); Text(output((low + high) / 2)); Spacer(); Text(output(low))
        }.font(.caption).frame(height: 160).fixedSize(horizontal: true, vertical: false)
        VStack(spacing: 8) {
          GeometryReader { geometry in
            let x = { (value: Double) in 6 + max(1, geometry.size.width - 12) * CGFloat((value - left) / (right - left)) }
            let y = { (value: Double) in 6 + max(1, geometry.size.height - 12) * CGFloat(1 - (value - low) / (high - low)) }
            ZStack {
              Path { path in
                for tick in [low, (low + high) / 2, high] {
                  path.move(to: CGPoint(x: 6, y: y(tick)))
                  path.addLine(to: CGPoint(x: geometry.size.width - 6, y: y(tick)))
                }
              }.stroke(Color.secondary.opacity(0.25), lineWidth: 1)
              Path { path in
                for point in model.response {
                  if point.id == 0 { path.move(to: CGPoint(x: x(point.x), y: y(point.y))) }
                  else { path.addLine(to: CGPoint(x: x(point.x), y: y(point.y))) }
                }
              }.stroke(Color.accentColor, lineWidth: 2.5)
              Path { path in
                path.move(to: CGPoint(x: x(model.input(model.kind.axis)), y: y(model.result)))
                path.addLine(to: CGPoint(x: x(model.input(model.kind.axis)), y: geometry.size.height - 6))
              }.stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3]))
              Circle().fill(Color.accentColor).frame(width: 10, height: 10)
                .position(x: x(model.input(model.kind.axis)), y: y(model.result))
            }.clipped()
          }.frame(height: 160)
          HStack {
            Text(input(left)); Spacer(); Text(input((left + right) / 2)); Spacer(); Text(input(right))
          }.font(.caption)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(t("model_" + model.kind.rawValue))
    .accessibilityValue(GalaxySSIHealthAtlasPhysiologyText.result(model, language: language) + "; " +
      GalaxySSIHealthAtlasPhysiologyText.input(model, index: model.kind.axis, language: language))
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasPhysiologyText.string(key, language: language) }
}
