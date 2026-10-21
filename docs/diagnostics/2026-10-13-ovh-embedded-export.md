# OVH embedded export correction — 0.6.36

Codex acquired sole writer ownership for this bounded correction following the
user's explicit request from AirDrop. Existing dirty changes preserved. No commit,
push, notarization or publication. Installed baseline 0.6.35.

Real OVH final S3 Paris export returned download_window_refused, with no file.
Local sameOriginFramePopupExportPreservesPage reproduced that exact error before
correction (webkitui-636-frame-red.log). It passes after removing the main-frame
restriction from the managed popup opener guard. View identity, exact expected
origin and one request-bound child window remain mandatory. The foreign embedded
opener test passes with download_window_origin_mismatch and no destination call.

Refusals now distinguish opener mismatch, origin mismatch and duplicate window;
MCP downloadFailed responses retain request-local diagnostic flags. The duplicate
window wire test and existing main-frame Blob/HTTP exports and failure cleanup
cases pass. No credential body, private path or URL was added to diagnostics.

Apple callback contracts consulted: sourceFrame identifies the requesting frame;
createWebViewWith supplies the configuration for the returned destination view.
https://developer.apple.com/documentation/webkit/wknavigationaction/sourceframe
https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:createwebviewwith:for:windowfeatures:)

The local reproduction establishes the mechanism, not live OVH causality or
successful credential custody. Full validation, packaging, installation and live
export qualification are tracked in the AirDrop remediation report and private
webkitui-636 logs. Installed app is unchanged until those gates pass.

## Final 0.6.36 local installation checkpoint

Final scope includes bounded native-click settling: survey without arming a
receipt, hold/recheck geometry and physical identity, then arm immediately before
the single dispatch. The test verifies one animated click and separately verifies
that a scripted click during settling cannot supply the native trusted receipt.

Final Debug and Release each pass 600 tests: 181 server, 242 runtime, 18 policy,
90 core, 56 adversarial Swift Testing tests plus 13 XCTest tests. Five bundle
summaries/no failures required. Earlier failed/interrupted runs are retained and
not accepted; no native trust check was relaxed. Native panel probes, package
provenance, exact signing and extracted-archive verification pass. Installed source
manifest matches the frozen tested source; installed machine code matches the
Release build. Installed two-client transport check passes.

No real OVH export was performed by this installation script. Credential custody
and live OVH qualification remain separate pending work in the owning AirDrop
mission. No commit, push, notarization or publication. Local code writer ownership
is relinquished after this completed coding lot; any new writer must recheck live
files and the installed version. Evidence: private webkitui-636 logs and AirDrop
docs/ovh-webkitui-remediation-0.6.36-20261013.md.

Installed source manifest SHA-256: `58b2cdf9b86544aeb2dec8e894544d7430dcfd3e9094ec85b8b054900f648b5e`
Signed archive SHA-256: `593d8350e46a96be82af3ea24eea9e241a39a559035e171436d82109d5bd41ef`
Rollback app: `/private/tmp/webkitui-636-install.429EO7/rollback/WebKitUI MCP.app`
