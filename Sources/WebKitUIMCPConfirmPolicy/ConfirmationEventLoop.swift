import AppKit

public enum ConfirmationEventLoop {
  /// `stop` called by a timer/AX callback needs an event dispatch to unwind `run`.
  /// This application-defined event carries no input and cannot press a button.
  @MainActor
  public static func stop(_ application: NSApplication = .shared) {
    application.stop(nil)
    if let wake = NSEvent.otherEvent(
      with: .applicationDefined, location: .zero, modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
      context: nil, subtype: 0, data1: 0, data2: 0)
    {
      application.postEvent(wake, atStart: true)
    }
  }
}
