import Foundation

struct GalaxySSIHealthAtlasCalloutLayout {
  let split: Bool
  let left: [Int]
  let right: [Int]
  let leftWidth: CGFloat
  let rightWidth: CGFloat
  let height: CGFloat
  let imageRect: CGRect
  let labelFrames: [CGRect]

  static func make(width: CGFloat, aspectRatio: Double, anchors: [CGPoint], splitRequested: Bool,
                   accessibility: Bool, preferredWidths: [CGFloat], legendInset: CGFloat = 0, minimumHeight: CGFloat = 300, numbered: Bool = false,
                   measureHeight: (Int, CGFloat) -> CGFloat) -> Self? {
    guard width.isFinite, width > 0, aspectRatio.isFinite, aspectRatio > 0, !anchors.isEmpty,
      legendInset.isFinite, legendInset >= 0, minimumHeight.isFinite, minimumHeight >= 0,
      anchors.count <= 64, preferredWidths.count == anchors.count,
      preferredWidths.allSatisfy({ $0.isFinite && $0 >= 0 }),
      anchors.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) })
    else { return nil }
    let split = !numbered && splitRequested && anchors.contains { $0.x < 0.5 } && anchors.contains { $0.x >= 0.5 }
    func sorted(_ indices: [Int]) -> [Int] {
      indices.sorted { anchors[$0].y == anchors[$1].y ? $0 < $1 : anchors[$0].y < anchors[$1].y }
    }
    let left = sorted(anchors.indices.filter { split && anchors[$0].x < 0.5 })
    let right = sorted(anchors.indices.filter { !split || anchors[$0].x >= 0.5 })
    func preferred(_ indices: [Int]) -> CGFloat {
      guard !indices.isEmpty else { return 0 }
      return min(floor(width * 0.24), max(48, ceil(indices.map { preferredWidths[$0] }.max() ?? 0)))
    }
    let leftWidth = preferred(left)
    let rightWidth = numbered ? min(48, width * 0.37) : split ? preferred(right) : width * (accessibility ? 0.55 : 0.36)
    let artWidth = width - leftWidth - rightWidth - (split ? 0 : 12)
    guard artWidth > 0, leftWidth >= 0, rightWidth > 0 else { return nil }
    var heights = Array(repeating: CGFloat(0), count: anchors.count)
    for (indices, column) in [(left, leftWidth), (right, rightWidth)] {
      for index in indices {
        let measured = measureHeight(index, column)
        guard measured.isFinite, measured >= 0 else { return nil }
        heights[index] = ceil(max(48, measured))
      }
    }
    func required(_ indices: [Int]) -> CGFloat { indices.reduce(CGFloat(8)) { $0 + heights[$1] + 8 } }
    let artHeight = artWidth / CGFloat(aspectRatio)
    let height = ceil(max(minimumHeight, max(artHeight + legendInset, max(required(left), required(right)) + legendInset)))
    guard height.isFinite else { return nil }
    let imageRect = CGRect(x: leftWidth, y: (height - legendInset - artHeight) / 2, width: artWidth, height: artHeight)
    var frames = Array(repeating: CGRect.zero, count: anchors.count)
    func pack(_ indices: [Int], x: CGFloat, column: CGFloat) {
      var tops: [CGFloat] = [], next: CGFloat = 8
      for index in indices {
        let desired = floor(imageRect.minY + imageRect.height * anchors[index].y - heights[index] / 2)
        let top = max(next, desired); tops.append(top); next = top + heights[index] + 8
      }
      var bottom = height - 8 - legendInset
      for order in indices.indices.reversed() {
        let index = indices[order], top = min(tops[order], bottom - heights[index])
        frames[index] = CGRect(x: x, y: top, width: column, height: heights[index])
        bottom = top - 8
      }
    }
    pack(left, x: 0, column: leftWidth); pack(right, x: width - rightWidth, column: rightWidth)
    return Self(split: split, left: left, right: right, leftWidth: leftWidth, rightWidth: rightWidth,
      height: height, imageRect: imageRect, labelFrames: frames)
  }
}
