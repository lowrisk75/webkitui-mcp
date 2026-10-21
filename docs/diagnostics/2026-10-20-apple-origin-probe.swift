import Foundation

@main
struct AppleOriginProbe {
  static func main() {
    var checks = 0
    func check(_ saved: String, _ requested: String, _ expected: Bool, port: UInt16 = 443) {
      precondition(AppleCredentialOriginMatching.matches(
        savedURL: URL(string: saved)!, scheme: "https", host: requested, port: port) == expected)
      checks += 1
    }
    for target in ["idmsa.apple.com", "appleid.apple.com", "account.apple.com", "developer.apple.com", "appstoreconnect.apple.com"] {
      for saved in ["apple.com", "www.apple.com", "appleid.apple.com", "account.apple.com", "developer.apple.com", "appstoreconnect.apple.com"] {
        check("https://\(saved)/", target, true)
      }
    }
    for saved in ["https://developer.apple.com.attacker.invalid", "https://fakeapple.com", "https://kevinn.ie", "https://unlisted.apple.com", "http://developer.apple.com", "https://developer.apple.com:444", "https://user@developer.apple.com"] {
      check(saved, "idmsa.apple.com", false)
    }
    for target in ["idmsa.apple.com.attacker.invalid", "fakeapple.com", "unlisted.apple.com", "kevinn.ie"] {
      check("https://developer.apple.com", target, false)
    }
    check("https://developer.apple.com", "idmsa.apple.com", false, port: 444)
    check("https://other.example.com:444", "other.example.com", true, port: 444)
    check("https://other.example.com", "login.other.example.com", false)
    print("PASS \(checks) synthetic Apple/exact-origin cases; no vault or credential read")
  }
}
