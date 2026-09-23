from pathlib import Path
import subprocess
import tempfile

base = Path(__file__).resolve().parent
script = (base / 'verify-native-installed.sh').read_text()
function = script[script.index('verify_installed_executable() {'):script.index('\n# The standalone CLI is optional')]
manifest = script[script.index('(\n  manifest_scratch='):script.index('\ntest -x "$installed_app/Contents/MacOS/webkitui-mcp-aqua-broker"')]

def run(program, args):
    return subprocess.run(['/bin/zsh', '-c', 'set -euo pipefail\n' + program, 'probe', *map(str,args)], capture_output=True, text=True)

with tempfile.TemporaryDirectory(prefix='webkitui-gates-', dir='/private/tmp') as tmp:
    work=Path(tmp)
    release=work/'release'; release.mkdir()
    app=work/'Test app.app'; resources=app/'Contents/Resources'; resources.mkdir(parents=True)
    installed=app/'Contents/MacOS'; installed.mkdir()
    # No native tools, AppKit, signing or UI execute: Mach-O section inspection is stubbed.
    prelude='''
otool() {
  printf 'mock file header\\nmock section header\\n'
  sed '/^SIGNATURE:/d' "$4"
}
codesign() { return 0; }
release_bin=$1
'''
    for name in ['webkitui-mcp-aqua-broker','webkitui-mcp-confirm','webkitui-mcp-relay']:
        (release/name).write_text('TEXT:current\nSIGNATURE:adhoc\n')
        (installed/name).write_text('TEXT:current\nSIGNATURE:developer-id\n')
        (installed/name).chmod(0o755)
        args=[release, installed/name, name]
        result=run(prelude+function+'\ncodesign --verify "$2"\nverify_installed_executable "$3" "$2"\n',args)
        assert result.returncode==0, result.stderr
        (installed/name).write_text('TEXT:stale\nSIGNATURE:developer-id\n')
        result=run(prelude+function+'\ncodesign --verify "$2"\nverify_installed_executable "$3" "$2"\n',args)
        assert result.returncode!=0 and 'not built from this source' in result.stderr, result
    root=work/'project'; (root/'scripts').mkdir(parents=True)
    generator=root/'scripts/generate-release-provenance.sh'
    generator.write_text('#!/bin/sh\nprintf "current source\\n" > "$1/SOURCE-MANIFEST.sha256"\n')
    generator.chmod(0o755)
    (resources/'ReleaseProvenance.plist').write_text('stubbed plist\n')
    prelude='''project_root=$1
installed_app=$2
plutil() { shasum -a 256 "$installed_app/Contents/Resources/SOURCE-MANIFEST.sha256" | cut -d' ' -f1; }
'''
    (resources/'SOURCE-MANIFEST.sha256').write_text('current source\n')
    result=run(prelude+manifest,[root,app]); assert result.returncode==0,result.stderr
    (resources/'SOURCE-MANIFEST.sha256').write_text('stale source\n')
    result=run(prelude+manifest,[root,app]); assert result.returncode!=0 and 'source manifest differs' in result.stderr,result
    pre= (base/'verify-pre-notarization.sh').read_text()
    branch=pre[pre.index('  if wait "$probe_pid"'):pre.index('\nfi\n\nprintf', pre.index('  if wait "$probe_pid"'))]
    # The branch now sits inside the probe's own `if`; give it that frame and its inputs.
    result=run('scratch_dir=$1\nprintf "synthetic crash detail\\n" > "$scratch_dir/confirmation-probe.err"\n(exit 64) &\nprobe_pid=$!\nprobe_started=$(perl -MTime::HiRes=time -e "print time")\nprobe_presented=0\nif true; then\n'+branch+'\nfi\n',[work])
    assert result.returncode==1 and 'exited with 64' in result.stderr and 'synthetic crash detail' in result.stderr,result
print('PASS: 3 signed-byte variants accepted; 3 stale embedded executables rejected; current manifest accepted; stale manifest rejected; crash status and stderr retained. No native helper or UI launched.')

# Exercise the exact production extractor with complete, concatenated and escaped keys.
import shlex
verification = (base / 'verify-package-preview.sh').read_text()
extractor = next(line for line in verification.splitlines() if line.startswith('perl -0777'))
command = shlex.split(extractor.rstrip(' \\'))
fixture = 'text("Single")\ntext(\n "Long "\n + "key " + "joined")\ntext("Say \\"yes\\"")\ntext(variable)\n'
result = subprocess.run(command, input=fixture, capture_output=True, text=True)
assert result.returncode == 0, result.stderr
assert result.stdout.splitlines() == ['Single', 'Long key joined', 'Say \\"yes\\"'], result.stdout
print('PASS: localization extraction keeps complete concatenated and escaped keys.')
