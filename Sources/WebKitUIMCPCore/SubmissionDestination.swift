import Foundation

/// Where a control's data would go, as a line for the human confirmation.
///
/// The dialog showed what a control calls itself and never where it would send anything.
/// A submit button's `formaction` overrides its form's `action`, so a control whose
/// accessible name reads "Show tracking number" can post to another site, and an
/// operator reading the dialog had nothing to notice. Published as the attack this
/// product did not stop: `docs/research/2026-09-09-agentic-browser-security-sota.md`.
public enum SubmissionDestination {
  public static func line(pageURL: URL?, destination: String?) -> String? {
    // A control that sends nothing says nothing. Anything else, including an address that
    // is blank or unparseable, is reported: silence there would hide the case worth
    // showing.
    guard let destination else { return nil }
    let unknown = "Data would be sent to:\nan address with no readable origin — treat as UNKNOWN"
    guard !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let target = URL(string: destination), let targetOrigin = origin(of: target)
    else { return unknown }
    // Only the origin. A query string in an approval dialog is both unreadable and a
    // place to hide an exfiltrated secret.
    guard let pageOrigin = pageURL.flatMap(origin(of:)) else {
      return "Data would be sent to:\n\(quoted(targetOrigin))"
    }
    if targetOrigin == pageOrigin {
      return "Data would be sent to:\n\(quoted(targetOrigin)) (this page's origin)"
    }
    return "Data would be sent to:\n\(quoted(targetOrigin)) — A DIFFERENT SITE "
      + "from the page you are on, \(quoted(pageOrigin))"
  }

  private static func origin(of url: URL) -> String? {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host, !host.isEmpty
    else { return nil }
    if let port = url.port { return "\(scheme)://\(host):\(port)" }
    return "\(scheme)://\(host)"
  }

  /// Quoted the way the confirmation summary quotes every other value it shows: JSON,
  /// so a hostile host name cannot forge a line break, and without slash escaping, so an
  /// origin still reads as an origin to the human.
  private static func quoted(_ value: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    guard let data = try? encoder.encode(value) else { return "\"unavailable\"" }
    return String(decoding: data, as: UTF8.self)
  }
}
