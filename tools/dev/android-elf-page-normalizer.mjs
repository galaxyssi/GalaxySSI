import {
  readFileSync,
  renameSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";

export const ANDROID_PAGE_SIZE = 16 * 1024;

const ELF_CLASS_64 = 2;
const ELF_DATA_LITTLE_ENDIAN = 1;
const ELF_MACHINE_AARCH64 = 183;
const PROGRAM_HEADER_LOAD = 1;
const SECTION_HEADER_NOBITS = 8;
const ELF64_HEADER_SIZE = 64;

function checkedNumber(value, label) {
  if (value > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new Error(`${label} exceeds the supported file range`);
  }
  return Number(value);
}

function readElf64(buffer) {
  if (buffer.length < ELF64_HEADER_SIZE || buffer.toString("ascii", 0, 4) !== "\x7fELF") {
    throw new Error("input is not an ELF file");
  }
  if (buffer[4] !== ELF_CLASS_64 || buffer[5] !== ELF_DATA_LITTLE_ENDIAN) return null;
  if (buffer.readUInt16LE(18) !== ELF_MACHINE_AARCH64) {
    return null;
  }
  if (buffer[6] !== 1 || buffer.readUInt32LE(20) !== 1) {
    throw new Error("input uses an unsupported ELF version");
  }

  const programHeaderOffset = checkedNumber(buffer.readBigUInt64LE(32), "program header offset");
  const sectionHeaderOffset = checkedNumber(buffer.readBigUInt64LE(40), "section header offset");
  const programHeaderEntrySize = buffer.readUInt16LE(54);
  const programHeaderCount = buffer.readUInt16LE(56);
  const sectionHeaderEntrySize = buffer.readUInt16LE(58);
  const sectionHeaderCount = buffer.readUInt16LE(60);
  if (programHeaderEntrySize < 56 || sectionHeaderEntrySize < 64) {
    throw new Error("ELF header table entry is truncated");
  }

  const programHeaders = [];
  for (let index = 0; index < programHeaderCount; index += 1) {
    const tableOffset = programHeaderOffset + index * programHeaderEntrySize;
    if (tableOffset + 56 > buffer.length) throw new Error("ELF program header table is truncated");
    programHeaders.push({
      index,
      type: buffer.readUInt32LE(tableOffset),
      offset: checkedNumber(buffer.readBigUInt64LE(tableOffset + 8), "segment offset"),
      virtualAddress: checkedNumber(buffer.readBigUInt64LE(tableOffset + 16), "segment virtual address"),
      fileSize: checkedNumber(buffer.readBigUInt64LE(tableOffset + 32), "segment file size"),
      alignment: checkedNumber(buffer.readBigUInt64LE(tableOffset + 48), "segment alignment"),
    });
  }

  const sectionHeaders = [];
  if (sectionHeaderOffset > 0) {
    for (let index = 0; index < sectionHeaderCount; index += 1) {
      const tableOffset = sectionHeaderOffset + index * sectionHeaderEntrySize;
      if (tableOffset + 64 > buffer.length) throw new Error("ELF section header table is truncated");
      sectionHeaders.push({
        index,
        type: buffer.readUInt32LE(tableOffset + 4),
        offset: checkedNumber(buffer.readBigUInt64LE(tableOffset + 24), "section offset"),
      });
    }
  }

  return {
    programHeaderOffset,
    sectionHeaderOffset,
    programHeaderEntrySize,
    sectionHeaderEntrySize,
    programHeaders,
    sectionHeaders,
  };
}

function requiredInsertions(programHeaders, pageSize) {
  const loads = programHeaders
    .filter((header) => header.type === PROGRAM_HEADER_LOAD)
    .sort((left, right) => left.offset - right.offset);
  if (!loads.length) throw new Error("AArch64 ELF contains no loadable segments");

  const insertions = [];
  let cumulative = 0;
  for (const load of loads) {
    const currentOffset = load.offset + cumulative;
    const desiredRemainder = load.virtualAddress % pageSize;
    const currentRemainder = currentOffset % pageSize;
    const padding = (desiredRemainder - currentRemainder + pageSize) % pageSize;
    if (!padding) continue;
    if (load.offset === 0) throw new Error("the first ELF load segment cannot be realigned safely");

    for (const header of programHeaders) {
      const end = header.offset + header.fileSize;
      if (header.fileSize > 0 && header.offset < load.offset && end > load.offset) {
        throw new Error("ELF load boundary overlaps another file-backed segment");
      }
    }
    insertions.push({ offset: load.offset, padding });
    cumulative += padding;
  }
  return insertions;
}

function translateOffset(offset, insertions) {
  if (offset === 0) return 0;
  return offset + insertions.reduce(
    (total, insertion) => total + (insertion.offset <= offset ? insertion.padding : 0),
    0,
  );
}

function insertPadding(buffer, insertions) {
  let output = buffer;
  for (const insertion of [...insertions].sort((left, right) => right.offset - left.offset)) {
    output = Buffer.concat([
      output.subarray(0, insertion.offset),
      Buffer.alloc(insertion.padding),
      output.subarray(insertion.offset),
    ]);
  }
  return output;
}

function writeNormalizedHeaders(output, elf, insertions, pageSize) {
  const programHeaderOffset = translateOffset(elf.programHeaderOffset, insertions);
  const sectionHeaderOffset = translateOffset(elf.sectionHeaderOffset, insertions);
  output.writeBigUInt64LE(BigInt(programHeaderOffset), 32);
  output.writeBigUInt64LE(BigInt(sectionHeaderOffset), 40);

  for (const header of elf.programHeaders) {
    const tableOffset = programHeaderOffset + header.index * elf.programHeaderEntrySize;
    output.writeBigUInt64LE(BigInt(translateOffset(header.offset, insertions)), tableOffset + 8);
    if (header.type === PROGRAM_HEADER_LOAD && header.alignment < pageSize) {
      output.writeBigUInt64LE(BigInt(pageSize), tableOffset + 48);
    }
  }

  for (const section of elf.sectionHeaders) {
    if (section.offset === 0 || section.type === SECTION_HEADER_NOBITS) continue;
    const tableOffset = sectionHeaderOffset + section.index * elf.sectionHeaderEntrySize;
    output.writeBigUInt64LE(BigInt(translateOffset(section.offset, insertions)), tableOffset + 24);
  }
}

export function inspectAndroidElfPageSize(buffer, pageSize = ANDROID_PAGE_SIZE) {
  const elf = readElf64(buffer);
  if (!elf) return { aarch64: false, compatible: true, loadSegments: [] };
  const loadSegments = elf.programHeaders
    .filter((header) => header.type === PROGRAM_HEADER_LOAD)
    .map((header) => ({
      offset: header.offset,
      virtualAddress: header.virtualAddress,
      alignment: header.alignment,
    }));
  return {
    aarch64: true,
    compatible: loadSegments.every((segment) =>
      segment.alignment >= pageSize &&
      segment.offset % pageSize === segment.virtualAddress % pageSize
    ),
    loadSegments,
  };
}

export function normalizeAndroidElfPageSize(buffer, pageSize = ANDROID_PAGE_SIZE) {
  const elf = readElf64(buffer);
  if (!elf) return { buffer, changed: false, insertions: [] };
  const before = inspectAndroidElfPageSize(buffer, pageSize);
  if (before.compatible) return { buffer, changed: false, insertions: [] };

  const insertions = requiredInsertions(elf.programHeaders, pageSize);
  const output = insertPadding(buffer, insertions);
  writeNormalizedHeaders(output, elf, insertions, pageSize);
  const after = inspectAndroidElfPageSize(output, pageSize);
  if (!after.compatible) throw new Error("ELF page-size normalization did not produce a compatible file");
  return { buffer: output, changed: true, insertions };
}

export function normalizeAndroidElfFile(file, pageSize = ANDROID_PAGE_SIZE) {
  const source = readFileSync(file);
  const normalized = normalizeAndroidElfPageSize(source, pageSize);
  if (!normalized.changed) return { ...normalized, beforeBytes: source.length, afterBytes: source.length };

  const temporary = join(dirname(file), `.${Date.now()}-${process.pid}-${Math.random().toString(16).slice(2)}.tmp`);
  writeFileSync(temporary, normalized.buffer, { mode: statSync(file).mode });
  renameSync(temporary, file);
  return {
    ...normalized,
    beforeBytes: source.length,
    afterBytes: normalized.buffer.length,
  };
}
