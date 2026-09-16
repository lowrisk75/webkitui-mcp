import Foundation
import Testing
import WebKitUIMCPCore

@testable import WebKitUIMCPServer

@Suite("Receipt and audit leak corpus", .serialized)
@MainActor
struct ReceiptLeakCorpusTests {
  private static let queryCanary = "QUERY-SECRETVALUE-7f31"
  private static let passwordCanary = "PASSWORD-SECRETVALUE-8a42"
  private static let fragmentCanary = "FRAGMENT-SECRETVALUE-9b53"

  @Test("Query values reach no observation byte")
  func queryValuesAreAbsentFromObservation() async throws {
    let run = try await queryRun()
    #expect(!run.observation.contains(Self.queryCanary))
  }

  @Test("Query values reach no confirmation byte")
  func queryValuesAreAbsentFromConfirmation() async throws {
    let run = try await queryRun()
    #expect(!run.confirmation.contains(Self.queryCanary))
  }

  @Test("Query values reach no action-result byte")
  func queryValuesAreAbsentFromActionResult() async throws {
    let run = try await queryRun()
    #expect(!run.actionResult.contains(Self.queryCanary))
  }

  @Test("Query values reach no exported-receipt byte")
  func queryValuesAreAbsentFromExportedReceipt() async throws {
    let run = try await queryRun()
    #expect(!run.exportedReceipt.contains(Self.queryCanary))
  }

  @Test("Query values reach no navigation-audit byte")
  func queryValuesAreAbsentFromNavigationAudit() async throws {
    let run = try await queryRun()
    #expect(!run.navigationAudit.contains(Self.queryCanary))
  }

  @Test("Query values reach no activity-log byte")
  func queryValuesAreAbsentFromActivityLog() async throws {
    let run = try await queryRun()
    #expect(!run.activityLog.contains(Self.queryCanary))
  }

  @Test("A password value reaches none of the exported surfaces")
  func passwordValueIsAbsentEverywhere() async throws {
    let run = try await queryRun()
    for (surface, bytes) in run.surfaces {
      #expect(!bytes.contains(Self.passwordCanary), "password leaked through \(surface)")
    }
  }

  @Test("P1 finding: URL fragments remain model-visible but leave no receipt or audit")
  func fragmentVisibilityIsRecorded() async throws {
    let run = try await performRun(urlSuffix: "#fragment=\(Self.fragmentCanary)")

    // This is a deliberately accepted finding, not an assertion that fragments are
    // harmless. A fragment can be the page's only useful identity, so Task 4 records
    // the measured boundary and Task 5 publishes the P1 rather than silently stripping
    // it without a product decision.
    #expect(run.observation.contains(Self.fragmentCanary))
    #expect(run.confirmation.contains(Self.fragmentCanary))
    #expect(!run.actionResult.contains(Self.fragmentCanary))
    #expect(!run.exportedReceipt.contains(Self.fragmentCanary))
    #expect(!run.navigationAudit.contains(Self.fragmentCanary))
    #expect(!run.activityLog.contains(Self.fragmentCanary))
  }

  private func queryRun() async throws -> LeakRun {
    try await performRun(
      urlSuffix: "?session=\(Self.queryCanary)&token=\(Self.queryCanary)")
  }

  private func performRun(urlSuffix: String) async throws -> LeakRun {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "webkitui-adversarial-activity-\(UUID().uuidString)",
      directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let activityLog = try WebKitActivityLog(directoryURL: directory)
    let harness = try AdversarialFixtureHarness(
      confirmationOutcomes: [.approved], activityLog: activityLog)
    let attributeSuffix =
      urlSuffix.hasPrefix("?")
      ? urlSuffix
      : "#fragment=\(Self.fragmentCanary)"
    let observation = try await harness.loadAndObserve(
      """
      <form action='/fallback\(attributeSuffix)' method='post'>
        <button id='send' type='submit' formaction='/collect\(attributeSuffix)'>Send</button>
        <input type='password' name='password' value='\(Self.passwordCanary)'>
      </form>
      <a href='/details\(attributeSuffix)'>Details</a>
      <img alt='' src='data:image/gif;base64,R0lGODlhAQABAAAAACw=\(attributeSuffix)'>
      <script>
        document.getElementById('send').addEventListener('click', event => {
          event.preventDefault();
          const status = document.createElement('h2');
          status.textContent = 'ADVERSARIAL ACTION COMPLETE';
          document.body.append(status);
        });
      </script>
      """,
      baseURL: try #require(
        URL(string: "https://receipt-leak.fixture.invalid/start\(urlSuffix)")))
    let observationID = try #require(observation["observationID"]?.stringValue)
    guard case .array(let elements) = observation["elements"],
      let button = elements.first(where: {
        $0.objectValue?["submitsForm"] == .bool(true)
      }),
      let elementID = button.objectValue?["elementID"]?.stringValue
    else {
      throw AdversarialFixtureHarnessError.missingObservationField("submit element")
    }
    let idempotencyKey = "receipt-leak-\(UUID().uuidString)"
    let actionResult = try await harness.callTool(
      "browser_act",
      arguments: [
        "session_id": .string(harness.session.rawValue.uuidString),
        "observation_id": .string(observationID),
        "element_id": .string(elementID),
        "operation": .string("submit"),
        "approval_mode": .string("native"),
        "idempotency_key": .string(idempotencyKey),
        "postcondition": .object([
          "type": .string("semantic_text_appears"),
          "value": .string("ADVERSARIAL ACTION COMPLETE"),
        ]),
      ])
    guard actionResult["action"]?.objectValue?["dispatched"] == .bool(true) else {
      throw AdversarialFixtureHarnessError.wrongWireShape("dispatched action result")
    }
    let confirmation = try #require(harness.confirmationPresenter.requests.last?.message)
    let exportedReceipt = try await harness.callTool(
      "browser_transaction",
      arguments: [
        "session_id": .string(harness.session.rawValue.uuidString),
        "operation": .string("export"),
        "idempotency_key": .string(idempotencyKey),
      ])
    guard
      exportedReceipt["receipt"]?.objectValue?["receipt"]?.objectValue?["phase"]
        == .string("verified")
    else {
      throw AdversarialFixtureHarnessError.wrongWireShape("verified ReceiptV1 export")
    }
    let navigationAudit = try #require(harness.runtime.latestNavigationAuditEvent())

    return LeakRun(
      observation: try encoded(.object(observation)),
      confirmation: try encoded(.string(confirmation)),
      actionResult: try encoded(.object(actionResult)),
      exportedReceipt: try encoded(.object(exportedReceipt)),
      navigationAudit: try JSONEncoder().encode(navigationAudit),
      activityLog: try await activityLog.exportData())
  }

  private func encoded(_ value: JSONValue) throws -> Data {
    try JSONEncoder().encode(value)
  }

  private struct LeakRun {
    let observation: Data
    let confirmation: Data
    let actionResult: Data
    let exportedReceipt: Data
    let navigationAudit: Data
    let activityLog: Data

    var surfaces: [(String, Data)] {
      [
        ("observation", observation),
        ("confirmation", confirmation),
        ("action_result", actionResult),
        ("exported_receipt", exportedReceipt),
        ("navigation_audit", navigationAudit),
        ("activity_log", activityLog),
      ]
    }
  }
}

extension Data {
  fileprivate func contains(_ text: String) -> Bool {
    range(of: Data(text.utf8)) != nil
  }
}
