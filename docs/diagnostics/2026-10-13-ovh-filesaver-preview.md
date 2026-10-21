# OVH FileSaver and ancillary preview — 0.6.37

Codex reacquired sole writer ownership for this bounded correction after the live
0.6.36 export failed with download_window_duplicate. Existing dirty changes are
preserved; other builds and simulators continue. No file was recovered by 0.6.36.

The public OVH pci-users useDownloadRCloneConfig hook saves a text/plain Blob with
FileSaver and separately opens a FileReader data preview. FileSaver's Mac WebKit
fallback opens a blank window and navigates it to data:attachment/file;base64.
This is a plausible explanation of the observed two native window requests,
not proof of the deployed OVH revision. Synthetic local tests reproduce both the
blank-preview duplicate refusal and the top-preview network-boundary refusal.

One request-bound managed window remains the limit. Only a base64 text/plain
ancillary preview from the same native source origin is suppressed while that
window exists. A base64 attachment/file GET in the managed window is converted
to a native download only with the expected native source origin. No data body
is evaluated, exposed in diagnostics or rendered. HTML, percent-encoded and
unapproved parameter data URLs remain refused. Duplicate blank windows and
foreign openers remain refused. One native destination and completed file receipt
are required; no automatic real click replay.

Sources consulted:
https://github.com/ovh/manager/blob/master/packages/manager/apps/pci-users/src/api/hooks/useUser.ts
https://github.com/ovh/manager/blob/master/packages/manager/modules/manager-pci-common/src/api/hook/useRclone.ts
https://github.com/eligrey/FileSaver.js/blob/master/src/FileSaver.js

Qualification, exact local signing, installation and live export are pending.
No commit, push, cloud policy changes, user/key recreation or publication.

## Local installation checkpoint

Final Debug and Release suites pass, including both FileSaver/preview cases and
negative data-format cases. Native panel probes, preview/provenance, exact local
signing and extracted-archive verification pass. Installed 0.6.37 (637) signature,
source manifest, three executable machine-code comparisons and two-client native
transport verification pass. Logs: /private/tmp/webkitui-637-*.log.
Local code writer ownership is relinquished after this bounded coding lot.
Live export qualification and private credential custody remain pending.

Source manifest SHA-256: `98be03862e90511ab6037dcb92962362615194a82428b9d843e3c8b62c6e23f5`
Signed archive SHA-256: `66beafaaaf60e3ebd2dbaddf1c0ad2aa249a1300aa4894ab89a993f18a60a427`
Rollback 0.6.36: `/private/tmp/webkitui-637-install.6zHdjj/rollback/WebKitUI MCP.app`
