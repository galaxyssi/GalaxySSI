import Foundation
#if canImport(Contacts)
import Contacts
#endif

protocol AgentIOSContactsWriteProviding {
  func upsertContact(
    contactId: Int64,
    displayName: String,
    phoneNumber: String,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult
  func deleteContact(contactId: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult
}

struct AgentIOSDefaultContactsWriteProvider: AgentIOSContactsWriteProviding {
  func upsertContact(
    contactId: Int64,
    displayName: String,
    phoneNumber: String,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult {
    let name = bounded(displayName, 160)
    let phone = bounded(phoneNumber, 64)
    guard !name.isEmpty else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_contact",
        message: "Contact display name is empty"
      )
    }

    #if canImport(Contacts)
    let authorization = CNContactStore.authorizationStatus(for: .contacts)
    guard isContactsAuthorized(authorization) else {
      return AgentNativeToolExecutionResult.failure(
        code: "contacts_permission_required",
        message: "iOS Contacts permission is required before contacts can be changed."
      )
    }

    let store = CNContactStore()
    do {
      if contactId <= 0 {
        return try createContact(
          store: store,
          displayName: name,
          phoneNumber: phone,
          authorization: authorization,
          nowMillis: nowMillis
        )
      }
      return try updateContact(
        store: store,
        contactId: contactId,
        displayName: name,
        phoneNumber: phone,
        authorization: authorization,
        nowMillis: nowMillis
      )
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "contacts_write_failed",
        message: "iOS Contacts write failed."
      )
    }
    #else
    return AgentNativeToolExecutionResult.failure(
      code: "contacts_framework_unavailable",
      message: "Contacts framework is unavailable on this platform."
    )
    #endif
  }

  func deleteContact(contactId: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    guard contactId > 0 else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_contact_id",
        message: "Contact id must be positive."
      )
    }

    #if canImport(Contacts)
    let authorization = CNContactStore.authorizationStatus(for: .contacts)
    guard isContactsAuthorized(authorization) else {
      return AgentNativeToolExecutionResult.failure(
        code: "contacts_permission_required",
        message: "iOS Contacts permission is required before contacts can be deleted."
      )
    }

    let store = CNContactStore()
    do {
      guard let contact = try findMutableContact(store: store, contactId: contactId) else {
        return AgentNativeToolExecutionResult.success(
          output: commonOutput(
            [
              "contact_id": .int(contactId),
              "deleted_rows": .int(0),
              "contact_found": .bool(false)
            ],
            authorization: authorization,
            nowMillis: nowMillis
          ),
          message: "Contact delete completed"
        )
      }
      let request = CNSaveRequest()
      request.delete(contact)
      try store.execute(request)
      return AgentNativeToolExecutionResult.success(
        output: commonOutput(
          [
            "contact_id": .int(contactId),
            "deleted_rows": .int(1),
            "contact_found": .bool(true)
          ],
          authorization: authorization,
          nowMillis: nowMillis
        ),
        message: "Contact delete completed"
      )
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "contacts_delete_failed",
        message: "iOS Contacts delete failed."
      )
    }
    #else
    return AgentNativeToolExecutionResult.failure(
      code: "contacts_framework_unavailable",
      message: "Contacts framework is unavailable on this platform."
    )
    #endif
  }

  #if canImport(Contacts)
  private func createContact(
    store: CNContactStore,
    displayName: String,
    phoneNumber: String,
    authorization: CNAuthorizationStatus,
    nowMillis: Int64
  ) throws -> AgentNativeToolExecutionResult {
    let contact = CNMutableContact()
    contact.givenName = displayName
    if !phoneNumber.isEmpty {
      contact.phoneNumbers = [
        CNLabeledValue(
          label: CNLabelPhoneNumberMobile,
          value: CNPhoneNumber(stringValue: phoneNumber)
        )
      ]
    }
    let request = CNSaveRequest()
    request.add(contact, toContainerWithIdentifier: nil)
    try store.execute(request)
    let syntheticId = try createdContactId(
      contact: contact,
      store: store,
      displayName: displayName,
      phoneNumber: phoneNumber,
      nowMillis: nowMillis
    )
    return AgentNativeToolExecutionResult.success(
      output: commonOutput(
        [
          "raw_contact_id": .int(syntheticId),
          "contact_id": .int(syntheticId),
          "display_name": .string(displayName),
          "phone_number": .string(phoneNumber),
          "created": .bool(true)
        ],
        authorization: authorization,
        nowMillis: nowMillis
      ),
      message: "Contact created"
    )
  }

  private func updateContact(
    store: CNContactStore,
    contactId: Int64,
    displayName: String,
    phoneNumber: String,
    authorization: CNAuthorizationStatus,
    nowMillis: Int64
  ) throws -> AgentNativeToolExecutionResult {
    guard let contact = try findMutableContact(store: store, contactId: contactId) else {
      return AgentNativeToolExecutionResult.success(
        output: commonOutput(
          [
            "contact_id": .int(contactId),
            "updated_name_rows": .int(0),
            "updated_phone_rows": .int(0),
            "contact_found": .bool(false)
          ],
          authorization: authorization,
          nowMillis: nowMillis
        ),
        message: "Contact updated"
      )
    }

    contact.givenName = displayName
    contact.middleName = ""
    contact.familyName = ""
    contact.organizationName = ""

    let updatedPhoneRows: Int64
    if phoneNumber.isEmpty {
      updatedPhoneRows = 0
    } else if contact.phoneNumbers.isEmpty {
      updatedPhoneRows = 0
    } else {
      contact.phoneNumbers = [
        CNLabeledValue(
          label: CNLabelPhoneNumberMobile,
          value: CNPhoneNumber(stringValue: phoneNumber)
        )
      ]
      updatedPhoneRows = 1
    }

    let request = CNSaveRequest()
    request.update(contact)
    try store.execute(request)
    return AgentNativeToolExecutionResult.success(
      output: commonOutput(
        [
          "contact_id": .int(contactId),
          "display_name": .string(displayName),
          "phone_number": .string(phoneNumber),
          "updated_name_rows": .int(1),
          "updated_phone_rows": .int(updatedPhoneRows),
          "contact_found": .bool(true)
        ],
        authorization: authorization,
        nowMillis: nowMillis
      ),
      message: "Contact updated"
    )
  }

  private func findMutableContact(
    store: CNContactStore,
    contactId: Int64
  ) throws -> CNMutableContact? {
    let keys = [
      CNContactIdentifierKey,
      CNContactGivenNameKey,
      CNContactMiddleNameKey,
      CNContactFamilyNameKey,
      CNContactOrganizationNameKey,
      CNContactPhoneNumbersKey
    ] as [CNKeyDescriptor]
    var match: CNMutableContact?
    let request = CNContactFetchRequest(keysToFetch: keys)
    try store.enumerateContacts(with: request) { contact, stop in
      if syntheticContactId(contact.identifier) == contactId {
        match = contact.mutableCopy() as? CNMutableContact
        stop.pointee = true
      }
    }
    return match
  }

  private func createdContactId(
    contact: CNMutableContact,
    store: CNContactStore,
    displayName: String,
    phoneNumber: String,
    nowMillis: Int64
  ) throws -> Int64 {
    if !contact.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return syntheticContactId(contact.identifier)
    }
    if let identifier = try findContactIdentifier(
      store: store,
      displayName: displayName,
      phoneNumber: phoneNumber
    ) {
      return syntheticContactId(identifier)
    }
    return syntheticContactId("\(displayName)|\(phoneNumber)|\(nowMillis)")
  }

  private func findContactIdentifier(
    store: CNContactStore,
    displayName: String,
    phoneNumber: String
  ) throws -> String? {
    let keys = [
      CNContactIdentifierKey,
      CNContactGivenNameKey,
      CNContactMiddleNameKey,
      CNContactFamilyNameKey,
      CNContactOrganizationNameKey,
      CNContactPhoneNumbersKey
    ] as [CNKeyDescriptor]
    var identifier: String?
    let request = CNContactFetchRequest(keysToFetch: keys)
    try store.enumerateContacts(with: request) { contact, stop in
      guard contactDisplayName(contact) == displayName else {
        return
      }
      if phoneNumber.isEmpty || contact.phoneNumbers.contains(where: { $0.value.stringValue == phoneNumber }) {
        identifier = contact.identifier
        stop.pointee = true
      }
    }
    return identifier
  }

  private func contactDisplayName(_ contact: CNContact) -> String {
    let name = [contact.givenName, contact.middleName, contact.familyName]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    if !name.isEmpty {
      return name
    }
    let organization = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
    return organization.isEmpty ? "Contact" : organization
  }

  private func commonOutput(
    _ values: AgentMcpJSONObject,
    authorization: CNAuthorizationStatus,
    nowMillis: Int64
  ) -> AgentMcpJSONObject {
    var output = values
    output["authorization_status"] = .string(authorizationStatus(authorization))
    output["scope"] = .string("ios_contacts_write")
    output["platform"] = .string("ios")
    output["observed_at_epoch_ms"] = .int(nowMillis)
    return output
  }

  private func isContactsAuthorized(_ status: CNAuthorizationStatus) -> Bool {
    status == .authorized || String(describing: status).lowercased().contains("limited")
  }

  private func authorizationStatus(_ status: CNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "not_determined"
    case .restricted:
      return "restricted"
    case .denied:
      return "denied"
    case .authorized:
      return "authorized"
    @unknown default:
      return String(describing: status)
        .replacingOccurrences(of: " ", with: "_")
        .lowercased()
    }
  }

  private func syntheticContactId(_ identifier: String) -> Int64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in identifier.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return Int64(hash & 0x7fff_ffff_ffff_ffff)
  }
  #endif

  private func bounded(_ value: String, _ limit: Int) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }
}
