import Foundation

extension GalaxySSIHealthAnswerBasis {
  @MainActor
  static func localNames(_ rows: [Source], archive: GalaxySSIHealthRecords.Archive,
                         originals: GalaxySSIHealthOriginalStore) throws -> [Source] {
    guard rows.contains(where: { !$0.files.isEmpty }) else { return rows }
    return try originals.withRestoreLease { lease in
      try originals.reconcileRestores(lease: lease)
      return rows.map { row in
        guard row.kind == .measurement, let ref = row.record, let metric = row.metric, let at = row.at,
          let reading = archive.current.first(where: { $0.id == ref.id && $0.revision == ref.revision &&
            $0.metric == metric && $0.measuredAt == at && !$0.deleted }) else { return row }
        let links = (reading.reportSource.map { [$0] } ?? []) + (archive.reportEvidence ?? []).filter {
          $0.target.record == ref.id && $0.target.revision == ref.revision
        }.map(\.source)
        var names: [String] = []
        for file in row.files.prefix(8) where links.contains(where: { $0.original == file.id && $0.sha256 == file.sha256 }) {
          guard !(archive.reviewOnlyReportOriginals ?? []).contains(file.id),
            let original = try? originals.visitOriginal(id: file.id, lease: lease),
            original.sha256 == file.sha256, !original.name.isBlank else { continue }
          let name = String(original.name.prefix(180))
          if !names.contains(name) { names.append(name) }
        }
        var resolved = row
        resolved.title = String(names.joined(separator: " · ").prefix(512))
        return resolved
      }
    }
  }
}
