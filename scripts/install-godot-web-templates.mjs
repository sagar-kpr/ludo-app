// Install only official web templates using ZIP range reads, not the 1.25 GB
// all-platform archive. ZIP CRCs are checked before writing tool assets.
import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';
import { inflateRawSync } from 'node:zlib';

const version = '4.6.1';
const source = `https://github.com/godotengine/godot-builds/releases/download/${version}-stable/Godot_v${version}-stable_export_templates.tpz`;
const head = await fetch(source, { method: 'HEAD', signal: AbortSignal.timeout(30000) });
if (!head.ok) throw new Error(`Official template download failed (${head.status})`);
const length = Number(head.headers.get('content-length'));
if (!Number.isSafeInteger(length) || length < 131072) throw new Error('Invalid template archive length');
async function range(start, end) {
  const response = await fetch(head.url, { headers: { Range: `bytes=${start}-${end}` }, signal: AbortSignal.timeout(120000) });
  if (response.status !== 206) { await response.body?.cancel(); throw new Error('Template host must support range downloads'); }
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length !== end-start+1) throw new Error('Incomplete template download');
  return bytes;
}
const tail = await range(length-131072, length-1);
const end = tail.lastIndexOf(Buffer.from([0x50,0x4b,0x05,0x06]));
if (end < 0) throw new Error('ZIP directory missing');
const directoryOffset = tail.readUInt32LE(end+16);
const directoryLength = tail.readUInt32LE(end+12);
const directory = directoryOffset >= length-tail.length
  ? tail.subarray(directoryOffset-(length-tail.length), directoryOffset-(length-tail.length)+directoryLength)
  : await range(directoryOffset, directoryOffset+directoryLength-1);
const entries = [];
for (let offset = 0; offset < directory.length;) {
  if (directory.readUInt32LE(offset) !== 0x02014b50) throw new Error('Unsupported ZIP directory');
  const nameLength = directory.readUInt16LE(offset+28);
  const name = directory.subarray(offset+46,offset+46+nameLength).toString();
  entries.push({ name, method: directory.readUInt16LE(offset+10), crc: directory.readUInt32LE(offset+16),
    size: directory.readUInt32LE(offset+20), unpacked: directory.readUInt32LE(offset+24), offset: directory.readUInt32LE(offset+42) });
  offset += 46+nameLength+directory.readUInt16LE(offset+30)+directory.readUInt16LE(offset+32);
}
function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
const dataRoot = process.platform === 'win32' ? process.env.APPDATA
  : process.platform === 'darwin' ? path.join(homedir(),'Library/Application Support')
  : process.env.XDG_DATA_HOME || path.join(homedir(),'.local/share');
const destination = path.join(dataRoot,'godot/export_templates',`${version}.stable`);
mkdirSync(destination,{ recursive:true });
for (const file of ['web_nothreads_release.zip','web_nothreads_debug.zip']) {
  const entry = entries.find(item => item.name === `templates/${file}`);
  if (!entry) throw new Error(`${file} missing from official archive`);
  const header = await range(entry.offset,entry.offset+29);
  const start = entry.offset+30+header.readUInt16LE(26)+header.readUInt16LE(28);
  console.log(`Downloading official ${file} (${Math.round(entry.size/1024/1024)} MB)…`);
  const compressed = await range(start,start+entry.size-1);
  const bytes = entry.method === 8 ? inflateRawSync(compressed) : compressed;
  if (bytes.length !== entry.unpacked || crc32(bytes) !== entry.crc) throw new Error('Template integrity check failed');
  writeFileSync(path.join(destination,file),bytes);
}
console.log('Godot 4.6.1 single-thread web templates installed.');
