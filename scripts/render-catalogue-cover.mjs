// Render the repository-native vector cover. No browser or external dependency.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import zlib from 'node:zlib';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'dist/catalogue-0.6.24');
fs.mkdirSync(output, { recursive: true });
execFileSync('/usr/bin/qlmanage', ['-t', '-s', '1200', '-o', output,
  path.join(root, 'Support/Catalogue/cover.svg')], { stdio: 'pipe' });
// Quick Look renders the 768-wide SVG into a 1200-square thumbnail, with white
// padding below its 1200x630 artwork. Retain the top scanlines without resampling.
const png = fs.readFileSync(path.join(output, 'cover.svg.png'));
const chunks = [];
for (let offset = 8; offset < png.length;) {
  const length = png.readUInt32BE(offset);
  const type = png.toString('ascii', offset + 4, offset + 8);
  chunks.push({ type, data: png.subarray(offset + 8, offset + 8 + length) });
  offset += length + 12;
}
const header = Buffer.from(chunks.find(c => c.type === 'IHDR').data);
if (header.readUInt32BE(0) !== 1200 || header.readUInt32BE(4) !== 1200 ||
    header[8] !== 8 || header[9] !== 6 || header[12] !== 0) {
  throw new Error('Unexpected Quick Look PNG layout; inspect before exporting');
}
const scanlines = zlib.inflateSync(Buffer.concat(chunks.filter(c => c.type === 'IDAT').map(c => c.data)));
if (scanlines.length !== (1200 * 4 + 1) * 1200) throw new Error('Unexpected scanline count');
header.writeUInt32BE(630, 4);
function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const name = Buffer.from(type);
  const size = Buffer.alloc(4); size.writeUInt32BE(data.length);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([name, data])));
  return Buffer.concat([size, name, data, crc]);
}
const profile = chunks.filter(c => ['sRGB', 'gAMA', 'cHRM', 'iCCP'].includes(c.type));
const destination = path.join(output, 'cover-1200x630.png');
fs.writeFileSync(destination, Buffer.concat([
  png.subarray(0, 8), chunk('IHDR', header), ...profile.map(c => chunk(c.type, c.data)),
  chunk('IDAT', zlib.deflateSync(scanlines.subarray(0, (1200 * 4 + 1) * 630))),
  chunk('IEND', Buffer.alloc(0)),
]));
console.log(destination);
