import Foundation

/// Whether a form submission may proceed, judged against the origin the human approved.
///
/// `WKFormInfo` reports what WebKit is about to send, which is the one description of a
/// submission the page cannot author. Its `submissionHandler` is a delay and not a veto,
/// so this decision is applied where refusals already live: the navigation policy
/// handler, returning `.cancel`.
public enum SubmissionApproval {
  public enum Decision: Equatable, Sendable {
    case allow
    /// The submission leaves the approved origin. Carries the origin it would reach, or
    /// `"unreadable"` when there is no origin to name.
    case refuseForeignOrigin(String)
    /// Nothing was approved. Fail closed.
    case refuseUnapproved
  }

  public static func decide(
    approvedOrigin: String?,
    submissionURL: URL,
    httpMethod: String
  ) -> Decision {
    guard let approvedOrigin, !approvedOrigin.isEmpty else { return .refuseUnapproved }
    guard let submissionOrigin = origin(of: submissionURL) else {
      return .refuseForeignOrigin("unreadable")
    }
    guard submissionOrigin == approvedOrigin else {
      return .refuseForeignOrigin(submissionOrigin)
    }
    return .allow
  }

  private static func origin(of url: URL) -> String? {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host, !host.isEmpty
    else { return nil }
    if let port = url.port { return "\(scheme)://\(host):\(port)" }
    return "\(scheme)://\(host)"
  }
}
