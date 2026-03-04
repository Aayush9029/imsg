import Contacts
import Foundation

public final class ContactsResolver: @unchecked Sendable {
  private enum AccessState {
    case unknown
    case available
    case unavailable
  }

  private let store: CNContactStore
  private let lock = NSLock()

  private var accessState: AccessState = .unknown
  private var didBuildIndex = false
  private var handleToDisplayName: [String: String] = [:]
  private var nameToHandles: [String: [String]] = [:]

  public init(store: CNContactStore = CNContactStore()) {
    self.store = store
  }

  public func displayName(for handle: String) -> String? {
    let normalizedHandle = Self.normalizeHandle(handle)
    guard !normalizedHandle.isEmpty, ensureIndex() else { return nil }

    lock.lock()
    defer { lock.unlock() }
    return handleToDisplayName[normalizedHandle]
  }

  public func handles(matching displayName: String) -> [String] {
    let normalizedName = Self.normalizeName(displayName)
    guard !normalizedName.isEmpty, ensureIndex() else { return [] }

    lock.lock()
    defer { lock.unlock() }
    return nameToHandles[normalizedName] ?? []
  }

  public func firstHandle(matching displayName: String) -> String? {
    handles(matching: displayName).first
  }

  private func ensureIndex() -> Bool {
    guard ensureContactsAccess() else { return false }

    lock.lock()
    let alreadyBuilt = didBuildIndex
    lock.unlock()
    if alreadyBuilt {
      return true
    }

    buildIndex()
    return true
  }

  private func ensureContactsAccess() -> Bool {
    lock.lock()
    let currentState = accessState
    lock.unlock()

    switch currentState {
    case .available:
      return true
    case .unavailable:
      return false
    case .unknown:
      let granted = requestContactsAccessIfNeeded()
      lock.lock()
      accessState = granted ? .available : .unavailable
      lock.unlock()
      return granted
    }
  }

  private func requestContactsAccessIfNeeded() -> Bool {
    switch CNContactStore.authorizationStatus(for: .contacts) {
    case .authorized:
      return true
    case .denied, .restricted:
      return false
    case .notDetermined:
      final class AccessStateBox: @unchecked Sendable {
        var granted = false
      }
      let state = AccessStateBox()
      let semaphore = DispatchSemaphore(value: 0)
      store.requestAccess(for: .contacts) { isGranted, _ in
        state.granted = isGranted
        semaphore.signal()
      }
      semaphore.wait()
      return state.granted
    @unknown default:
      return false
    }
  }

  private func buildIndex() {
    let keys: [CNKeyDescriptor] = [
      CNContactGivenNameKey as CNKeyDescriptor,
      CNContactFamilyNameKey as CNKeyDescriptor,
      CNContactNicknameKey as CNKeyDescriptor,
      CNContactOrganizationNameKey as CNKeyDescriptor,
      CNContactPhoneNumbersKey as CNKeyDescriptor,
      CNContactEmailAddressesKey as CNKeyDescriptor,
    ]

    let request = CNContactFetchRequest(keysToFetch: keys)
    var localHandleToDisplayName: [String: String] = [:]
    var localNameToHandles: [String: [String]] = [:]

    do {
      try store.enumerateContacts(with: request) { contact, _ in
        let handles = Self.contactHandles(from: contact)
        guard !handles.isEmpty else { return }

        let displayName = Self.preferredDisplayName(from: contact)

        for handle in handles {
          let normalizedHandle = Self.normalizeHandle(handle)
          guard !normalizedHandle.isEmpty else { continue }
          if localHandleToDisplayName[normalizedHandle] == nil {
            localHandleToDisplayName[normalizedHandle] = displayName
          }
        }

        var normalizedNames = Set<String>()
        normalizedNames.insert(Self.normalizeName(displayName))

        let fullName = Self.fullName(from: contact)
        if !fullName.isEmpty {
          normalizedNames.insert(Self.normalizeName(fullName))
        }

        let nickname = contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nickname.isEmpty {
          normalizedNames.insert(Self.normalizeName(nickname))
        }

        let organization = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !organization.isEmpty {
          normalizedNames.insert(Self.normalizeName(organization))
        }

        normalizedNames.remove("")
        for normalizedName in normalizedNames {
          for handle in handles {
            Self.appendUnique(handle, to: &localNameToHandles[normalizedName, default: []])
          }
        }
      }
    } catch {
      // Graceful fallback: keep indexes empty when Contacts lookup fails.
    }

    lock.lock()
    handleToDisplayName = localHandleToDisplayName
    nameToHandles = localNameToHandles
    didBuildIndex = true
    lock.unlock()
  }

  private static func preferredDisplayName(from contact: CNContact) -> String {
    let nickname = contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    if !nickname.isEmpty { return nickname }

    let fullName = fullName(from: contact)
    if !fullName.isEmpty { return fullName }

    let organization = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !organization.isEmpty { return organization }

    return "Unknown Contact"
  }

  private static func fullName(from contact: CNContact) -> String {
    let given = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
    let family = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
    return [given, family].filter { !$0.isEmpty }.joined(separator: " ")
  }

  private static func contactHandles(from contact: CNContact) -> [String] {
    var handles: [String] = []
    var seen = Set<String>()

    for phone in contact.phoneNumbers {
      let value = phone.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { continue }
      let normalized = normalizeHandle(value)
      if !normalized.isEmpty, seen.insert(normalized).inserted {
        handles.append(value)
      }
    }

    for email in contact.emailAddresses {
      let value = String(email.value).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { continue }
      let normalized = normalizeHandle(value)
      if !normalized.isEmpty, seen.insert(normalized).inserted {
        handles.append(value)
      }
    }

    return handles
  }

  private static func appendUnique(_ value: String, to array: inout [String]) {
    if !array.contains(value) {
      array.append(value)
    }
  }

  private static func normalizeName(_ value: String) -> String {
    let folded = value
      .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !folded.isEmpty else { return "" }

    return folded
      .split(whereSeparator: { $0.isWhitespace })
      .map(String.init)
      .joined(separator: " ")
      .lowercased()
  }

  private static func normalizeHandle(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    if trimmed.contains("@") {
      return trimmed.lowercased()
    }

    let digits = trimmed.unicodeScalars
      .filter { CharacterSet.decimalDigits.contains($0) }
      .map(String.init)
      .joined()

    guard !digits.isEmpty else {
      return trimmed.lowercased()
    }

    if digits.count == 11, digits.hasPrefix("1") {
      return String(digits.dropFirst())
    }

    return digits
  }
}
