import SwiftUI
import UIKit

extension GalaxySSIHealthAtlasHeartbeatView {
  func pressures(in context: GraphicsContext, stage: GalaxySSIHealthAtlasBeatStage, fraction: Double) {
    let left = 20.0, top = 277.0, bottom = 330.0, step = 304.0 / 5
    let cursor = left + step * (Double(stage.rawValue) + fraction)
    func y(_ value: Double) -> Double { bottom - (bottom - top) * value }
    context.fill(Path(roundedRect: CGRect(x: 9, y: 244, width: 326, height: 95), cornerRadius: 7), with: .color(Self.color(0xFDFBF7)))
    context.draw(Text(verbatim: t("pressure_axis")).font(.system(size: 10)).foregroundColor(Self.color(0x4A6061)),
      at: CGPoint(x: left, y: 256 - UIFont.systemFont(ofSize: 10).ascender), anchor: .topLeading)
    context.fill(Path(CGRect(x: left + Double(stage.rawValue) * step, y: top, width: step, height: bottom - top)), with: .color(Self.color(0xE5E5DF)))
    var axis = Path(); axis.move(to: CGPoint(x: left, y: bottom)); axis.addLine(to: CGPoint(x: 324, y: bottom))
    axis.move(to: CGPoint(x: cursor, y: top)); axis.addLine(to: CGPoint(x: cursor, y: bottom))
    context.stroke(axis, with: .color(Self.color(0xA0A9A9)), lineWidth: 0.8)
    let lines: [(String, UInt32, KeyPath<GalaxySSIHealthAtlasBeatPressure, Double>)] = [
      ("atrium_label", 0x247B72, \.atrium), ("ventricle_label", 0xAB304C, \.ventricle), ("aorta_label", 0xA36624, \.aorta)
    ]
    for (index, line) in lines.enumerated() {
      let color = Self.color(line.1)
      legend(in: context, center: 63 + 109 * Double(index), baseline: 271, text: t(line.0), color: color)
      var trace = Path()
      for chapter in GalaxySSIHealthAtlasBeatStage.allCases {
        for sample in 0...12 {
          let local = Double(sample) / 12
          let value = GalaxySSIHealthAtlasBeatPressureTrace.sample(chapter, fraction: local)[keyPath: line.2]
          let point = CGPoint(x: left + step * (Double(chapter.rawValue) + local), y: y(value))
          if chapter.rawValue == 0 && sample == 0 { trace.move(to: point) } else { trace.addLine(to: point) }
        }
      }
      context.stroke(trace, with: .color(color), lineWidth: 1.8)
      let current = GalaxySSIHealthAtlasBeatPressureTrace.sample(stage, fraction: fraction)[keyPath: line.2]
      context.fill(Path(ellipseIn: CGRect(x: cursor - 3, y: y(current) - 3, width: 6, height: 6)), with: .color(color))
    }
  }
}
