#![allow(non_snake_case)]
mod buffers;
mod owner;
#[cfg(test)]
mod tests;

use buffers::{Output, aligned, floats, input};
use galaxyssi_memory_native::{replay::{Chunk, ReplayIndex, format::Event}, sqlite_store::{SqliteIndexStore, StoreConfig}};
use std::{panic::{AssertUnwindSafe, catch_unwind}, path::PathBuf, sync::{Arc, atomic::AtomicBool}};
use zeroize::Zeroizing;

type Result<T> = std::result::Result<T, String>;
trait Checked<T> { fn checked(self) -> Result<T>; }
impl<T, E: std::fmt::Display> Checked<T> for std::result::Result<T, E> {
    fn checked(self) -> Result<T> { self.map_err(|error| error.to_string()) }
}

fn boundary(call: impl FnOnce() -> Result<()>) -> i32 {
    match catch_unwind(AssertUnwindSafe(call)) {
        Ok(Ok(())) => 0,
        Ok(Err(_)) => 1,
        Err(_) => 2,
    }
}

unsafe fn decode_event(pointer: *const u8, length: usize) -> Result<Event> {
    let bytes = unsafe { input(pointer, length, 93, 93) }?;
    let event = Event::decode(&bytes).checked()?;
    if [event.sequence, event.previous, event.chunks].iter().any(|value| *value > i64::MAX as u64) {
        return Err("Event exceeds source ledger range".into());
    }
    Ok(event)
}

#[repr(C)]
pub struct OpenConfig {
    pub abi_version: u32,
    pub dimensions: u32,
    pub shards: u32,
    pub cache_bytes: u64,
    pub key: [u8; 32],
    pub identity: [u8; 32],
    pub epoch: [u8; 16],
}

/// All C pointers must refer to valid, aligned, non-overlapping caller-owned regions.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gs_memory_open(path: *const u8, path_length: usize, config: *const OpenConfig,
    root: *const f32, root_length: usize, handle: *mut i64) -> i32 {
    boundary(|| {
        if !aligned(handle) { return Err("Invalid handle output".into()); }
        unsafe { handle.write(0); }
        if !aligned(config) { return Err("Invalid configuration".into()); }
        let config = unsafe { &*config };
        if config.abi_version != 1 || !(1..=8192).contains(&config.dimensions)
            || !(1..=64).contains(&config.shards) || config.cache_bytes == 0
            || config.cache_bytes > 256 * 1024 * 1024 {
            return Err("Invalid configuration".into());
        }
        let path = unsafe { input(path, path_length, 1, 4096) }?;
        let text = std::str::from_utf8(&path).checked()?;
        if text.contains('\0') { return Err("Invalid path".into()); }
        let path = PathBuf::from(text);
        if !path.is_absolute() { return Err("Relative index path".into()); }
        let dimensions = config.dimensions as usize;
        let settings = StoreConfig { dimensions, shards: config.shards as usize, cache_bytes: config.cache_bytes as usize };
        let key = Zeroizing::new(config.key);
        let create = !root.is_null();
        let store = if create {
            let root = unsafe { floats(root, root_length, dimensions) }?;
            SqliteIndexStore::create(&path, key, config.identity, settings, &root).checked()?
        } else {
            if root_length != 0 { return Err("Unexpected root length".into()); }
            SqliteIndexStore::open(&path, key, config.identity, settings).checked()?
        };
        let cancelled = Arc::new(AtomicBool::new(false));
        let index = ReplayIndex::attach(store, config.epoch, cancelled.clone(), create).checked()?;
        let id = owner::add(index, cancelled, dimensions)?;
        unsafe { handle.write(id); }
        Ok(())
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn gs_memory_checkpoint(handle: i64, bytes: *mut u8, capacity: usize, written: *mut usize) -> i32 {
    boundary(|| {
        let output = unsafe { Output::prepare(bytes, capacity, written, 208) }?;
        owner::access(handle, |engine| unsafe { output.write(&engine.index.checkpoint().checked()?.encode()) })
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn gs_memory_begin(handle: i64, event: *const u8, event_length: usize, skip: u8,
    bytes: *mut u8, capacity: usize, written: *mut usize) -> i32 {
    boundary(|| {
        let output = unsafe { Output::prepare(bytes, capacity, written, 208) }?;
        if skip > 1 { return Err("Invalid skip flag".into()); }
        let event = unsafe { decode_event(event, event_length) }?;
        owner::access(handle, |engine| unsafe { output.write(&engine.index.begin_event(&event, skip == 1).checked()?.encode()) })
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn gs_memory_append(handle: i64, event: *const u8, event_length: usize,
    metadata: *const u64, metadata_length: usize, values: *const f32, values_length: usize,
    bytes: *mut u8, capacity: usize, written: *mut usize) -> i32 {
    boundary(|| {
        let output = unsafe { Output::prepare(bytes, capacity, written, 208) }?;
        let event = unsafe { decode_event(event, event_length) }?;
        let metadata = unsafe { input(metadata, metadata_length, 3, 64 * 3) }?;
        if metadata.len() % 3 != 0 || metadata.iter().any(|value| *value > i64::MAX as u64) {
            return Err("Invalid replay metadata".into());
        }
        owner::access(handle, |engine| {
            let count = metadata.len() / 3;
            let values = unsafe { floats(values, values_length, count * engine.dimensions) }?;
            let chunks: Vec<_> = metadata.chunks_exact(3).zip(values.chunks_exact(engine.dimensions))
                .map(|(m, vector)| Chunk { ordinal: m[0], start: m[1], end: m[2], vector: Zeroizing::new(vector.to_vec()) }).collect();
            let checkpoint = engine.runtime.block_on(engine.index.append(&event, &chunks)).checked()?;
            unsafe { output.write(&checkpoint.encode()) }
        })
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn gs_memory_search(handle: i64, query: *const f32, query_length: usize,
    count: u32, breadth: u32, bytes: *mut u8, capacity: usize, written: *mut usize) -> i32 {
    boundary(|| {
        if !(1..=256).contains(&count) || breadth <= count || breadth > 4096 {
            return Err("Invalid search bounds".into());
        }
        let output = unsafe { Output::prepare(bytes, capacity, written, 8 + count as usize * 104) }?;
        owner::access(handle, |engine| {
            let query = unsafe { floats(query, query_length, engine.dimensions) }?;
            let matches = engine.runtime.block_on(engine.index.search(&query, count as usize, breadth as usize)).checked()?;
            if matches.len() > count as usize { return Err("Oversized search result".into()); }
            let mut bytes = Zeroizing::new(b"GSM1".to_vec());
            bytes.extend_from_slice(&(matches.len() as u32).to_le_bytes());
            for matched in matches {
                bytes.extend_from_slice(&matched.source.encode());
                bytes.extend_from_slice(&matched.similarity.to_le_bytes());
            }
            unsafe { output.write(&bytes) }
        })
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn gs_memory_node_count(handle: i64, count: *mut u64) -> i32 {
    boundary(|| {
        if !aligned(count) { return Err("Invalid count output".into()); }
        unsafe { count.write(0); }
        owner::access(handle, |engine| {
            let value = engine.index.node_count().checked()?;
            unsafe { count.write(value); }
            Ok(())
        })
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn gs_memory_records_partitioned(handle: i64, complete: *mut u8) -> i32 {
    boundary(|| {
        if !aligned(complete) { return Err("Invalid layout output".into()); }
        unsafe { complete.write(0); }
        owner::access(handle, |engine| {
            let value = engine.index.records_partitioned().checked()?;
            unsafe { complete.write(u8::from(value)); }
            Ok(())
        })
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn gs_memory_migrate_records(handle: i64, limit: u32, complete: *mut u8) -> i32 {
    boundary(|| {
        if !aligned(complete) { return Err("Invalid migration output".into()); }
        unsafe { complete.write(0); }
        if !(1..=256).contains(&limit) { return Err("Invalid migration page size".into()); }
        owner::access(handle, |engine| {
            let value = engine.index.migrate_records(limit as usize).checked()?;
            unsafe { complete.write(u8::from(value)); }
            Ok(())
        })
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn gs_memory_cancel(handle: i64) -> i32 { boundary(|| owner::cancel(handle)) }

#[unsafe(no_mangle)]
pub extern "C" fn gs_memory_close(handle: i64) -> i32 { boundary(|| owner::remove(handle)) }
