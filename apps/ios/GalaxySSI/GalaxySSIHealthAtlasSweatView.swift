import SwiftUI

struct GalaxySSIHealthAtlasSweatView: View {
  let phase: Double
  let stages: [String]
  let language: String
  private static let droplet = Color(red: 32/255, green: 103/255, blue: 130/255)
  static let duct: Path = {
    var path = Path()
    path.move(to: CGPoint(x: 173, y: 66))
    path.addLine(to: CGPoint(x: 173, y: 83))
    path.addQuadCurve(to: CGPoint(x: 173, y: 103), control: CGPoint(x: 152, y: 93))
    path.addQuadCurve(to: CGPoint(x: 170, y: 125), control: CGPoint(x: 194, y: 113))
    path.addQuadCurve(to: CGPoint(x: 174, y: 145), control: CGPoint(x: 149, y: 136))
    path.addLine(to: CGPoint(x: 174, y: 170))
    path.addQuadCurve(to: CGPoint(x: 144, y: 199), control: CGPoint(x: 145, y: 181))
    path.addQuadCurve(to: CGPoint(x: 181, y: 230), control: CGPoint(x: 145, y: 227))
    path.addQuadCurve(to: CGPoint(x: 210, y: 204), control: CGPoint(x: 214, y: 231))
    path.addQuadCurve(to: CGPoint(x: 183, y: 190), control: CGPoint(x: 208, y: 183))
    path.addQuadCurve(to: CGPoint(x: 168, y: 211), control: CGPoint(x: 159, y: 194))
    path.addQuadCurve(to: CGPoint(x: 192, y: 216), control: CGPoint(x: 177, y: 223))
    return path
  }()
  var body: some View {
    if let model = GalaxySSIHealthAtlasSweat(phase: phase), stages.count == 4 {
      Canvas { context, size in
        var drawing = context
        let scale = min(size.width / 360, size.height / 280)
        drawing.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 280 * scale) / 2)
        drawing.scaleBy(x: scale, y: scale)
        let picture = drawing.resolve(Image("HealthAtlasContextSweatGlandSection"))
        drawing.draw(picture, in: CGRect(x: 0, y: 0, width: 360, height: 280))
        if let position = model.transportFraction {
          let point = position == 0 ? CGPoint(x: 173, y: 66) :
            Self.duct.trimmedPath(from: 0, to: CGFloat(position)).cgPath.currentPoint
          drawing.fill(Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)), with: .color(Self.droplet))
        } else if let radius = model.surfaceRadius {
          drawing.fill(Path(ellipseIn: CGRect(x: 173 - radius, y: 47 - radius, width: radius * 2, height: 4 + radius * 2)),
            with: .color(Self.droplet))
        } else {
          drawing.opacity = model.vaporOpacity
          for index in -1...1 {
            let x = 173 + 14 * Double(index), y = 39 - 20 * model.fraction + 4 * Double(abs(index))
            drawing.stroke(Path(ellipseIn: CGRect(x: x - 4.5, y: y - 4.5, width: 9, height: 9)),
              with: .color(Self.droplet), lineWidth: 2.8)
          }
        }
      }.aspectRatio(360.0 / 280, contentMode: .fit).frame(maxHeight: 234)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GalaxySSIHealthAtlasText.get(stages[model.stage], language) + ". " +
          GalaxySSIHealthAtlasText.get("health_atlas_context_sweat_scope", language))
        .accessibilityIdentifier("atlas-sweat-diagram")
    }
  }
}
