#!/usr/bin/env node
// One synthetic panel, no website/input/approval. Only its own helper is signalled.
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';

const helper = process.argv[2];
if (!helper || process.argv.length !== 3) process.exit(64);
const requestID = randomUUID();
const child = spawn(helper, ['--protocol-version', '1', '--request-stdin'], {
  stdio: ['pipe', 'pipe', 'ignore'],
});
console.log(`RESOURCE_CREATED=refocus-probe:${child.pid ?? 'launching'}`);
let buffer = '', bytes = 0, signalled = false, passed = false, failed = false;
function refuse() { failed = true; child.kill('SIGKILL'); }
const timer = setTimeout(refuse, 5000);
child.stdin.on('error', refuse);
child.stdin.end(JSON.stringify({ requestID, title: 'Test local WebKitUI [LOCAL]',
  message: 'Synthetic focus check. No website or real action. No approval requested.',
  approveLabel: 'Test only' }));
child.stdout.on('data', data => {
  bytes += data.length;
  if (bytes > 16384) return refuse();
  buffer += data.toString('utf8');
  while (buffer.includes('\n')) {
    const boundary = buffer.indexOf('\n');
    const line = buffer.slice(0, boundary); buffer = buffer.slice(boundary + 1);
    let receipt;
    try { receipt = JSON.parse(line); } catch { refuse(); return; }
    if (receipt.requestID?.toLowerCase() !== requestID.toLowerCase()
        || receipt.helperPID !== child.pid || receipt.windowNumber <= 0
        || receipt.decision != null) return refuse();
    if (receipt.phase === 'ordered' && !signalled) {
      signalled = child.kill('SIGUSR1');
      if (!signalled) return refuse();
    }
    if (receipt.phase === 'refocused' && signalled) {
      passed = receipt.windowVisible === true && receipt.onActiveSpace === true
        && receipt.intersectsScreen === true && receipt.appKitVisible === true
        && receipt.keyWindow === true;
      if (!passed) return refuse();
      child.kill('SIGTERM');
    }
  }
});
child.on('error', () => { failed = true; });
child.on('close', (_code, signal) => {
  clearTimeout(timer);
  console.log(`RESOURCE_STOPPED=refocus-probe:${child.pid ?? 'not-launched'}`);
  if (failed || !passed || signal !== 'SIGTERM') {
    console.error('FAIL exact helper refocus; no approval or browser action was requested.');
    process.exitCode = 1;
  } else console.log('PASS exact helper refocus metadata; no approval, input or browser dispatch. Human perception remains separate.');
});
