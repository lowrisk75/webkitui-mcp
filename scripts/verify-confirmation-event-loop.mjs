#!/usr/bin/env node
// No panel, credential access, input synthesis, or approval. The helper itself
// exercises its production timer-driven stop/wake path, bounded by this parent.
import { spawn } from 'node:child_process';

const helper = process.argv[2];
if (!helper || process.argv.length !== 3) {
  console.error('usage: node scripts/verify-confirmation-event-loop.mjs /path/to/helper');
  process.exit(64);
}
const child = spawn(helper, ['--verify-event-loop-stop'], { stdio: ['ignore', 'pipe', 'ignore'] });
let output = '';
let exceeded = false;
const timer = setTimeout(() => {
  exceeded = true;
  child.kill('SIGKILL'); // Only the probe subprocess created above.
}, 4000);
child.stdout.on('data', data => {
  if (output.length + data.length > 1024) {
    exceeded = true;
    child.kill('SIGKILL');
  } else output += data;
});
child.on('error', () => {
  clearTimeout(timer);
  console.error('confirmation event-loop probe could not start');
  process.exitCode = 1;
});
child.on('close', (code, signal) => {
  clearTimeout(timer);
  let result;
  try { result = JSON.parse(output); } catch { /* Invalid/absent receipt fails closed. */ }
  if (exceeded || code !== 0 || signal || result?.event_loop_stopped !== true
      || result?.input_posted !== false) {
    console.error(`confirmation event-loop probe failed: exit=${code}, signal=${signal}, deadlineOrSizeExceeded=${exceeded}`);
    process.exitCode = 1;
    return;
  }
  console.log('Confirmation timer stop/wake passed; no panel or input posted.');
});
