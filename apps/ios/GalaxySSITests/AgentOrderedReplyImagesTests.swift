import Foundation
import XCTest
@testable import GalaxySSI

final class AgentOrderedReplyImagesTests: XCTestCase {
  func testBalancedSourceParenthesesConsumeTheEntireLinkedImage() {
    let blocks = AgentRichContentCodec.fromText("Before [![Harbor](https://image.example/photo.png)](https://source.example/harbor_(east)) after")
    XCTAssertEqual(blocks.map(\.type), [.text, .image, .text, .text])
    XCTAssertEqual(blocks[1].title, "Harbor")
    XCTAssertEqual(blocks[2].text, "[Harbor](<https://source.example/harbor_(east)>)")
    XCTAssertEqual(blocks[3].text, "after")
  }

  func testAngledSourceWithQuotedTitleDoesNotLeaveMarkdownResidue() {
    let blocks = AgentRichContentCodec.fromText(#"[![Harbor](https://image.example/photo.png)](<https://source.example/item?a=1&amp;b=2> "Title ) ignored") after"#)
    XCTAssertEqual(blocks.map(\.type), [.image, .text, .text])
    XCTAssertEqual(blocks[0].title, "Harbor")
    XCTAssertEqual(blocks[1].text, "[Harbor](<https://source.example/item?a=1&b=2>)")
    XCTAssertEqual(blocks[2].text, "after")
  }

  func testUnangledSourceWithQuotedParenthesisTitleKeepsCaptionAndTail() {
    let blocks = AgentRichContentCodec.fromText(#"[![First](https://image.example/1.png)](https://source.example/item_(one) 'Source ) title') end"#)
    XCTAssertEqual(blocks.map(\.type), [.image, .text, .text])
    XCTAssertEqual(blocks[1].text, "[First](<https://source.example/item_(one)>)")
    XCTAssertEqual(blocks[2].text, "end")
  }

  func testReplyOrderAndCaptionsFollowMarkupNotURLSorting() {
    let raw = AgentRichContentCodec.encode([AgentRichBlock(id: "reply", type: .text, text:
      "![First](https://image.example/z.png) ![Second](https://image.example/a.png) ![Third](https://image.example/m.png)")])
    let blocks = AgentRichContentCodec.decode(raw)
    XCTAssertEqual(blocks.map(\.title), ["First", "Second", "Third"])
    XCTAssertEqual(blocks.map(\.uri), ["https://image.example/z.png", "https://image.example/a.png", "https://image.example/m.png"])
    XCTAssertEqual(blocks.map(\.id), ["reply", "reply-markdown-1", "reply-markdown-2"])
    XCTAssertEqual(AgentRichContentCodec.decode(raw).map(\.id), blocks.map(\.id))
  }

  func testCaseSensitiveImagePathsRemainDistinctInDecodedReply() {
    let raw = AgentRichContentCodec.encode([
      AgentRichBlock(id: "upper", type: .image, title: "Upper", uri: "https://image.example/Photo.png"),
      AgentRichBlock(id: "lower", type: .image, title: "Lower", uri: "https://image.example/photo.png")])
    let blocks = AgentRichContentCodec.decode(raw)
    XCTAssertEqual(blocks.map(\.id), ["upper", "lower"])
    XCTAssertEqual(blocks.map(\.title), ["Upper", "Lower"])
  }

  func testCaseSensitiveImageQueriesAndFragmentsDoNotCollide() {
    for (a, b) in [("?token=A", "?token=a"), ("#Upper", "#upper"), ("?X=1", "?x=1")] {
      let first = AgentRichBlock(type: .image, uri: "https://image.example/p.png" + a)
      let second = AgentRichBlock(type: .image, uri: "https://image.example/p.png" + b)
      XCTAssertNotEqual(first.artifactIdentity(), second.artifactIdentity())
    }
  }

  func testOnlySchemeAndHostAreCaseInsensitiveForURIIdentity() {
    let first = AgentRichBlock(type: .image, uri: "HTTPS://IMAGE.EXAMPLE/Photo.png?token=A")
    let second = AgentRichBlock(type: .image, uri: "https://image.example/Photo.png?token=A")
    XCTAssertEqual(first.artifactIdentity(), second.artifactIdentity())
    let localA = AgentRichBlock(type: .image, uri: "galaxyssi-artifact://task/outputs/A.png")
    let localB = AgentRichBlock(type: .image, uri: "galaxyssi-artifact://task/outputs/a.png")
    XCTAssertNotEqual(localA.artifactIdentity(), localB.artifactIdentity())
  }

  func testDuplicateQualityUpgradeRetainsOriginalSlotWithoutReorderingOthers() {
    let raw = AgentRichContentCodec.encode([
      AgentRichBlock(id: "a", type: .image, title: "First", uri: "https://image.example/a.png"),
      AgentRichBlock(id: "b", type: .image, title: "Second", uri: "https://image.example/b.png"),
      AgentRichBlock(id: "a-ready", type: .image, title: "First ready", uri: "https://image.example/a.png", mimeType: "image/png")])
    let blocks = AgentRichContentCodec.decode(raw)
    XCTAssertEqual(blocks.map(\.id), ["a-ready", "b"])
    XCTAssertEqual(blocks.map(\.title), ["First ready", "Second"])
  }

  func testUnsafeImageAndInternalArtifactMarkupAreNotPromotedByWrapperFix() {
    for text in ["![Unsafe](javascript:alert(1))", "![Unsafe](file:///private/photo.png)",
                 "![Unsafe](https://user:secret@image.example/photo.png)"] {
      XCTAssertFalse(AgentRichContentCodec.fromText(text).contains { $0.type == .image })
    }
    XCTAssertTrue(AgentRichContentCodec.fromText("![Private](galaxyssi-artifact://foreign/outputs/private.png)").isEmpty)
  }

  func testSharedArtifactURIIdentityPreservesCaseForFileAudioAndVideo() {
    for type in [AgentRichBlockType.file, .audio, .video, .gallery] {
      let a = AgentRichBlock(type: type, uri: "https://media.example/Artifact?Key=A")
      let b = AgentRichBlock(type: type, uri: "https://media.example/artifact?Key=a")
      XCTAssertNotEqual(a.artifactIdentity(), b.artifactIdentity())
    }
  }

  func testAuthenticatedDigestAndLocalVideoIdentityRulesRemainUnchanged() {
    let digest = String(repeating: "a", count: 64)
    let a = AgentRichBlock(type: .image, title: "Photo", uri: "https://image.example/A.png", metadata: ["sha256": digest])
    let b = AgentRichBlock(type: .image, title: "Photo", uri: "https://image.example/B.png", metadata: ["sha256": digest])
    XCTAssertEqual(a.artifactIdentity(), b.artifactIdentity())
    XCTAssertEqual(a.artifactIdentity(), "sha256:\(digest):photo")
    let video = AgentRichBlock(type: .video, uri: AgentVisualOutputPolicy.localVideoPrefix + "video",
      metadata: ["relative_path": "outputs/Clip.mp4"])
    XCTAssertEqual(video.artifactIdentity(), "local-video:\(video.uri):outputs/Clip.mp4")
  }
}
