import assert from "node:assert/strict";
import test from "node:test";

import {
  ANDROID_PAGE_SIZE,
  inspectAndroidElfPageSize,
  normalizeAndroidElfPageSize,
} from "./android-elf-page-normalizer.mjs";

function syntheticElf({ alignments = [0x1000, 0x1000, 0x1000] } = {}) {
  const programHeaderOffset = 64;
  const programHeaderEntrySize = 56;
  const programHeaders = [
    { offset: 0, virtualAddress: 0, fileSize: 0x180, alignment: alignments[0] },
    { offset: 0x180, virtualAddress: 0x1180, fileSize: 0x90, alignment: alignments[1] },
    { offset: 0x210, virtualAddress: 0x3210, fileSize: 0x70, alignment: alignments[2] },
  ];
  const sectionHeaderOffset = 0x300;
  const sectionHeaderEntrySize = 64;
  const buffer = Buffer.alloc(sectionHeaderOffset + sectionHeaderEntrySize * 2);
  buffer.write("\x7fELF", 0, "binary");
  buffer[4] = 2;
  buffer[5] = 1;
  buffer[6] = 1;
  buffer.writeUInt16LE(3, 16);
  buffer.writeUInt16LE(183, 18);
  buffer.writeUInt32LE(1, 20);
  buffer.writeBigUInt64LE(BigInt(programHeaderOffset), 32);
  buffer.writeBigUInt64LE(BigInt(sectionHeaderOffset), 40);
  buffer.writeUInt16LE(64, 52);
  buffer.writeUInt16LE(programHeaderEntrySize, 54);
  buffer.writeUInt16LE(programHeaders.length, 56);
  buffer.writeUInt16LE(sectionHeaderEntrySize, 58);
  buffer.writeUInt16LE(2, 60);

  for (const [index, header] of programHeaders.entries()) {
    const offset = programHeaderOffset + index * programHeaderEntrySize;
    buffer.writeUInt32LE(1, offset);
    buffer.writeUInt32LE(index === 0 ? 4 : 5, offset + 4);
    buffer.writeBigUInt64LE(BigInt(header.offset), offset + 8);
    buffer.writeBigUInt64LE(BigInt(header.virtualAddress), offset + 16);
    buffer.writeBigUInt64LE(BigInt(header.virtualAddress), offset + 24);
    buffer.writeBigUInt64LE(BigInt(header.fileSize), offset + 32);
    buffer.writeBigUInt64LE(BigInt(header.fileSize), offset + 40);
    buffer.writeBigUInt64LE(BigInt(header.alignment), offset + 48);
  }
  const dataSection = sectionHeaderOffset + sectionHeaderEntrySize;
  buffer.writeUInt32LE(1, dataSection + 4);
  buffer.writeBigUInt64LE(0x230n, dataSection + 24);
  buffer.writeBigUInt64LE(0x20n, dataSection + 32);
  return buffer;
}

test("normalizes all 4 KB AArch64 load segments to 16 KB", () => {
  const source = syntheticElf();
  const result = normalizeAndroidElfPageSize(source);
  assert.equal(result.changed, true);
  assert.ok(result.buffer.length > source.length);
  const inspected = inspectAndroidElfPageSize(result.buffer);
  assert.equal(inspected.aarch64, true);
  assert.equal(inspected.compatible, true);
  assert.ok(inspected.loadSegments.every((segment) => segment.alignment === ANDROID_PAGE_SIZE));
});

test("leaves an already compatible ELF byte-identical", () => {
  const source = normalizeAndroidElfPageSize(syntheticElf()).buffer;
  const result = normalizeAndroidElfPageSize(source);
  assert.equal(result.changed, false);
  assert.equal(result.buffer, source);
});

test("leaves non-AArch64 ELF input byte-identical", () => {
  const source = syntheticElf();
  source.writeUInt16LE(62, 18);
  const result = normalizeAndroidElfPageSize(source);
  assert.equal(result.changed, false);
  assert.equal(inspectAndroidElfPageSize(source).aarch64, false);
});
