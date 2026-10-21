#!/usr/bin/env python3
"""Apply only the reviewed owner-side Apple matching fix; refuse concurrent changes."""
import difflib
import hashlib
from pathlib import Path
import sys

repo = Path(__file__).resolve().parents[2]
owner = Path("/Users/kevin/GitHub/SiliconPass")
provider = owner / "Sources/SiliconPassCredentialBrokerVault/VaultCredentialFillProvider.swift"
helper = owner / "Sources/SiliconPassCredentialBrokerVault/AppleCredentialOriginMatching.swift"
tests = owner / "Tests/SiliconPassCredentialBrokerVaultTests/AppleCredentialOriginMatchingTests.swift"
before = provider.read_text()
assert hashlib.sha256(before.encode()).hexdigest() == "832dc2d4a2d4233defc463c35c2b0fb5f21bde1ae7139491a3b0fcd51a43c68b", "Provider changed; stop for writer coordination"
assert not helper.exists() and not tests.exists()
old = '''    !item.isArchived && item.scope?.urls.contains { url in
      guard url.scheme?.lowercased() == origin.scheme,
        url.host?.lowercased() == origin.asciiHost
      else { return false }
      let effectivePort = url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
      return effectivePort == Int(origin.effectivePort)
    } == true'''
new = '''    !item.isArchived && item.scope?.urls.contains { url in
      AppleCredentialOriginMatching.matches(savedURL: url, scheme: origin.scheme,
        host: origin.asciiHost, port: origin.effectivePort)
    } == true'''
assert old in before
after = before.replace(old, new).replace("exactlyCovers", "coversBrokerOrigin")
helper_text = (repo / "docs/diagnostics/AppleCredentialOriginMatching.swift").read_text().replace("Proposed owner-side broker fix.", "Apple Account sign-in aliases for the native broker.")
test_text = '''import Foundation
import Testing
@testable import SiliconPassCredentialBrokerVault

struct AppleCredentialOriginMatchingTests {
  @Test("Developer and Apple Account login hosts share native candidates")
  func developerAppleAccountCandidates() throws {
    for target in ["idmsa.apple.com", "appleid.apple.com", "account.apple.com", "developer.apple.com", "appstoreconnect.apple.com"] {
      for stored in ["apple.com", "www.apple.com", "appleid.apple.com", "account.apple.com", "developer.apple.com", "appstoreconnect.apple.com"] {
        #expect(AppleCredentialOriginMatching.matches(
          savedURL: try #require(URL(string: "https://\\(stored)/account")),
          scheme: "https", host: target, port: 443))
      }
    }
  }

  @Test("Apple aliases reject phishing, email domains, downgrade and port changes")
  func appleAliasBoundaries() throws {
    for stored in ["https://developer.apple.com.attacker.invalid", "https://fakeapple.com", "https://kevinn.ie", "https://unlisted.apple.com", "http://developer.apple.com", "https://developer.apple.com:444", "https://user@developer.apple.com"] {
      #expect(!AppleCredentialOriginMatching.matches(savedURL: try #require(URL(string: stored)),
        scheme: "https", host: "idmsa.apple.com", port: 443))
    }
    for target in ["idmsa.apple.com.attacker.invalid", "fakeapple.com", "unlisted.apple.com", "kevinn.ie"] {
      #expect(!AppleCredentialOriginMatching.matches(savedURL: try #require(URL(string: "https://developer.apple.com")),
        scheme: "https", host: target, port: 443))
    }
    #expect(!AppleCredentialOriginMatching.matches(savedURL: try #require(URL(string: "https://developer.apple.com")),
      scheme: "https", host: "idmsa.apple.com", port: 444))
    #expect(AppleCredentialOriginMatching.matches(savedURL: try #require(URL(string: "https://other.example.com:444")),
      scheme: "https", host: "other.example.com", port: 444))
    #expect(!AppleCredentialOriginMatching.matches(savedURL: try #require(URL(string: "https://other.example.com")),
      scheme: "https", host: "login.other.example.com", port: 443))
  }
}
'''
changes = [(provider, before, after), (helper, "", helper_text), (tests, "", test_text)]
patch = "".join("".join(difflib.unified_diff(old_text.splitlines(True), new_text.splitlines(True),
  fromfile="a/" + str(path.relative_to(owner)), tofile="b/" + str(path.relative_to(owner))))
  for path, old_text, new_text in changes)
(repo / "docs/diagnostics/2026-10-20-siliconpass-apple-origin.patch").write_text(patch)
if "--apply" in sys.argv:
    # CAS check immediately before the only existing-file write. No other files,
    # credential data, signing configuration or installed application is changed.
    assert provider.read_text() == before
    for path, _, new_text in changes: path.write_text(new_text)
    print("Applied three-file Apple-only native matching patch in SiliconPass; no vault/app changes")
else:
    print("Prepared reviewable owner patch; no SiliconPass file changed")
