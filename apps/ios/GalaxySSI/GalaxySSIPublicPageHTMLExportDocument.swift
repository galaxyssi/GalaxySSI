import SwiftUI
import UniformTypeIdentifiers

struct GalaxySSIPublicPageHTMLExportDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.html] }
  static var writableContentTypes: [UTType] { [.html] }

  var data: Data

  init(data: Data = Data()) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
