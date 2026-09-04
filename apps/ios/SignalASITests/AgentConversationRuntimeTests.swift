import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentWorkspaceFileModelsUseAndroidWireNames() throws {
    let policy = AgentWorkspaceFilePolicy(maxTextReadBytes: -1, maxZipCompressionRatio: 0)
    let encodedPolicy = String(decoding: try JSONEncoder().encode(policy), as: UTF8.self)
    let decodedMutation = try JSONDecoder().decode(
      AgentWorkspaceMutation.self,
      from: Data(
        #"""
        {
          "kind": "MOVE",
          "path": "docs/new.txt",
          "source_path": "docs/old.txt",
          "affected_entries": 1,
          "affected_bytes": 12,
          "metadata": {
            "path": "docs/new.txt",
            "type": "FILE",
            "size_bytes": 12,
            "last_modified_millis": 123
          }
        }
        """#.utf8
      )
    )
    let zipEntry = AgentWorkspaceZipEntryMetadata(
      path: "docs/a.txt",
      directory: false,
      compressedBytes: 3,
      uncompressedBytes: 9,
      compressionRatio: 3,
      crc32: 42,
      lastModifiedMillis: 100
    )
    let encodedZip = String(
      decoding: try JSONEncoder().encode(
        AgentWorkspaceZipListing(
          archivePath: "bundle.zip",
          archiveBytes: 100,
          totalCompressedBytes: 3,
          totalUncompressedBytes: 9,
          entries: [zipEntry]
        )
      ),
      as: UTF8.self
    )

    XCTAssertEqual(policy.maxTextReadBytes, 1)
    XCTAssertEqual(policy.maxZipCompressionRatio, 1)
    XCTAssertTrue(encodedPolicy.contains(#""max_text_read_bytes":1"#))
    XCTAssertTrue(encodedPolicy.contains(#""max_zip_entry_name_characters":512"#))
    XCTAssertEqual(decodedMutation.kind, .move)
    XCTAssertEqual(decodedMutation.sourcePath, "docs/old.txt")
    XCTAssertEqual(decodedMutation.metadata?.type, .file)
    XCTAssertEqual(AgentWorkspaceFileErrorCode.fromWireValue("path_escape"), .pathEscape)
    XCTAssertEqual(AgentWorkspaceMutationKind.fromWireValue("mkdir"), .mkdir)
    XCTAssertEqual(AgentWorkspaceEntryType.fromWireValue("directory"), .directory)
    XCTAssertTrue(encodedZip.contains(#""archive_path":"bundle.zip""#))
    XCTAssertTrue(encodedZip.contains(#""total_uncompressed_bytes":9"#))
    XCTAssertTrue(encodedZip.contains(#""compression_ratio":3"#))
  }

  func testAgentWorkspaceFilePathPolicyRejectsEscapesAndNormalizesPortablePaths() {
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.workspaceDirectoryName("alpha_1.2-3").value, "alpha_1.2-3")
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.workspaceDirectoryName("../alpha").error?.code, .invalidWorkspace)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("docs/./nested//note.txt").value, ["docs", "nested", "note.txt"])
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("docs\\note.txt").value, ["docs", "note.txt"])
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("../escape.txt").error?.code, .pathEscape)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("docs/../escape.txt").error?.code, .pathEscape)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("/absolute.txt").error?.code, .pathEscape)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("C:\\absolute.txt").error?.code, .pathEscape)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("contains\u{0000}null").error?.code, .invalidPath)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("", allowRoot: false).error?.code, .invalidPath)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.displayPath("docs\\note.txt"), "docs/note.txt")
  }

  func testAgentWorkspaceFileArchivePolicyRejectsZipSlipAndAbsoluteEntries() {
    let policy = AgentWorkspaceFilePolicy(maxZipEntryNameCharacters: 12)

    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("docs\\a.txt").value, "docs/a.txt")
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("docs/a.txt/").value, "docs/a.txt")
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("../escaped.txt").error?.code, .invalidArchive)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("/absolute.txt").error?.code, .invalidArchive)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("C:\\absolute.txt").error?.code, .invalidArchive)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("/").error?.code, .invalidArchive)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("very-long-entry-name.txt", policy: policy).error?.code, .invalidArchive)
  }

  func testAgentWorkspacePatchPolicyMatchesAndroidDiffAndReplacementRules() {
    let before = "one\ntwo\nthree\n"
    let after = AgentWorkspacePatchPolicy.replaceOccurrences(text: before, expected: "two", replacement: "TWO")
    let diff = AgentWorkspacePatchPolicy.summarizeDiff(before: before, after: after)
    let unchanged = AgentWorkspacePatchPolicy.summarizeDiff(before: after, after: after)
    let inserted = AgentWorkspacePatchPolicy.summarizeDiff(before: "one\nthree", after: "one\ntwo\nthree")

    XCTAssertEqual(AgentWorkspacePatchPolicy.countOccurrences(text: before, expected: "two"), 1)
    XCTAssertEqual(AgentWorkspacePatchPolicy.countOccurrences(text: "aaaa", expected: "aa"), 2)
    XCTAssertEqual(after, "one\nTWO\nthree\n")
    XCTAssertEqual(diff.beforeSha256, agentReputationSha256(Data(before.utf8)))
    XCTAssertEqual(diff.afterSha256, agentReputationSha256(Data(after.utf8)))
    XCTAssertEqual(diff.firstChangedLine, 2)
    XCTAssertEqual(diff.changedLinePairs, 1)
    XCTAssertEqual(diff.addedLines, 0)
    XCTAssertEqual(diff.deletedLines, 0)
    XCTAssertNil(unchanged.firstChangedLine)
    XCTAssertEqual(inserted.firstChangedLine, 2)
    XCTAssertEqual(inserted.addedLines, 1)
    XCTAssertEqual(inserted.deletedLines, 0)
  }

  func testAgentFastLocalResponseAnswersBoundedBinaryArithmeticLocally() {
    let context = AgentConversationContext(conversationId: "test", summary: "", turns: [], privateMode: false)

    XCTAssertEqual(
      AgentFastLocalResponse.reply(goal: "\u{53ea}\u{7ed9}\u{51fa} 37 + 58 \u{7684}\u{7ed3}\u{679c}\u{3002}", context: context),
      "95"
    )
    XCTAssertEqual(AgentFastLocalResponse.reply(goal: "12 / 2", context: context), "6")
    XCTAssertEqual(AgentFastLocalResponse.reply(goal: "Calculate 3 x -7", context: context), "-21")
    XCTAssertEqual(AgentFastLocalResponse.reply(goal: "1+1=", context: context), "2")
    XCTAssertEqual(AgentFastLocalResponse.reply(goal: "1 + 1 \u{ff1d}", context: context), "2")
    XCTAssertNil(
      AgentFastLocalResponse.reply(goal: "Explain why 37 + 58 is useful in this example", context: context)
    )
    XCTAssertNil(AgentFastLocalResponse.reply(goal: "Calculate 1 / 0", context: context))
  }

  func testAgentFastLocalResponseAsksOneQuestionForObjectlessNewConversationRequest() {
    let goal = "\u{5e2e}\u{6211}\u{5904}\u{7406}\u{4e00}\u{4e0b}\u{3002}"
    let contextAfterUserAppend = AgentConversationContext(
      conversationId: "test",
      summary: "",
      turns: [AgentTranscriptEntry(id: "current", role: .user, text: goal, timestampMillis: 1)],
      privateMode: false
    )
    let response = AgentFastLocalResponse.reply(goal: goal, context: contextAfterUserAppend)

    XCTAssertEqual(
      response,
      "\u{4f60}\u{60f3}\u{8ba9}\u{6211}\u{5904}\u{7406}\u{4ec0}\u{4e48}\u{ff1f}\u{53ef}\u{4ee5}\u{53d1}\u{6587}\u{5b57}\u{3001}\u{6587}\u{4ef6}\u{6216}\u{56fe}\u{7247}\u{ff0c}\u{6216}\u{76f4}\u{63a5}\u{8bf4}\u{8981}\u{6211}\u{67e5}\u{770b}\u{3001}\u{4fee}\u{6539}\u{3001}\u{603b}\u{7ed3}\u{8fd8}\u{662f}\u{6267}\u{884c}\u{3002}"
    )
  }

  func testAgentFastLocalResponsePreservesContextualFollowUpForTheModel() {
    let context = AgentConversationContext(
      conversationId: "test",
      summary: "",
      turns: [AgentTranscriptEntry(id: "1", role: .user, text: "Prior task", timestampMillis: 1)],
      privateMode: false
    )
    let summarizedContext = AgentConversationContext(
      conversationId: "test",
      summary: "The user asked for a report review.",
      turns: [],
      privateMode: false
    )

    XCTAssertNil(
      AgentFastLocalResponse.reply(goal: "\u{5e2e}\u{6211}\u{5904}\u{7406}\u{4e00}\u{4e0b}\u{3002}", context: context)
    )
    XCTAssertNil(AgentFastLocalResponse.reply(goal: "Handle this", context: summarizedContext))
  }

  func testAgentFastLocalResponseRequestsDocumentAuthorizationForRawSharedStoragePaths() {
    let context = AgentConversationContext(conversationId: "test", summary: "", turns: [], privateMode: false)
    let chinese = AgentFastLocalResponse.reply(
      goal: "\u{8bfb}\u{53d6} /storage/emulated/0/Download/report.txt \u{5e76}\u{544a}\u{8bc9}\u{6211}\u{7ed3}\u{679c}\u{3002}",
      context: context
    )

    XCTAssertTrue(chinese?.contains("Android \u{4e0d}\u{5141}\u{8bb8} App") == true)
    XCTAssertTrue(chinese?.contains("\u{91cd}\u{65b0}\u{9009}\u{62e9}\u{8be5}\u{6587}\u{4ef6}") == true)
    XCTAssertEqual(
      AgentFastLocalResponse.reply(goal: "Read /sdcard/Download/report.txt", context: context),
      "Android does not let apps read this raw shared-storage path directly. Select the file again with the input bar's file button; after you grant access, I will process it directly."
    )
    XCTAssertNil(AgentFastLocalResponse.reply(goal: "Save the result to /sdcard/Download/report.txt", context: context))
  }

  func testAgentConversationContextUsesAndroidWireNamesAndGlobalContextRules() throws {
    let context = AgentConversationContext(
      conversationId: "conversation-a",
      summary: "Earlier summary",
      turns: [AgentTranscriptEntry(id: "1", role: .assistant, text: "Done", timestampMillis: 2)],
      privateMode: true,
      globalContext: "Global note",
      trackingPaused: true
    )
    let encoded = String(decoding: try JSONEncoder().encode(context), as: UTF8.self)

    XCTAssertFalse(context.allowsGlobalContext)
    XCTAssertTrue(encoded.contains(#""conversation_id":"conversation-a""#))
    XCTAssertTrue(encoded.contains(#""private_mode":true"#))
    XCTAssertTrue(encoded.contains(#""global_context":"Global note""#))
    XCTAssertTrue(encoded.contains(#""tracking_paused":true"#))
  }

  func testAgentGlobalContextDispatchPolicyMatchesAndroidGreetingRules() {
    [
      "hello",
      "Hello!",
      "hi there",
      "\u{4f60}\u{597d}",
      "\u{4f60}\u{597d}\u{ff01}",
      "\u{65e9}\u{4e0a}\u{597d}"
    ].forEach { query in
      XCTAssertEqual(
        AgentGlobalContextDispatchPolicy.mode(query: query, hasAttachments: false),
        .minimal,
        query
      )
    }

    XCTAssertEqual(AgentGlobalContextDispatchPolicy.mode(query: "hello", hasAttachments: true), .full)

    [
      "\u{4f60}\u{597d}\u{ff0c}\u{8bf7}\u{7ee7}\u{7eed}\u{5904}\u{7406}\u{521a}\u{624d}\u{7684}\u{56fe}\u{7247}",
      "hello, summarize the attachment",
      "\u{7ee7}\u{7eed}",
      "\u{5f53}\u{524d}\u{8bf7}\u{6c42}",
      "\u{65e9}\u{4e0a}\u{597d}\u{ff0c}\u{67e5}\u{770b}\u{4eca}\u{5929}\u{7684}\u{65b0}\u{95fb}"
    ].forEach { query in
      XCTAssertEqual(
        AgentGlobalContextDispatchPolicy.mode(query: query, hasAttachments: false),
        .full,
        query
      )
    }
  }

  func testAgentConversationContextTransportKeepsAttachmentReferenceWithoutPrivateBytes() throws {
    let richOutput = """
    {"version":1,"blocks":[{"id":"image-1","type":"image","title":"homework.jpg","uri":"content://signalasi/private/homework.jpg","data_b64":"private-image-bytes","mime_type":"image/jpeg","metadata":{"size_bytes":"245760"}}]}
    """
    let context = AgentConversationContext(
      conversationId: "conversation-1",
      summary: "",
      turns: [
        AgentTranscriptEntry(
          id: "entry-1",
          role: .user,
          text: "Please review this",
          timestampMillis: 1,
          dedupeKey: "",
          conversationId: "conversation-1",
          turnId: "turn-1",
          taskId: "turn-1",
          richOutputJson: richOutput
        )
      ],
      privateMode: false
    )

    let transport = context.asTransportBlock()
    let json = transport
      .replacingOccurrences(of: "\(AgentConversationContext.transportHeader)\n", with: "")
      .replacingOccurrences(of: "\n\(AgentConversationContext.transportFooter)", with: "")
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let attachmentIndex = try XCTUnwrap(payload["attachment_index"] as? [[String: Any]])
    let turns = try XCTUnwrap(payload["turns"] as? [[String: Any]])
    let turnAttachments = try XCTUnwrap(turns.first?["attachments"] as? [[String: Any]])

    XCTAssertTrue(context.hasAttachments)
    XCTAssertTrue(context.asPromptBlock().contains("Attachments: homework.jpg (image/jpeg)"))
    XCTAssertEqual(attachmentIndex.first?["name"] as? String, "homework.jpg")
    XCTAssertEqual(attachmentIndex.first?["mime_type"] as? String, "image/jpeg")
    XCTAssertEqual((attachmentIndex.first?["size_bytes"] as? NSNumber)?.intValue, 245_760)
    XCTAssertEqual(attachmentIndex.first?["turn_id"] as? String, "turn-1")
    XCTAssertEqual(turnAttachments.first?["artifact_id"] as? String, "image-1")
    XCTAssertFalse(transport.contains("content://signalasi/private"))
    XCTAssertFalse(transport.contains("private-image-bytes"))
    XCTAssertFalse(transport.contains("data_b64"))
  }

  func testAgentConversationTransportRequiresExplicitGlobalContextOptIn() {
    let marker = "Core personal memory: preferred name is Nova."
    let shared = AgentConversationContext(
      conversationId: "new-session",
      summary: "",
      turns: [],
      privateMode: false,
      globalContext: marker
    )
    let privateContext = AgentConversationContext(
      conversationId: "private-session",
      summary: "",
      turns: [],
      privateMode: true,
      globalContext: marker
    )

    XCTAssertTrue(shared.asTransportBlock().isEmpty)
    XCTAssertTrue(shared.asTransportBlock(includeGlobalContext: true).contains(marker))
    XCTAssertTrue(privateContext.asTransportBlock(includeGlobalContext: true).isEmpty)
  }

  func testAgentConversationMergePolicyMergesDialogueOnceAndArchivesChild() {
    let parent = agentConversation(id: "parent", title: "Main topic", summary: "Parent summary")
    let child = agentConversation(
      id: "child",
      title: "Agent research",
      summary: "Runtime is ready",
      createdByAgent: true,
      parentConversationId: parent.id,
      inputTokens: 20,
      outputTokens: 30
    )
    let entries = [
      agentMergeEntry(id: "user", role: .user, conversationId: child.id, text: "Investigate the runtime"),
      agentMergeEntry(id: "process", role: .process, conversationId: child.id, text: "Ran a tool"),
      agentMergeEntry(
        id: "assistant",
        role: .assistant,
        conversationId: child.id,
        text: "The runtime is ready",
        richOutputJson: #"{"version":1,"blocks":[{"id":"result","type":"markdown","text":"ready"}]}"#
      )
    ]

    let mutation = AgentConversationMergePolicy.mergeIntoParent(
      conversations: [parent, child],
      entries: entries,
      sourceConversationId: child.id,
      nowMillis: 1_000
    )

    XCTAssertTrue(mutation.result.merged)
    XCTAssertEqual(mutation.result.copiedEntryCount, 2)
    XCTAssertEqual(mutation.result.skippedEntryCount, 0)
    let copied = mutation.entries.filter { $0.conversationId == parent.id }
    XCTAssertEqual(copied.map(\.role), [.user, .assistant])
    XCTAssertTrue(copied.allSatisfy { $0.sourceConversationId == child.id })
    XCTAssertTrue(copied.allSatisfy { $0.sourceConversationTitle == child.title })
    XCTAssertEqual(copied.last?.richOutputJson, entries.last?.richOutputJson)
    XCTAssertTrue(copied.allSatisfy { $0.dedupeKey.hasPrefix("merged:child:") })

    let mergedChild = mutation.conversations.first { $0.id == child.id }
    XCTAssertEqual(mergedChild?.status, .archived)
    XCTAssertEqual(mergedChild?.trackingPaused, true)
    XCTAssertEqual(mergedChild?.mergedIntoConversationId, parent.id)
    XCTAssertEqual(mergedChild?.mergedAtMillis, 1_000)
    XCTAssertEqual(mutation.result.targetConversation?.status, .active)
    XCTAssertEqual(mutation.result.targetConversation?.inputTokens, 20)
    XCTAssertEqual(mutation.result.targetConversation?.outputTokens, 30)
    XCTAssertTrue(mutation.result.targetConversation?.summary.contains("Merged topic Agent research:") == true)

    let repeated = AgentConversationMergePolicy.mergeIntoParent(
      conversations: mutation.conversations,
      entries: mutation.entries,
      sourceConversationId: child.id,
      nowMillis: 2_000
    )
    XCTAssertFalse(repeated.result.merged)
    XCTAssertEqual(repeated.result.failure, .alreadyMerged)
  }

  func testAgentConversationMergePolicyRefusesPrivacyMismatch() {
    let parent = agentConversation(id: "parent", title: "Main topic")
    let child = agentConversation(
      id: "child",
      title: "Private research",
      createdByAgent: true,
      parentConversationId: parent.id,
      privateMode: true
    )

    let mutation = AgentConversationMergePolicy.mergeIntoParent(
      conversations: [parent, child],
      entries: [],
      sourceConversationId: child.id,
      nowMillis: 1_000
    )

    XCTAssertFalse(mutation.result.merged)
    XCTAssertEqual(mutation.result.failure, .privacyMismatch)
    XCTAssertEqual(mutation.conversations, [parent, child])
  }

  func testAgentConversationMergePolicySkipsGlobalDeliveryDuplicates() {
    let parent = agentConversation(id: "parent", title: "Main topic")
    let child = agentConversation(
      id: "child",
      title: "Agent research",
      createdByAgent: true,
      parentConversationId: parent.id
    )
    let parentInsight = agentMergeEntry(
      id: "parent-insight",
      role: .assistant,
      conversationId: parent.id,
      text: "Shared result",
      dedupeKey: "global-agent:insight"
    )
    let childInsight = agentMergeEntry(
      id: "child-insight",
      role: .assistant,
      conversationId: child.id,
      text: "Shared result",
      dedupeKey: "global-agent:insight"
    )

    let mutation = AgentConversationMergePolicy.mergeIntoParent(
      conversations: [parent, child],
      entries: [parentInsight, childInsight],
      sourceConversationId: child.id,
      nowMillis: 1_000
    )

    XCTAssertTrue(mutation.result.merged)
    XCTAssertEqual(mutation.result.copiedEntryCount, 0)
    XCTAssertEqual(mutation.result.skippedEntryCount, 1)
    XCTAssertEqual(
      mutation.entries.filter { $0.conversationId == parent.id && $0.dedupeKey == "global-agent:insight" }.count,
      1
    )
  }

  func testAgentFinalResponseIdentityCoalescesCanonicalDuplicates() {
    let canonical = finalTranscriptEntry(
      id: "canonical",
      turnId: "turn-1",
      taskId: "task-1",
      dedupeKey: "assistant-final:turn:turn-1",
      timestampMillis: 1
    )
    let lateDuplicate = finalTranscriptEntry(
      id: "late",
      turnId: "",
      taskId: " task-1 ",
      dedupeKey: "assistant-final:task:task-1",
      timestampMillis: 2
    )
    let userEntry = finalTranscriptEntry(
      id: "user",
      role: .user,
      taskId: "task-1",
      dedupeKey: "assistant-final:task:task-1",
      timestampMillis: 3
    )
    let otherTask = finalTranscriptEntry(
      id: "other",
      taskId: "task-2",
      dedupeKey: "assistant-final:task:task-2",
      timestampMillis: 4
    )

    XCTAssertEqual(
      AgentFinalResponseIdentity.coalesce([canonical, lateDuplicate, userEntry, otherTask]),
      [canonical, userEntry, otherTask]
    )
  }

  func testAgentFinalResponseIdentityPrefersRichOutputThenLatestTimestamp() {
    let plain = finalTranscriptEntry(
      id: "plain",
      taskId: "task-1",
      dedupeKey: "assistant-final:source:101",
      timestampMillis: 3
    )
    let rich = finalTranscriptEntry(
      id: "rich",
      taskId: "task-1",
      dedupeKey: "assistant-final:task:task-1",
      timestampMillis: 1,
      richOutputJson: #"{"type":"markdown"}"#
    )
    let latest = finalTranscriptEntry(
      id: "latest",
      taskId: "task-2",
      dedupeKey: "assistant-final:source:202",
      timestampMillis: 4
    )
    let earlier = finalTranscriptEntry(
      id: "earlier",
      taskId: "task-2",
      dedupeKey: "assistant-final:task:task-2",
      timestampMillis: 2
    )

    XCTAssertEqual(
      AgentFinalResponseIdentity.coalesce([plain, rich, latest, earlier]),
      [rich, latest]
    )
  }

  func testAgentTaskIdentityPolicyGeneratesStableAndroidIds() {
    let conversationId = AgentTaskIdentityPolicy.conversationId(contactId: "codex", requested: "")
    let turnId = AgentTaskIdentityPolicy.turnId(sourceMessageId: 42, requested: "")
    let first = AgentTaskIdentityPolicy.taskId(
      ownerId: "signalasi:phone",
      contactId: "codex",
      sourceMessageId: 42,
      conversationId: conversationId,
      turnId: turnId
    )
    let second = AgentTaskIdentityPolicy.taskId(
      ownerId: "signalasi:phone",
      contactId: "codex",
      sourceMessageId: 42,
      conversationId: conversationId,
      turnId: turnId
    )

    XCTAssertEqual(conversationId, "contact:codex")
    XCTAssertEqual(turnId, "message:42")
    XCTAssertEqual(first, second)
    XCTAssertEqual(first, "89d82315-14f3-3f6a-8e5f-4cb48680373d")
    XCTAssertEqual(
      AgentTaskIdentityPolicy.conversationId(contactId: "codex", requested: " conversation-a "),
      "conversation-a"
    )
    XCTAssertEqual(
      AgentTaskIdentityPolicy.turnId(sourceMessageId: nil, requested: "") {
        UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
      },
      "11111111-2222-3333-4444-555555555555"
    )
    XCTAssertEqual(
      AgentTaskIdentityPolicy.taskId(
        ownerId: "signalasi:phone",
        contactId: "codex",
        sourceMessageId: "message-uuid",
        conversationId: conversationId,
        turnId: turnId
      ),
      AgentTaskIdentityPolicy.taskId(
        ownerId: "signalasi:phone",
        contactId: "codex",
        sourceMessageId: "message-uuid",
        conversationId: conversationId,
        turnId: turnId
      )
    )
  }

  func testAgentTaskIdentityPolicyMatchesDesktopResponseIdentity() {
    let expected = [
      "resource_location": "desktop",
      "conversation_id": "conversation-a",
      "remote_task_id": "task-a",
      "turn_id": "turn-a"
    ]

    XCTAssertTrue(
      AgentTaskIdentityPolicy.matchesDesktopResponse(
        expected: expected,
        conversationId: "conversation-a",
        taskId: "task-a",
        turnId: "turn-a"
      )
    )
    XCTAssertFalse(
      AgentTaskIdentityPolicy.matchesDesktopResponse(
        expected: expected,
        conversationId: "conversation-b",
        taskId: "task-a",
        turnId: "turn-a"
      )
    )
    XCTAssertFalse(
      AgentTaskIdentityPolicy.matchesDesktopResponse(
        expected: expected,
        conversationId: "conversation-a",
        taskId: "task-a",
        turnId: "turn-b"
      )
    )
    XCTAssertFalse(
      AgentTaskIdentityPolicy.matchesDesktopResponse(
        expected: expected,
        conversationId: "conversation-a",
        taskId: "",
        turnId: "turn-a"
      )
    )
    XCTAssertTrue(
      AgentTaskIdentityPolicy.matchesDesktopResponse(
        expected: ["resource_location": "cloud"],
        conversationId: "",
        taskId: "",
        turnId: ""
      )
    )
  }

  func testAgentTaskIdentityPolicyRoutesPersistedMainAgentConversationLikeAndroid() {
    XCTAssertTrue(
      AgentTaskIdentityPolicy.routesToMainAgent(
        superseded: false,
        hasRuntime: false,
        resolvedConversationId: "conversation-a"
      )
    )
    XCTAssertTrue(
      AgentTaskIdentityPolicy.routesToMainAgent(
        superseded: true,
        hasRuntime: false,
        resolvedConversationId: ""
      )
    )
    XCTAssertTrue(
      AgentTaskIdentityPolicy.routesToMainAgent(
        superseded: false,
        hasRuntime: true,
        resolvedConversationId: ""
      )
    )
    XCTAssertFalse(
      AgentTaskIdentityPolicy.routesToMainAgent(
        superseded: false,
        hasRuntime: false,
        resolvedConversationId: ""
      )
    )
  }

  func testAgentTaskIdentityCompletenessAndWireNames() throws {
    let identity = AgentTaskIdentity(
      clientRouteId: "route-1",
      conversationId: "conversation-a",
      taskId: "task-a",
      turnId: "turn-a"
    )
    XCTAssertTrue(identity.isComplete)
    XCTAssertFalse(
      AgentTaskIdentity(
        clientRouteId: "route-1",
        conversationId: "conversation-a",
        taskId: "",
        turnId: "turn-a"
      ).isComplete
    )

    let encoded = String(decoding: try JSONEncoder().encode(identity), as: UTF8.self)
    XCTAssertTrue(encoded.contains(#""client_route_id":"route-1""#))
    XCTAssertTrue(encoded.contains(#""conversation_id":"conversation-a""#))
    XCTAssertTrue(encoded.contains(#""task_id":"task-a""#))
    XCTAssertTrue(encoded.contains(#""turn_id":"turn-a""#))

    let decoded = try JSONDecoder().decode(
      AgentTaskIdentity.self,
      from: Data(
        #"""
        {
          "client_route_id": "route-2",
          "conversation_id": "conversation-b",
          "task_id": "task-b",
          "turn_id": "turn-b"
        }
        """#.utf8
      )
    )
    XCTAssertEqual(decoded.clientRouteId, "route-2")
    XCTAssertTrue(decoded.isComplete)
  }

  func testAgentTaskIdentityStoreMatchesRegisteredAndroidTurnIdentity() throws {
    let suite = "AgentTaskIdentityStoreTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AgentTaskIdentityStore(defaults: defaults)
    let identity = AgentTaskIdentity(
      clientRouteId: "route-1",
      conversationId: "conversation-a",
      taskId: "task-a",
      turnId: "turn-a"
    )
    let payload: [String: Any] = [
      "client_route_id": "route-1",
      "conversation_id": "conversation-a",
      "task_id": "task-a",
      "turn_id": "turn-a",
      "contact_id": "codex",
      "source_message_id": "message-uuid"
    ]

    XCTAssertTrue(store.matches(payload: payload))
    XCTAssertFalse(store.matchesRegistered(payload: payload))

    store.register(contactId: "codex", sourceMessageId: "message-uuid", identity: identity)

    XCTAssertTrue(store.matches(payload: payload))
    XCTAssertTrue(store.matchesRegistered(payload: payload))

    var staleRoute = payload
    staleRoute["client_route_id"] = "route-2"
    XCTAssertFalse(store.matches(payload: staleRoute))
    XCTAssertFalse(store.matchesRegistered(payload: staleRoute))
  }

  func testAgentTaskIdentityStoreFallsBackToClientMessageIdForOutboundPayloads() throws {
    let suite = "AgentTaskIdentityStoreClientMessageTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AgentTaskIdentityStore(defaults: defaults)
    let identity = AgentTaskIdentity(
      clientRouteId: "route-1",
      conversationId: "conversation-a",
      taskId: "task-a",
      turnId: "turn-a"
    )

    store.register(contactId: "codex", sourceMessageId: "42", identity: identity)

    XCTAssertTrue(
      store.matchesRegistered(payload: [
        "client_route_id": "route-1",
        "conversation_id": "conversation-a",
        "task_id": "task-a",
        "turn_id": "turn-a",
        "contact_id": "codex",
        "client_message_id": 42
      ])
    )
  }

  func testAgentTaskIntentClassifierMatchesAndroidCanonicalIntents() {
    let cases: [(String, AgentTaskIntent)] = [
      ("Hello, how are you?", .chat),
      ("Build an Android app and run unit tests", .code),
      ("Turn on the flashlight on my phone", .phoneControl),
      ("Open the browser on my computer", .desktopControl),
      ("Research today's AI news and cite sources", .research),
      ("Extract text from this PDF", .file),
      ("Remember that I prefer concise replies", .memory),
      ("Run this health check every hour", .automation)
    ]

    for (goal, expected) in cases {
      let result = AgentTaskIntentClassifier.classify(goal: goal)

      XCTAssertEqual(result.intent, expected, goal)
      XCTAssertGreaterThanOrEqual(result.confidence, 55, goal)
    }
  }

  func testAgentTaskIntentClassifierHandlesAttachmentsAndChineseSignals() {
    let attachment = AgentTaskIntentClassifier.classify(goal: "", hasAttachments: true)
    XCTAssertEqual(attachment.intent, .file)
    XCTAssertTrue(attachment.matchedSignals.contains("attachment"))

    let cases: [(String, AgentTaskIntent)] = [
      ("\u{4f60}\u{597d}", .chat),
      ("\u{7f16}\u{8bd1}\u{8fd9}\u{4e2a}\u{9879}\u{76ee}", .code),
      ("\u{6253}\u{5f00}\u{624b}\u{673a}\u{624b}\u{7535}\u{7b52}", .phoneControl),
      ("\u{63a7}\u{5236}\u{7535}\u{8111}\u{6253}\u{5f00}\u{6d4f}\u{89c8}\u{5668}", .desktopControl),
      ("\u{641c}\u{7d22}\u{4eca}\u{5929}\u{7684}\u{65b0}\u{95fb}", .research),
      ("\u{63d0}\u{53d6}\u{8fd9}\u{4e2a} PDF \u{6587}\u{4ef6}\u{7684}\u{6587}\u{5b57}", .file),
      ("\u{8bb0}\u{4f4f}\u{6211}\u{7684}\u{504f}\u{597d}", .memory),
      ("\u{6bcf}\u{5929}\u{76d1}\u{63a7}\u{8fd9}\u{4e2a}\u{670d}\u{52a1}", .automation)
    ]

    for (goal, expected) in cases {
      XCTAssertEqual(AgentTaskIntentClassifier.classify(goal: goal).intent, expected, goal)
    }
  }

  func testAgentTaskIntentClassifierPrioritizesAutomationAndAvoidsGenericPhoneControl() {
    let automation = AgentTaskIntentClassifier.classify(
      goal: "Turn on the phone flashlight every day at 8"
    )
    let generic = AgentTaskIntentClassifier.classify(
      goal: "Open the app and show me its status"
    )

    XCTAssertEqual(automation.intent, .automation)
    XCTAssertEqual(generic.intent, .chat)
  }

  func testAgentTaskIntentClassifierKeepsFrequencyDescriptionsInChat() {
    let goals = [
      "\u{4e3a}\u{6bcf}\u{5929}\u{53ea}\u{6709}\u{4e8c}\u{5341}\u{5206}\u{949f}\u{7684}\u{4eba}" +
        "\u{5236}\u{5b9a}\u{4e00}\u{5468}\u{7684}\u{82f1}\u{8bed}\u{542c}\u{529b}\u{7ec3}\u{4e60}" +
        "\u{8ba1}\u{5212}\u{ff0c}\u{8981}\u{6c42}\u{53ef}\u{6267}\u{884c}\u{3002}",
      "\u{6bcf}\u{5929}\u{4e00}\u{676f}\u{5496}\u{5561}\u{662f}\u{5426}\u{8fc7}\u{91cf}\u{ff1f}",
      "Compare studying every day with studying every week.",
      "\u{6bcf}\u{5929}\u{8fd0}\u{884c}\u{4e00}\u{6b21}\u{6a21}\u{578b}\u{4f1a}\u{8017}" +
        "\u{591a}\u{5c11}\u{7535}\u{ff1f}"
    ]

    for goal in goals {
      XCTAssertEqual(AgentTaskIntentClassifier.classify(goal: goal).intent, .chat, goal)
    }
  }

  func testAgentTaskIntentClassifierRequiresFrequencyAndConcreteActionForAutomation() {
    let goals = [
      "Run this health check every hour",
      "\u{6bcf}\u{5929}\u{76d1}\u{63a7}\u{8fd9}\u{4e2a}\u{670d}\u{52a1}",
      "\u{6bcf}\u{5468}\u{5907}\u{4efd}\u{8fd9}\u{4e2a}\u{6587}\u{4ef6}\u{5939}"
    ]

    for goal in goals {
      let result = AgentTaskIntentClassifier.classify(goal: goal)
      XCTAssertEqual(result.intent, .automation, goal)
      XCTAssertTrue(result.matchedSignals.contains("scheduled-action"), goal)
    }
  }

  func testAgentTaskIntentClassifierKeepsPhoneTopicsInChatRouting() {
    let writingGoal = "\u{7ed9}\u{79bb}\u{7ebf}\u{4e5f}\u{80fd}\u{5de5}\u{4f5c}\u{7684}\u{624b}\u{673a}\u{667a}\u{80fd}\u{4f53}" +
      "\u{5199}\u{4e00}\u{4e2a}\u{6807}\u{9898}\u{548c}\u{4e00}\u{53e5}\u{526f}\u{6807}\u{9898}"
    let reasoningGoal = "\u{5df2}\u{77e5}\u{6240}\u{6709}\u{79bb}\u{7ebf}\u{6a21}\u{578b}\u{90fd}\u{5728}\u{672c}\u{673a}\u{8fd0}\u{884c}" +
      "\u{ff0c}\u{7ed9}\u{51fa}\u{7ed3}\u{8bba}\u{548c}\u{7406}\u{7531}"
    let explicitControl = "\u{5728}\u{8fd9}\u{90e8}\u{624b}\u{673a}\u{4e0a}\u{6253}\u{5f00}\u{5fae}\u{4fe1}"

    XCTAssertEqual(AgentTaskIntentClassifier.classify(goal: writingGoal).intent, .chat)
    XCTAssertEqual(AgentTaskIntentClassifier.classify(goal: reasoningGoal).intent, .chat)
    XCTAssertEqual(AgentTaskIntentClassifier.classify(goal: explicitControl).intent, .phoneControl)
  }

  func testPhoneRuntimeRequiresExplicitCodeOrProjectOperation() {
    let crashHypothesis = "\u{5e94}\u{7528}\u{5076}\u{53d1}\u{95ea}\u{9000}\u{4e14}\u{53ea}\u{5728}\u{53d1}\u{9001}\u{6587}\u{5b57}\u{65f6}\u{51fa}\u{73b0}" +
      "\u{3002}\u{5217}\u{51fa}\u{4e24}\u{4e2a}\u{4e92}\u{4e0d}\u{91cd}\u{590d}\u{7684}\u{53ef}\u{9a8c}\u{8bc1}\u{5047}\u{8bbe}"

    XCTAssertFalse(AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(goal: crashHypothesis))
    XCTAssertTrue(AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(
      goal: "Continue https://github.com/signalasi/SignalASI on this phone"
    ))
    XCTAssertTrue(AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(
      goal: "Run this Python script locally on the phone and verify it"
    ))
  }

  func testAgentExecutionProfileMatchesAndroidTaskKindsAndTimeouts() {
    let chat = AgentExecutionProfile.forGoal("Hello there")
    let device = AgentExecutionProfile.forGoal("Turn on the flashlight")
    let research = AgentExecutionProfile.forGoal("Research today's AI news")
    let artifact = AgentExecutionProfile.forGoal("Summarize this PDF", hasAttachments: true)
    let build = AgentExecutionProfile.forGoal("Build an Android app and run tests")
    let install = AgentExecutionProfile.forGoal("Install APK on the phone")

    XCTAssertEqual(chat.taskKind, .chat)
    XCTAssertEqual(chat.reasoningEffort, .low)
    XCTAssertEqual(chat.noProgressTimeoutMillis, 180_000)
    XCTAssertFalse(chat.requiresArtifact)

    XCTAssertEqual(device.taskKind, .device)
    XCTAssertEqual(device.reasoningEffort, .low)
    XCTAssertEqual(device.noProgressTimeoutMillis, 120_000)

    XCTAssertEqual(research.taskKind, .research)
    XCTAssertEqual(research.reasoningEffort, .medium)
    XCTAssertEqual(research.noProgressTimeoutMillis, 300_000)

    XCTAssertEqual(artifact.taskKind, .artifact)
    XCTAssertEqual(artifact.noProgressTimeoutMillis, 360_000)
    XCTAssertTrue(artifact.requiresArtifact)
    XCTAssertEqual(artifact.taskIntent, .file)
    XCTAssertTrue(artifact.taskIntentSignals.contains("attachment"))

    XCTAssertEqual(build.taskKind, .build)
    XCTAssertEqual(build.noProgressTimeoutMillis, 420_000)
    XCTAssertTrue(build.requiresArtifact)
    XCTAssertEqual(build.targetPlatform, "android")
    XCTAssertEqual(build.taskIntent, .code)

    XCTAssertEqual(install.taskKind, .install)
    XCTAssertEqual(install.reasoningEffort, .medium)
    XCTAssertEqual(install.noProgressTimeoutMillis, 420_000)
    XCTAssertTrue(install.requiresArtifact)
    XCTAssertTrue(install.verifyInstallation)
    XCTAssertEqual(install.targetPlatform, "android")
  }

  func testAgentExecutionProfileContractUsesTargetRuntimeVerification() throws {
    let profile = AgentExecutionProfile.forGoal("Install APK on the phone")

    XCTAssertTrue(profile.contract.contains("task=install"))
    XCTAssertTrue(profile.contract.contains("reasoning_effort=medium"))
    XCTAssertTrue(profile.contract.contains("A single deliverable remains in its native format"))
    XCTAssertTrue(profile.contract.contains("target runtime returns a verified execution receipt"))
    XCTAssertTrue(profile.contract.contains("Do not report success without verification evidence."))

    let encoded = try JSONEncoder().encode(profile)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    XCTAssertEqual(object["task_kind"] as? String, "INSTALL")
    XCTAssertEqual(object["reasoning_effort"] as? String, "MEDIUM")
    XCTAssertEqual(object["no_progress_timeout_millis"] as? Int, 420_000)
    XCTAssertEqual(object["max_same_failure_attempts"] as? Int, 2)
    XCTAssertEqual(object["requires_artifact"] as? Bool, true)
    XCTAssertEqual(object["target_platform"] as? String, "android")
    XCTAssertEqual(object["verify_installation"] as? Bool, true)
    XCTAssertEqual(object["task_intent"] as? String, "CODE")
    XCTAssertGreaterThanOrEqual(object["task_intent_confidence"] as? Int ?? 0, 55)
  }

  func testAgentRuntimePackCatalogSigningPayloadCodecAndWireNamesMatchAndroid() throws {
    let now: Int64 = 1_750_000_000_000
    let first = runtimeCatalogEntry(packId: "linux-base", architecture: "arm64-v8a")
    let second = runtimeCatalogEntry(
      packId: "python-uv",
      architecture: "arm64-v8a",
      dependencies: ["linux-base"]
    )
    let forward = runtimeCatalog(now: now, entries: [first, second])
    let reversed = runtimeCatalog(now: now, entries: [second, first])

    XCTAssertEqual(forward.signingPayload(), reversed.signingPayload())
    XCTAssertFalse(first.canonicalValue().contains("|"))

    let encoded = try JSONEncoder().encode(forward)
    let decoded = try JSONDecoder().decode(AgentRuntimePackCatalog.self, from: encoded)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let entries = try XCTUnwrap(object["entries"] as? [[String: Any]])

    XCTAssertEqual(decoded, forward)
    XCTAssertEqual(object["format_version"] as? Int, 1)
    XCTAssertEqual(object["catalog_version"] as? String, "1.0.0")
    XCTAssertEqual(object["signature_key_id"] as? String, String(repeating: "a", count: 64))
    XCTAssertEqual(entries.first?["pack_id"] as? String, "linux-base")
    XCTAssertEqual(entries.first?["archive_sha256"] as? String, String(repeating: "b", count: 64))
    XCTAssertEqual((entries.first?["archive_size_bytes"] as? NSNumber)?.int64Value, Int64(1_024))

    let manifest = AgentRuntimePackManifest(
      id: "python-uv",
      version: "1.0.0",
      architecture: "arm64-v8a",
      imageFile: "python.img",
      imageSha256: String(repeating: "c", count: 64),
      capabilities: ["uv.sync", "python.execute"],
      dependencies: ["linux-base"],
      installedSizeBytes: 2_048,
      license: "Apache-2.0",
      signatureKeyId: String(repeating: "d", count: 64),
      signature: "signed",
      archiveSizeBytes: 1_024
    )
    let status = AgentRuntimePackStatus(id: "python-uv", state: .ready, manifest: manifest)
    let install = AgentRuntimePackInstallResult(
      packId: "python-uv",
      version: "1.0.0",
      state: .ready,
      installedBytes: 2_048,
      replacedExisting: true
    )
    let progress = AgentRuntimePackInstallProgress(stage: .verifying, processedBytes: 128, totalBytes: 256)
    let installObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try JSONEncoder().encode(install)) as? [String: Any]
    )

    XCTAssertFalse(manifest.signingPayload().isEmpty)
    XCTAssertEqual(status.manifest, Optional(manifest))
    XCTAssertEqual(installObject["pack_id"] as? String, "python-uv")
    XCTAssertEqual((installObject["installed_bytes"] as? NSNumber)?.int64Value, Int64(2_048))
    XCTAssertEqual(installObject["replaced_existing"] as? Bool, true)
    XCTAssertEqual(installObject["state"] as? String, "ready")
    XCTAssertEqual(progress.stage.rawValue, "VERIFYING")
    XCTAssertEqual(AgentRuntimePackState.fromWireValue("NOT-INSTALLED"), .notInstalled)
    XCTAssertEqual(AgentRuntimeLanguage.typescript.requiredPack, "node-js")
    XCTAssertTrue(AgentRuntimePackCatalogPolicy.requiredPacks.contains("browser-automation"))
    XCTAssertEqual(
      AgentRuntimePackCatalogPolicy.requiredPackCapabilities["ffmpeg"] ?? [],
      Set(["ffmpeg.execute", "ffprobe.inspect"])
    )
  }

  func testAgentRuntimePackCatalogPolicyRejectsDuplicateInsecureExpiredAndUntrustedCatalogs() throws {
    let now: Int64 = 1_750_000_000_000
    let valid = runtimeCatalog(now: now, entries: [
      runtimeCatalogEntry(packId: "linux-base", architecture: "arm64-v8a")
    ])
    let trusted: (AgentRuntimePackCatalog) -> Bool = { _ in true }

    XCTAssertEqual(try AgentRuntimePackCatalogPolicy.validate(valid, nowMillis: now, verifier: trusted), valid)

    var duplicate = valid
    duplicate.entries = [
      valid.entries[0],
      runtimeCatalogEntry(packId: "linux-base", architecture: "arm64-v8a").with(version: "1.0.1")
    ]
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validate(duplicate, nowMillis: now, verifier: trusted))

    var insecure = valid
    insecure.entries = [valid.entries[0].with(downloadUrl: "http://example.com/runtime.sarpack")]
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validate(insecure, nowMillis: now, verifier: trusted))

    var expired = valid
    expired.expiresAtMillis = now - 1
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validate(expired, nowMillis: now, verifier: trusted))

    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validate(valid, nowMillis: now, verifier: { _ in false }))

    let missingDependency = runtimeCatalog(now: now, entries: [
      runtimeCatalogEntry(packId: "python-uv", architecture: "arm64-v8a", dependencies: ["linux-base"])
    ])
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validate(missingDependency, nowMillis: now, verifier: trusted))

    let dependencyCycle = runtimeCatalog(now: now, entries: [
      runtimeCatalogEntry(packId: "linux-base", architecture: "arm64-v8a", dependencies: ["python-uv"]),
      runtimeCatalogEntry(packId: "python-uv", architecture: "arm64-v8a", dependencies: ["linux-base"])
    ])
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validate(dependencyCycle, nowMillis: now, verifier: trusted))
  }

  func testAgentRuntimePackCatalogPolicyChecksReplacementAndCompatibility() throws {
    let now: Int64 = 1_750_000_000_000
    let previous = runtimeCatalog(now: now, entries: [
      runtimeCatalogEntry(packId: "linux-base", architecture: "arm64-v8a")
    ])

    var rollback = previous
    rollback.generatedAtMillis = previous.generatedAtMillis - 1
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validateReplacement(previous: previous, candidate: rollback))

    var reusedGeneration = previous
    reusedGeneration.entries = [previous.entries[0].with(version: "1.0.1")]
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validateReplacement(previous: previous, candidate: reusedGeneration))

    try AgentRuntimePackCatalogPolicy.validateReplacement(previous: previous, candidate: previous)
    var newer = previous
    newer.generatedAtMillis = previous.generatedAtMillis + 1
    try AgentRuntimePackCatalogPolicy.validateReplacement(previous: previous, candidate: newer)

    let compatible = runtimeCatalogEntry(packId: "linux-base", architecture: "arm64-v8a")
    let wrongArchitecture = runtimeCatalogEntry(packId: "python-uv", architecture: "x86_64")
    let futureHost = runtimeCatalogEntry(packId: "node-js", architecture: "arm64-v8a")
      .with(minimumHostVersionCode: 99)
    let wrongGuest = runtimeCatalogEntry(packId: "go", architecture: "arm64-v8a")
      .with(guestApiVersion: AgentRuntimeGuestProtocol.version + 1)
    let catalog = runtimeCatalog(now: now, entries: [compatible, wrongArchitecture, futureHost, wrongGuest])

    XCTAssertEqual(
      AgentRuntimePackCatalogPolicy.compatibleEntries(
        in: catalog,
        supportedArchitectures: ["arm64-v8a"],
        hostVersionCode: 1
      ),
      [compatible]
    )
  }

  func testAgentRuntimeDistributionSourcesUseIOSCatalogAndChineseAccelerators() {
    let official = AgentRuntimeDistributionSources.githubCatalogURL

    XCTAssertTrue(official.contains("/ios-runtime-v1/"))
    XCTAssertFalse(official.contains("/android-runtime-"))
    XCTAssertEqual(AgentRuntimeDistributionSources.catalogCandidates(languageTag: "en-US"), [official])

    let chinese = AgentRuntimeDistributionSources.catalogCandidates(languageTag: "zh-CN")
    XCTAssertEqual(chinese.count, 4)
    XCTAssertEqual(chinese.last ?? "", official)
    XCTAssertTrue(chinese.prefix(3).allSatisfy { $0.hasSuffix(official) })
    XCTAssertEqual(
      AgentRuntimeDistributionSources.downloadCandidates(
        url: "https://downloads.example.com/tool.sarpack",
        languageTag: "zh-CN"
      ),
      ["https://downloads.example.com/tool.sarpack"]
    )
  }

  func testIOSRuntimePolicyRejectsAndroidABI() {
    XCTAssertFalse(AgentRuntimePackCatalogPolicy.defaultSupportedArchitectures.contains("arm64-v8a"))
    XCTAssertFalse(AgentRuntimePackCatalogPolicy.defaultSupportedArchitectures.contains("x86"))
  }

  func testAgentEmbeddedRuntimeBundleCodecRequiresDefaultBootstrapEnvironment() throws {
    let bundle = try AgentEmbeddedRuntimeBundleCodec.decode(embeddedRuntimeIndexJson())
    let encoded = try JSONEncoder().encode(bundle)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let packs = try XCTUnwrap(object["packs"] as? [[String: Any]])

    XCTAssertEqual(bundle.architecture, AgentRuntimePackCatalogPolicy.defaultSupportedArchitectures.first)
    XCTAssertEqual(bundle.formatVersion, 1)
    XCTAssertEqual(bundle.packs.map(\.packId), ["linux-base", "python-uv"])
    XCTAssertEqual(bundle.packs.last?.dependencies, ["linux-base"])
    XCTAssertEqual(bundle.packs.first?.archiveSha256, String(repeating: "a", count: 64))
    XCTAssertEqual(object["format_version"] as? Int, 1)
    XCTAssertEqual(packs.first?["pack_id"] as? String, "linux-base")
    XCTAssertEqual(packs.last?["asset_path"] as? String, "runtime/bootstrap/python-uv.sarpack")
  }

  func testAgentEmbeddedRuntimeBundleCodecRejectsIncompleteDefaultEnvironment() {
    let invalid = """
      {"format_version":1,"architecture":"arm64-v8a","packs":[
        {"pack_id":"linux-base","version":"1.0.0","architecture":"arm64-v8a","asset_path":"runtime/bootstrap/linux-base.sarpack","archive_sha256":"\(String(repeating: "a", count: 64))","archive_size_bytes":1024,"installed_size_bytes":2048,"dependencies":[]}
      ]}
      """

    XCTAssertThrowsError(try AgentEmbeddedRuntimeBundleCodec.decode(invalid))
  }

  func testAgentEmbeddedRuntimeBootstrapVersionComparisonAvoidsDowngrades() {
    XCTAssertEqual(AgentEmbeddedRuntimeBootstrap.compareVersions("1.2.0", "1.1.9"), 1)
    XCTAssertEqual(AgentEmbeddedRuntimeBootstrap.compareVersions("1.2.0", "1.2.0"), 0)
    XCTAssertEqual(AgentEmbeddedRuntimeBootstrap.compareVersions("1.1.9", "1.2.0"), -1)
    XCTAssertEqual(AgentEmbeddedRuntimeBootstrap.compareVersions("1.2.0", "1.2.0-rc.1"), 1)
    XCTAssertEqual(AgentEmbeddedRuntimeBootstrap.compareVersions("1.2.0+build.2", "1.2.0+build.1"), 0)
  }

  func testAgentMcpToolSecurityPolicyMatchesAndroidRiskAndPermissions() {
    let read = AgentMcpToolSecurityPolicy.assess(
      tool: mcpTool("get_weather", readOnly: true),
      arguments: ["city": .string("Shanghai")],
      transport: .streamableHTTP
    )
    let destructive = AgentMcpToolSecurityPolicy.assess(
      tool: mcpTool("delete_project", destructive: true),
      arguments: [
        "project_path": .string("/work"),
        "api_token": .string("secret-value")
      ],
      transport: .localStdio
    )

    XCTAssertEqual(read.risk, .low)
    XCTAssertTrue(read.permissions.contains("mcp.network.connect"))
    XCTAssertEqual(read.publicValue()["risk"], .string("low"))

    XCTAssertEqual(destructive.risk, .high)
    XCTAssertTrue(destructive.permissions.contains("mcp.destructive"))
    XCTAssertTrue(destructive.permissions.contains("mcp.files.access"))
    XCTAssertTrue(destructive.permissions.contains("mcp.secrets.use"))
    XCTAssertTrue(destructive.permissions.contains("mcp.process.execute"))
    XCTAssertEqual(destructive.parameterPreview["api_token"], .string("[REDACTED]"))
    XCTAssertEqual(destructive.inputSha256.count, 64)
  }

  func testAgentMcpToolSecurityPolicyPermissionMatrixMatchesAndroid() {
    let high = AgentMcpToolSecurityPolicy.assess(
      tool: mcpTool("delete_account", destructive: true),
      arguments: [:],
      transport: .streamableHTTP
    )
    let medium = AgentMcpToolSecurityPolicy.assess(
      tool: mcpTool("update_document", readOnly: false),
      arguments: ["content": .string("updated")],
      transport: .streamableHTTP
    )

    XCTAssertFalse(AgentMcpToolSecurityPolicy.decide(mode: .askForChanges, assessment: high, explicitlyApproved: false).allowed)
    XCTAssertTrue(AgentMcpToolSecurityPolicy.decide(mode: .askForChanges, assessment: high, explicitlyApproved: true).allowed)
    XCTAssertFalse(AgentMcpToolSecurityPolicy.decide(mode: .trusted, assessment: high, explicitlyApproved: false).allowed)
    XCTAssertTrue(AgentMcpToolSecurityPolicy.decide(mode: .trusted, assessment: high, explicitlyApproved: true).allowed)
    XCTAssertFalse(AgentMcpToolSecurityPolicy.decide(mode: .askForChanges, assessment: medium, explicitlyApproved: false).allowed)
    XCTAssertTrue(AgentMcpToolSecurityPolicy.decide(mode: .askForChanges, assessment: medium, explicitlyApproved: true).allowed)
    XCTAssertTrue(AgentMcpToolSecurityPolicy.decide(mode: .trusted, assessment: medium, explicitlyApproved: false).allowed)
    XCTAssertFalse(AgentMcpToolSecurityPolicy.decide(mode: .readOnly, assessment: medium, explicitlyApproved: true).allowed)
    XCTAssertEqual(
      AgentMcpToolSecurityPolicy.decide(mode: .disabled, assessment: medium, explicitlyApproved: true).requiredUserAction,
      "enable_connection"
    )
  }

  func testAgentMcpParameterRedactorDropsNestedInlineAndURLSecrets() {
    let sanitized = AgentMcpParameterRedactor.sanitize([
      "password": .string("secret-value"),
      "nested": .object([
        "authorization": .string("Bearer abcdefghijklmnop"),
        "url": .string("https://example.test/action?token=secret#fragment"),
        "note": .string("token=inline-secret")
      ])
    ])
    let serialized = AgentMcpJSONCodec.stringify(sanitized)
    let error = AgentMcpParameterRedactor.sanitizeText(
      "token=inline-secret at https://example.test/mcp?api_key=secret"
    )

    XCTAssertFalse(serialized.contains("secret-value"))
    XCTAssertFalse(serialized.contains("abcdefghijklmnop"))
    XCTAssertFalse(serialized.contains("inline-secret"))
    XCTAssertFalse(serialized.contains("fragment"))
    XCTAssertFalse(error.contains("inline-secret"))
    XCTAssertFalse(error.contains("api_key=secret"))
  }

  func testAgentMcpSecurityModelsUseAndroidWireNamesAndStableJson() throws {
    let mode = try JSONDecoder().decode(AgentMcpPermissionMode.self, from: Data(#""trusted""#.utf8))
    let fallbackMode = try JSONDecoder().decode(AgentMcpPermissionMode.self, from: Data(#""future""#.utf8))
    let tool = try JSONDecoder().decode(
      AgentMcpTool.self,
      from: Data(
        #"""
        {
          "name": "get_status",
          "input_schema": {},
          "annotations": {
            "read_only_hint": true,
            "open_world_hint": true
          },
          "raw": {"name": "get_status"}
        }
        """#.utf8
      )
    )
    let assessment = AgentMcpToolSecurityPolicy.assess(
      tool: tool,
      arguments: ["path": .string("/tmp/report.txt")],
      transport: .streamableHTTP
    )
    let encodedAssessment = String(decoding: try JSONEncoder().encode(assessment), as: UTF8.self)
    let stableJson = AgentMcpJSONCodec.stringify(["b": .int(2), "a": .string("x")])

    XCTAssertEqual(mode, .trusted)
    XCTAssertEqual(fallbackMode, .askForChanges)
    XCTAssertEqual(tool.annotations?["read_only_hint"]?.boolValue, true)
    XCTAssertEqual(assessment.risk, .low)
    XCTAssertTrue(assessment.permissions.contains("mcp.files.access"))
    XCTAssertTrue(assessment.permissions.contains("mcp.network.open_world"))
    XCTAssertTrue(encodedAssessment.contains(#""parameter_preview":"#))
    XCTAssertEqual(stableJson, #"{"a":"x","b":2}"#)
    XCTAssertEqual(AgentMcpToolSecurityPolicy.provisionalRisk(toolName: "get_status"), .low)
    XCTAssertEqual(AgentMcpToolSecurityPolicy.provisionalRisk(toolName: "control_relay"), .medium)
    XCTAssertEqual(AgentMcpToolSecurityPolicy.provisionalRisk(toolName: "delete_device"), .high)
  }

  func testAgentMcpAuditStoreAppendsListsBoundsAndClears() {
    let store = InMemoryAgentMcpAuditStore()
    store.append(mcpAuditRecord("audit-1", connectionId: "conn-a", timestampMillis: 1))
    store.append(mcpAuditRecord("audit-2", connectionId: "conn-b", timestampMillis: 2))
    store.append(mcpAuditRecord("audit-3", connectionId: "conn-a", timestampMillis: 3))

    XCTAssertEqual(store.list(limit: 2).map(\.auditId), ["audit-3", "audit-2"])
    XCTAssertEqual(store.list(connectionId: "conn-a", limit: 10).map(\.auditId), ["audit-3", "audit-1"])
    XCTAssertEqual(store.clear(connectionId: "conn-a"), 2)
    XCTAssertEqual(store.list(limit: 10).map(\.auditId), ["audit-2"])

    let bounded = InMemoryAgentMcpAuditStore()
    for index in 0..<1_005 {
      bounded.append(mcpAuditRecord("bulk-\(index)", connectionId: "bulk", timestampMillis: Int64(index)))
    }
    XCTAssertEqual(bounded.list(limit: 1).first?.auditId, "bulk-1004")
    XCTAssertEqual(bounded.list(limit: 1_000).count, 500)
    XCTAssertEqual(bounded.clear(connectionId: ""), 1_000)
  }

  func testFileAgentMcpAuditStorePersistsAndRecoversRecords() throws {
    let root = try temporaryDirectory("mcp-audit-store")
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("audit/records.json", isDirectory: false)
    let store = FileAgentMcpAuditStore(fileURL: fileURL)

    store.append(mcpAuditRecord("audit-1", connectionId: "conn-a", timestampMillis: 1))
    store.append(mcpAuditRecord("audit-2", connectionId: "conn-b", timestampMillis: 2))
    let restored = FileAgentMcpAuditStore(fileURL: fileURL)

    XCTAssertEqual(restored.list(limit: 10).map(\.auditId), ["audit-2", "audit-1"])
    XCTAssertEqual(restored.clear(connectionId: "conn-a"), 1)
    XCTAssertEqual(FileAgentMcpAuditStore(fileURL: fileURL).list(limit: 10).map(\.auditId), ["audit-2"])

    try "not-json".write(to: fileURL, atomically: true, encoding: .utf8)
    XCTAssertEqual(FileAgentMcpAuditStore(fileURL: fileURL).list(limit: 10), [])
  }

  func testAgentMcpAuditRecordFactoryAndCodecUseAndroidWireNames() throws {
    let connection = AgentMcpConnection(
      id: "conn-a",
      displayName: "Relay",
      endpoint: "https://relay.example/mcp",
      distribution: .remote,
      transport: .streamableHTTP,
      authProfile: try AgentMcpAuthProfile(.none),
      authState: .notRequired,
      permissionMode: .askForChanges
    )
    let assessment = AgentMcpToolSecurityPolicy.assess(
      tool: mcpTool("delete_project", destructive: true),
      arguments: [
        "api_token": .string("secret-value"),
        "url": .string("https://example.test/mcp?api_key=secret")
      ],
      transport: .streamableHTTP
    )
    let decision = AgentMcpToolSecurityPolicy.decide(
      mode: .askForChanges,
      assessment: assessment,
      explicitlyApproved: false
    )
    let context = AgentNativeToolInvocationContext(
      conversationId: "chat-1",
      callerId: "planner",
      attributes: ["task_id": "task-1"]
    )

    let record = AgentMcpAuditRecord.toolCall(
      connection: connection,
      toolName: "delete_project",
      assessment: assessment,
      decision: decision,
      context: context,
      status: "failed",
      durationMillis: -5,
      outputSha256: String(repeating: "b", count: 64),
      errorCode: "mcp_call_failed",
      errorMessage: "token=inline-secret at https://example.test/mcp?api_key=secret",
      auditId: "audit-fixed",
      timestampMillis: 12_345
    )
    let encoded = AgentMcpAuditCodec.encode([record])
    let decoded = try XCTUnwrap(AgentMcpAuditCodec.decode(encoded).first)

    XCTAssertEqual(record.source, "ios-mcp:conn-a")
    XCTAssertEqual(record.durationMillis, 0)
    XCTAssertEqual(record.permissions, assessment.permissions.sorted())
    XCTAssertEqual(record.parameterPreview["api_token"], .string("[REDACTED]"))
    XCTAssertTrue(encoded.contains(#""audit_id":"audit-fixed""#))
    XCTAssertTrue(encoded.contains(#""timestamp_ms":12345"#))
    XCTAssertTrue(encoded.contains(#""permission_decision":"mcp_high_risk_approval_required""#))
    XCTAssertFalse(encoded.contains("secret-value"))
    XCTAssertFalse(encoded.contains("inline-secret"))
    XCTAssertFalse(encoded.contains("api_key=secret"))
    XCTAssertEqual(decoded.auditId, "audit-fixed")
    XCTAssertEqual(decoded.connectionId, "conn-a")
    XCTAssertEqual(decoded.taskId, "task-1")
    XCTAssertEqual(decoded.conversationId, "chat-1")
    XCTAssertEqual(decoded.risk, "high")
    XCTAssertEqual(decoded.errorCode, "mcp_call_failed")
  }

  func testUnifiedCommandProtocolRequestPayloadUsesAndroidDesktopMqttContract() throws {
    let payload = try UnifiedCommandProtocol.requestPayload(
      commandId: "commands.list",
      args: ["dry_run": .bool(true)],
      messageId: "message-1"
    )

    XCTAssertEqual(payload["type"]?.stringValue, UnifiedCommandProtocol.requestType)
    XCTAssertEqual(payload["message_id"]?.stringValue, "message-1")
    XCTAssertEqual(payload["source_message_id"]?.stringValue, "message-1")
    XCTAssertEqual(payload["contact_id"]?.stringValue, "system")
    XCTAssertEqual(payload["command_id"]?.stringValue, "commands.list")
    XCTAssertEqual(payload["args"]?.objectValue?["dry_run"]?.boolValue, true)
    XCTAssertEqual(payload["requested_by"]?.stringValue, "paired_phone")
    XCTAssertEqual(payload["approve"]?.boolValue, false)
  }

  func testUnifiedCommandProtocolSlashPayloadCanOmitCommandIdAndRejectsBlankRequests() throws {
    let payload = try UnifiedCommandProtocol.requestPayload(
      commandId: "",
      slash: "/commands",
      messageId: "message-2"
    )

    XCTAssertEqual(payload["command_id"]?.stringValue, "")
    XCTAssertEqual(payload["slash"]?.stringValue, "/commands")
    XCTAssertThrowsError(
      try UnifiedCommandProtocol.requestPayload(commandId: "", raw: "  ", slash: "")
    ) { error in
      XCTAssertEqual(error as? UnifiedCommandProtocolError, .missingCommand)
    }
  }

  func testUnifiedCommandProtocolDecodesStructuredCommandResult() throws {
    let payload: AgentMcpJSONObject = [
      "type": .string("unified_command_result"),
      "command_id": .string("commands.list"),
      "command_status": .string("completed"),
      "source_message_id": .string("message-1"),
      "result": .object([
        "status": .string("completed"),
        "command_id": .string("commands.list"),
        "run_id": .string("run-1"),
        "data": .object(["catalog_size": .int(753)]),
        "display": .object(["type": .string("command_list")])
      ])
    ]

    let result = try XCTUnwrap(UnifiedCommandProtocol.decodeResult(payload))

    XCTAssertEqual(result.commandId, "commands.list")
    XCTAssertEqual(result.status, "completed")
    XCTAssertEqual(result.runId, "run-1")
    XCTAssertEqual(result.sourceMessageId, "message-1")
    XCTAssertEqual(result.data["catalog_size"]?.intValue, 753)
    XCTAssertEqual(result.display["type"]?.stringValue, "command_list")
  }

  func testUnifiedCommandProtocolIgnoresOtherPayloadTypesAndUsesResultFallbacks() throws {
    XCTAssertNil(UnifiedCommandProtocol.decodeResult(["type": .string("text")]))

    let result = try XCTUnwrap(
      UnifiedCommandProtocol.decodeResult([
        "type": .string("unified_command_result"),
        "source_message_id": .string("message-fallback"),
        "result": .object([
          "status": .string("failed"),
          "command_id": .string("commands.run"),
          "error_code": .string("command_failed"),
          "message": .string("Command failed")
        ])
      ])
    )

    XCTAssertEqual(result.commandId, "commands.run")
    XCTAssertEqual(result.status, "failed")
    XCTAssertEqual(result.errorCode, "command_failed")
    XCTAssertEqual(result.message, "Command failed")
  }

  func testUnifiedCommandResultUsesAndroidWireNames() throws {
    let result = UnifiedCommandResult(
      commandId: "commands.list",
      status: "completed",
      runId: "run-1",
      sourceMessageId: "message-1",
      data: ["catalog_size": .int(753)],
      display: ["type": .string("command_list")]
    )
    let encoded = String(decoding: try JSONEncoder.signalASI.encode(result), as: UTF8.self)

    XCTAssertTrue(encoded.contains(#""command_id":"commands.list""#))
    XCTAssertTrue(encoded.contains(#""run_id":"run-1""#))
    XCTAssertTrue(encoded.contains(#""source_message_id":"message-1""#))
    XCTAssertTrue(encoded.contains(#""catalog_size":753"#))
  }

  func testAgentFailureRecoveryPayloadRoundTripsAndroidWireNames() throws {
    let payload = AgentFailureRecoveryPayload(
      action: .switchAgent,
      taskId: "task-1",
      conversationId: "conversation-1",
      turnId: "turn-1",
      agentId: "codex",
      originalGoal: "Build the project",
      failure: "Codex is unavailable"
    )

    let decoded = try XCTUnwrap(AgentFailureRecoveryPayload.decode(payload.encode()))
    let encodedObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(payload.encode().utf8)) as? [String: Any]
    )

    XCTAssertEqual(decoded, payload)
    XCTAssertNil(AgentFailureRecoveryPayload.decode("{}"))
    XCTAssertEqual(encodedObject["version"] as? Int, 1)
    XCTAssertEqual(encodedObject["action"] as? String, "switch_agent")
    XCTAssertEqual(encodedObject["task_id"] as? String, "task-1")
    XCTAssertEqual(AgentFailureRecoveryAction.fromWireValue(" SWITCH_AGENT "), .switchAgent)
  }

  func testAgentFailureRecoveryPayloadBoundsRecoveryContext() throws {
    let payload = AgentFailureRecoveryPayload(
      action: .retry,
      taskId: String(repeating: "t", count: 200),
      conversationId: String(repeating: "c", count: 200),
      turnId: String(repeating: "u", count: 200),
      agentId: String(repeating: "a", count: 200),
      originalGoal: String(repeating: "g", count: 17_000),
      failure: String(repeating: "f", count: 2_500)
    )
    let decoded = try XCTUnwrap(AgentFailureRecoveryPayload.decode(payload.encode()))

    XCTAssertEqual(decoded.taskId.count, 160)
    XCTAssertEqual(decoded.conversationId.count, 160)
    XCTAssertEqual(decoded.turnId.count, 160)
    XCTAssertEqual(decoded.agentId.count, 160)
    XCTAssertEqual(decoded.originalGoal.count, 16_000)
    XCTAssertEqual(decoded.failure.count, 2_000)
  }

  func testAgentFailureRecoveryPolicyRecommendsAndroidRecoveryPaths() {
    XCTAssertEqual(
      AgentFailureRecoveryPolicy.recommended(status: "timed_out", failure: "Execution timed out"),
      .retry
    )
    XCTAssertEqual(
      AgentFailureRecoveryPolicy.recommended(status: "failed", failure: "Agent unavailable"),
      .switchAgent
    )
    XCTAssertEqual(
      AgentFailureRecoveryPolicy.recommended(status: "failed", failure: "Verification failed"),
      .degrade
    )
    XCTAssertEqual(
      AgentFailureRecoveryPolicy.recommended(status: "failed", failure: "Permanent failure"),
      .diagnostics
    )
    XCTAssertEqual(AgentFailureRecoveryPolicy.executionMode(for: .degrade), .planOnly)
    XCTAssertEqual(AgentFailureRecoveryPolicy.executionMode(for: .diagnostics), .planOnly)
    XCTAssertNil(AgentFailureRecoveryPolicy.executionMode(for: .retry))
  }

  func testAgentFailureRecoveryInstructionPreservesGoalFailureAndLanguageHint() {
    let instruction = AgentFailureRecoveryPolicy.instruction(
      payload: AgentFailureRecoveryPayload(
        action: .retry,
        taskId: "task-1",
        conversationId: "conversation-1",
        turnId: "turn-1",
        agentId: "codex",
        originalGoal: "Build the app",
        failure: "Network unavailable"
      ),
      chinese: true
    )

    XCTAssertTrue(instruction.contains("latest safe checkpoint"))
    XCTAssertTrue(instruction.contains("Respond in Simplified Chinese."))
    XCTAssertTrue(instruction.contains("Build the app"))
    XCTAssertTrue(instruction.contains("Network unavailable"))
  }

  func testCodexStyleResponsePolicyCoversLanguageActionClarificationAndFailures() {
    let policy = CodexStyleResponsePolicy.promptText
    let preferred = CodexStyleResponsePolicy.preferredPrompt(languageTag: "zh-Hans-CN", languageName: "Simplified Chinese")
    let clarification = CodexStyleResponsePolicy.attachmentClarification(names: ["report.pdf", "report.pdf", "chart.png"])

    XCTAssertTrue(policy.contains("Simplified Chinese"))
    XCTAssertTrue(policy.contains("execute it"))
    XCTAssertTrue(policy.contains("ask only the most important question"))
    XCTAssertTrue(policy.contains("Never return a raw exception or stack trace"))
    XCTAssertTrue(policy.contains("never reproduce the input files as assistant artifacts"))
    XCTAssertTrue(preferred.contains("Preferred response language: Simplified Chinese (zh-Hans-CN)"))
    XCTAssertTrue(clarification.contains("report.pdf, chart.png"))
  }

  func testCodexStyleResponsePolicyDropsInputArtifactsButKeepsGeneratedFiles() throws {
    let raw = richDocument([
      [
        "id": "input",
        "type": "file",
        "title": "test.xlsx",
        "uri": "signalasi-artifact://task/downloads/input/01-test.xlsx"
      ],
      [
        "id": "output",
        "type": "file",
        "title": "summary.csv",
        "uri": "signalasi-artifact://task/outputs/summary.csv"
      ]
    ])

    let blocks = try richBlocks(CodexStyleResponsePolicy.filterAssistantRichOutput(raw))

    XCTAssertEqual(blocks.count, 1)
    XCTAssertEqual(blocks.first?["title"] as? String, "summary.csv")
  }

  func testCodexStyleResponsePolicyKeepsHostOwnedConversationActions() throws {
    let raw = richDocument([
      [
        "id": "notice",
        "type": "notice",
        "text": "A focused topic workspace is ready."
      ],
      [
        "id": "actions",
        "type": "actions",
        "actions": [
          [
            "id": "open",
            "label": "Open topic",
            "verb": "open_conversation",
            "value": "conversation-id"
          ]
        ]
      ]
    ])

    let blocks = try richBlocks(CodexStyleResponsePolicy.filterAssistantRichOutput(raw))
    let actions = try XCTUnwrap(blocks.last?["actions"] as? [[String: Any]])

    XCTAssertEqual(blocks.compactMap { $0["id"] as? String }, ["notice", "actions"])
    XCTAssertEqual(actions.first?["verb"] as? String, "open_conversation")
  }

  func testCodexStyleResponsePolicySanitizesToolChatterAndStackFrames() {
    let raw = """
    preparing mcp_fetch
    Useful result
    at com.signalasi.Internal.run(Internal.kt:10)
    """

    XCTAssertEqual(CodexStyleResponsePolicy.sanitizeAssistantText(raw), "Useful result")
  }

  func testCodexStyleResponsePolicyDropsDuplicatePhoneRuntimeVerification() throws {
    let text = [
      "\u{5df2}\u{5199}\u{597d}\u{5e76}\u{5728}\u{624b}\u{673a}\u{672c}\u{673a} Linux \u{4e2d}\u{9a8c}\u{8bc1}\u{901a}\u{8fc7}\u{3002}",
      "",
      "\u{8fd0}\u{884c}\u{7ed3}\u{679c}\u{ff1a}",
      "",
      "```text",
      "5050",
      "```",
      "",
      "\u{9a8c}\u{8bc1}\u{7ed3}\u{679c}\u{ff1a}",
      "",
      "```text",
      "\u{901a}\u{8fc7}\u{ff08}\u{9000}\u{51fa}\u{7801} 0\u{ff09}",
      "```"
    ].joined(separator: "\n")
    let clean = CodexStyleResponsePolicy.sanitizeAssistantText(text)
    XCTAssertTrue(clean.contains("5050"))
    XCTAssertFalse(clean.contains("\u{5df2}\u{5199}\u{597d}"))
    XCTAssertFalse(clean.contains("\u{9a8c}\u{8bc1}\u{7ed3}\u{679c}"))
    XCTAssertFalse(clean.contains("\u{9000}\u{51fa}\u{7801}"))

    let rich = richDocument([
      [
        "id": "heading",
        "type": "text",
        "text": "\u{5df2}\u{5199}\u{597d}\u{5e76}\u{5728}\u{624b}\u{673a}\u{672c}\u{673a} Linux \u{4e2d}\u{9a8c}\u{8bc1}\u{901a}\u{8fc7}\u{3002}"
      ],
      [
        "id": "run-heading",
        "type": "text",
        "text": "\u{8fd0}\u{884c}\u{7ed3}\u{679c}\u{ff1a}"
      ],
      [
        "id": "run",
        "type": "code",
        "text": "5050",
        "language": "text"
      ],
      [
        "id": "verify-heading",
        "type": "text",
        "text": "\u{9a8c}\u{8bc1}\u{7ed3}\u{679c}\u{ff1a}"
      ],
      [
        "id": "verify",
        "type": "code",
        "text": "\u{901a}\u{8fc7}\u{ff08}\u{9000}\u{51fa}\u{7801} 0\u{ff09}",
        "language": "text"
      ]
    ])
    let blocks = try richBlocks(CodexStyleResponsePolicy.filterAssistantRichOutput(rich))

    XCTAssertEqual(blocks.compactMap { $0["id"] as? String }, ["run-heading", "run"])
  }

  func testDeliveryTraceStageLabelsMatchAndroidActions() {
    XCTAssertEqual(DeliveryTraceEvent(stage: "mqtt_published").displayTitle, "Published to MQTT")
    XCTAssertEqual(DeliveryTraceEvent(stage: "desktop_decrypted").displayTitle, "Desktop decrypted")
    XCTAssertEqual(DeliveryTraceEvent(stage: "cloud_request").displayTitle, "Model request")
    XCTAssertEqual(DeliveryTraceEvent(stage: "agent_accepted").displayTitle, "Accepted")
    XCTAssertEqual(DeliveryTraceEvent(stage: "agent_running").displayTitle, "Running")
    XCTAssertEqual(DeliveryTraceEvent(stage: "agent_waiting_input").displayTitle, "Waiting for input")
    XCTAssertEqual(DeliveryTraceEvent(stage: "agent_completed").displayTitle, "Completed")
    XCTAssertEqual(DeliveryTraceEvent(stage: "agent_timed_out").displayTitle, "Timed out")
    XCTAssertEqual(DeliveryTraceEvent(stage: "local_saved").displayTitle, "Saved locally")
    XCTAssertEqual(DeliveryTraceEvent(stage: "unknown_stage").displayTitle, "unknown_stage")
  }

  func testMessageStatusUpdatesExposeReadableDeliveryTrace() {
    let store = makeStore()
    let message = store.appendOutgoing("hello", to: "hermes")

    store.markMessage(message.id, contactId: "hermes", status: .sent, detail: "QoS accepted")

    let updated = store.messages(for: "hermes").first { $0.id == message.id }
    XCTAssertEqual(updated?.deliveryTrace.map(\.displayTitle), ["Queued", "Sent"])
    XCTAssertEqual(updated?.deliveryTrace.last?.detail, "QoS accepted")
  }

  func testAppendDeliveryTraceUpdatesStatusAndKeepsPriorStages() {
    let store = makeStore()
    let message = store.appendOutgoing("hello", to: "hermes")

    XCTAssertTrue(store.appendDeliveryTrace(
      message.id,
      contactId: "hermes",
      stage: "mqtt_published",
      detail: "signalasi/topic",
      status: .sent
    ))

    let updated = store.messages(for: "hermes").first { $0.id == message.id }
    XCTAssertEqual(updated?.deliveryStatus, .sent)
    XCTAssertEqual(updated?.deliveryTrace.map(\.stage), ["queued", "mqtt_published"])
    XCTAssertEqual(updated?.deliveryTrace.last?.detail, "signalasi/topic")
  }

  func testDeletingHermesClearsServerLinks() throws {
    let store = makeStore()
    _ = try store.addServerLink(from: makePairingQRCode())

    XCTAssertEqual(store.serverLinks.count, 1)
    XCTAssertTrue(store.deleteContact(id: "hermes"))

    XCTAssertTrue(store.serverLinks.isEmpty)
    XCTAssertEqual(store.contact(id: "hermes")?.trustState, .deleted)
  }

  func testDestroyAllPrivateDataRegeneratesIdentityAndClearsSecrets() throws {
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)
    let originalSignalASIId = store.profile.signalASIId
    let originalIdentitySecret = secrets.string(account: "identity.p256.private")
    let contact = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "secret-key",
      apiStyle: .openAICompatible
    )
    let keychainAccount = contact.cloudModels[0].keychainAccount
    _ = try store.addServerLink(from: makePairingQRCode())
    store.appendOutgoing("private note", to: "hermes")
    store.updateVoiceSettings { settings in
      settings.wakeListeningEnabled = true
    }
    store.updateDisplaySettings {
      $0.textScale = .extraLarge
    }
    store.updateAgentSafetySettings {
      $0.taskExecutionMode = .planOnly
      $0.permissionMode = .observeOnly
      $0.executionPaused = true
    }
    store.selectAgentTaskBudgetProfile(.privateMode)
    store.upsertCustomDeviceConnector(
      CustomDeviceConnector(
        id: "custom-device-office",
        name: "Office Light",
        transport: .mqtt,
        endpoint: "mqtt://broker.local",
        authToken: "token"
      )
    )
    store.updateHomeAssistantSettings {
      $0.enabled = true
      $0.baseUrl = "http://homeassistant.local:8123"
      $0.accessToken = "ha-token"
      $0.defaultEntityId = "light.office"
    }
    store.updateModelPlannerSettings {
      $0.enabled = true
      $0.maxActions = 12
    }

    store.destroyAllPrivateData()

    XCTAssertNotEqual(store.profile.signalASIId, originalSignalASIId)
    XCTAssertNotEqual(secrets.string(account: "identity.p256.private"), originalIdentitySecret)
    XCTAssertNil(secrets.string(account: keychainAccount))
    XCTAssertNotNil(store.contact(id: "hermes"))
    XCTAssertNil(store.contact(id: "cloud:openai"))
    XCTAssertTrue(store.friendRequests.isEmpty)
    XCTAssertTrue(store.serverLinks.isEmpty)
    XCTAssertEqual(store.messages(for: "hermes").count, 1)
    XCTAssertEqual(store.voiceSettings, .default)
    XCTAssertEqual(store.displaySettings, .default)
    XCTAssertEqual(store.agentSafetySettings, .default)
    XCTAssertEqual(store.agentTaskBudget, .default)
    XCTAssertTrue(store.customDeviceConnectors.isEmpty)
    XCTAssertNil(secrets.string(account: "custom_device_connector.custom-device-office.auth_token"))
    XCTAssertEqual(store.homeAssistantSettings, .default)
    XCTAssertNil(secrets.string(account: "home_assistant.access_token"))
    XCTAssertEqual(store.modelPlannerSettings, .default)
  }

  func testSelectingCloudModelChangesProviderActiveModel() throws {
    let store = makeStore()

    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )
    _ = try store.addCloudModelContact(
      displayName: "Model B",
      provider: "OpenAI",
      modelId: "model-b",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "key-b",
      apiStyle: .openAICompatible
    )

    XCTAssertTrue(store.setSelectedCloudModel(contactId: "cloud:openai", modelId: "model-b"))

    let contact = store.contact(id: "cloud:openai")
    XCTAssertEqual(contact?.selectedCloudModelId, "model-b")
    XCTAssertEqual(contact?.selectedCloudModel?.displayName, "Model B")
  }

  func testDeletingSelectedCloudModelRemovesSecretAndFallsBack() throws {
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)
    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )
    _ = try store.addCloudModelContact(
      displayName: "Model B",
      provider: "OpenAI",
      modelId: "model-b",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "key-b",
      apiStyle: .openAICompatible
    )
    XCTAssertTrue(store.setSelectedCloudModel(contactId: "cloud:openai", modelId: "model-b"))
    let removedAccount = store.contact(id: "cloud:openai")!.cloudModels[1].keychainAccount

    XCTAssertTrue(store.deleteCloudModel(contactId: "cloud:openai", modelId: "model-b"))

    let contact = store.contact(id: "cloud:openai")
    XCTAssertNil(secrets.string(account: removedAccount))
    XCTAssertEqual(contact?.cloudModels.map(\.modelId), ["model-a"])
    XCTAssertEqual(contact?.selectedCloudModelId, "model-a")
    XCTAssertEqual(contact?.deleted, false)
  }
  func testDeletingLastCloudModelHidesProviderContact() throws {
    let store = makeStore()
    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )

    XCTAssertTrue(store.deleteCloudModel(contactId: "cloud:openai", modelId: "model-a"))

    XCTAssertEqual(store.contact(id: "cloud:openai")?.deleted, true)
    XCTAssertTrue(store.cloudModelContacts.isEmpty)
  }

  func testCloudModelCredentialPolicyRejectsPlaceholders() {
    XCTAssertFalse(CloudModelCredentialPolicy.isStoredCredential(""))
    XCTAssertFalse(CloudModelCredentialPolicy.isStoredCredential("****-key"))
    XCTAssertFalse(CloudModelCredentialPolicy.isStoredCredential("your-api-key"))
    XCTAssertFalse(CloudModelCredentialPolicy.isAutoRoutableCredential("sk-signalasi-smoke-key"))
    XCTAssertTrue(CloudModelCredentialPolicy.isStoredCredential("sk-live-key"))
  }

  func testAgentConnectorAvailabilityMatchesAndroidDesktopStatusRules() {
    let now: Int64 = 20_000_000

    XCTAssertTrue(
      AgentConnectorAvailability.desktopAgentReady(setupStatus: "ready", setupUpdatedAtMillis: now, nowMillis: now)
    )
    XCTAssertTrue(
      AgentConnectorAvailability.desktopAgentReady(setupStatus: "busy", setupUpdatedAtMillis: now, nowMillis: now)
    )
    XCTAssertFalse(
      AgentConnectorAvailability.desktopAgentReady(setupStatus: "degraded", setupUpdatedAtMillis: now, nowMillis: now)
    )
    XCTAssertFalse(
      AgentConnectorAvailability.desktopAgentReady(setupStatus: "needs_setup", setupUpdatedAtMillis: now, nowMillis: now)
    )
    XCTAssertFalse(
      AgentConnectorAvailability.desktopAgentReady(setupStatus: "unavailable", setupUpdatedAtMillis: now, nowMillis: now)
    )
    XCTAssertFalse(
      AgentConnectorAvailability.desktopAgentReady(
        setupStatus: "ready",
        setupUpdatedAtMillis: now - AgentConnectorAvailability.desktopStatusTtlMillis - 1,
        nowMillis: now
      )
    )
    XCTAssertTrue(
      AgentConnectorAvailability.desktopAgentReady(
        setupStatus: "ready",
        setupUpdatedAtMillis: now - AgentConnectorAvailability.desktopStatusTtlMillis,
        nowMillis: now
      )
    )
    XCTAssertFalse(
      AgentConnectorAvailability.desktopAgentReady(setupStatus: "ready", setupUpdatedAtMillis: 0, nowMillis: now)
    )
    XCTAssertTrue(
      AgentConnectorAvailability.desktopAgentReady(
        setupStatus: "ready",
        setupUpdatedAtMillis: now + 60_000,
        nowMillis: now
      )
    )
    XCTAssertFalse(
      AgentConnectorAvailability.desktopAgentReady(
        setupStatus: "ready",
        setupUpdatedAtMillis: now + 60_001,
        nowMillis: now
      )
    )

    var contact = SignalASIContact.hermes()
    contact.setupStatus = "busy"
    contact.updatedAt = Date(timeIntervalSince1970: Double(now) / 1_000)
    XCTAssertTrue(
      AgentConnectorAvailability.desktopAgentReady(
        contact: contact,
        now: Date(timeIntervalSince1970: Double(now) / 1_000)
      )
    )
  }

  func testConnectorStatusControlPacketsAreAlwaysSilent() {
    XCTAssertTrue(SignalASIConnectorControlMessagePolicy.isSilentStatus(type: "connector_status"))
    XCTAssertFalse(SignalASIConnectorControlMessagePolicy.isSilentStatus(type: "pairing_confirmed"))
    XCTAssertFalse(SignalASIConnectorControlMessagePolicy.isSilentStatus(type: "agent_task_event"))
  }

  func testAgentConnectorAvailabilityMatchesAndroidCloudModelReadiness() {
    let complete = CloudModelConfig(
      id: "deepseek-v4",
      displayName: "DeepSeek V4",
      provider: "deepseek",
      modelId: "deepseek-v4",
      endpoint: "https://api.example.test/v1/chat/completions",
      apiStyle: .openAICompatible,
      keychainAccount: "cloud.deepseek.deepseek-v4",
      updatedAt: Date()
    )

    XCTAssertTrue(
      AgentConnectorAvailability.cloudModelReady(
        model: complete,
        apiKey: "secret",
        provider: "deepseek",
        setupStatus: "ready"
      )
    )
    XCTAssertFalse(AgentConnectorAvailability.cloudModelReady(model: complete, apiKey: "", provider: "deepseek"))
    XCTAssertFalse(AgentConnectorAvailability.cloudModelReady(model: complete, apiKey: "****-key", provider: "deepseek"))
    XCTAssertFalse(
      AgentConnectorAvailability.cloudModelReady(model: complete, apiKey: "sk-signalasi-smoke-key", provider: "deepseek")
    )
    XCTAssertFalse(
      AgentConnectorAvailability.cloudModelReady(
        model: CloudModelConfig(
          id: "blank-model",
          displayName: "Blank",
          provider: "deepseek",
          modelId: "",
          endpoint: complete.endpoint,
          apiStyle: .openAICompatible,
          keychainAccount: "blank",
          updatedAt: Date()
        ),
        apiKey: "secret",
        provider: "deepseek"
      )
    )
    XCTAssertFalse(
      AgentConnectorAvailability.cloudModelReady(
        model: CloudModelConfig(
          id: "example-endpoint",
          displayName: "Example",
          provider: "deepseek",
          modelId: "deepseek-v4",
          endpoint: "https://api.example.com/v1/chat/completions",
          apiStyle: .openAICompatible,
          keychainAccount: "example",
          updatedAt: Date()
        ),
        apiKey: "secret",
        provider: "deepseek"
      )
    )
    XCTAssertFalse(
      AgentConnectorAvailability.cloudModelReady(
        model: complete,
        apiKey: "secret",
        provider: "deepseek",
        setupStatus: "needs_setup"
      )
    )

    var contact = SignalASIContact.system()
    contact.deliveryMode = .cloudAPI
    contact.setupStatus = "ready"
    contact.cloudProvider = "deepseek"
    contact.cloudModels = [complete]
    contact.selectedCloudModelId = "deepseek-v4"
    XCTAssertTrue(AgentConnectorAvailability.cloudModelReady(contact: contact, apiKey: "secret"))
    contact.cloudModels = []
    XCTAssertFalse(AgentConnectorAvailability.cloudModelReady(contact: contact, apiKey: "secret"))
  }

  func testCloudClientRejectsPlaceholderCredentialBeforeNetwork() async throws {
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)
    let contact = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "sk-live-key",
      apiStyle: .openAICompatible
    )
    let model = contact.cloudModels[0]
    try secrets.setString("your-api-key", account: model.keychainAccount)

    do {
      _ = try await CloudModelClient().send(
        contact: store.contact(id: "cloud:openai")!,
        store: store,
        turns: [ChatMessage(contactId: "cloud:openai", content: "hello", isMine: true)]
      )
      XCTFail("Expected placeholder credentials to fail before a network request.")
    } catch SignalASIError.missingAPIKey {
      XCTAssertTrue(true)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

}
