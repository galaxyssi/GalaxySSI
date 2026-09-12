//! Synchronous, bounded JNI calls. Kotlin owns workers; no Java references cross calls.
mod arrays;
mod owner;
use crate::{
    replay::{Chunk, ReplayIndex, format::Event},
    sqlite_store::{SqliteIndexStore, StoreConfig},
};
use arrays::*;
use jni::{
    JNIEnv,
    objects::{JByteArray, JClass, JFloatArray, JLongArray, JString},
    sys::{jboolean, jbyteArray, jint, jlong},
};
use std::{
    panic::{AssertUnwindSafe, catch_unwind},
    path::PathBuf,
    sync::{Arc, atomic::AtomicBool},
};
use zeroize::Zeroizing;

type Result<T> = std::result::Result<T, String>;
trait Checked<T> {
    fn checked(self) -> Result<T>;
}
impl<T, E: std::fmt::Display> Checked<T> for std::result::Result<T, E> {
    fn checked(self) -> Result<T> {
        self.map_err(|e| e.to_string())
    }
}
fn guard<T: Default>(mut env: JNIEnv, call: impl FnOnce(&mut JNIEnv) -> Result<T>) -> T {
    match catch_unwind(AssertUnwindSafe(|| call(&mut env))) {
        Ok(Ok(value)) => value,
        failed => {
            let message = match failed {
                Ok(Err(e)) => e,
                _ => "Native memory operation panicked".into(),
            };
            if !env.exception_check().unwrap_or(true) {
                let _ = env.throw_new("java/lang/IllegalStateException", message);
            }
            T::default()
        }
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_galaxyssi_chat_KnowledgeNativeBridge_openIndex(
    env: JNIEnv,
    _: JClass,
    path: JString,
    key: JByteArray,
    identity: JByteArray,
    epoch: JByteArray,
    dimensions: jint,
    shards: jint,
    cache_bytes: jlong,
    root: JFloatArray,
) -> jlong {
    guard(env, |env| {
        if !(1..=8192).contains(&dimensions)
            || !(1..=64).contains(&shards)
            || cache_bytes <= 0
            || cache_bytes > 256 * 1024 * 1024
        {
            return Err("Invalid native memory configuration".into());
        }
        let key = bytes(env, &key, 32, 32)?;
        let key = Zeroizing::new(<[u8; 32]>::try_from(key.as_slice()).unwrap());
        let identity: [u8; 32] = bytes(env, &identity, 32, 32)?
            .as_slice()
            .try_into()
            .unwrap();
        let epoch: [u8; 16] = bytes(env, &epoch, 16, 16)?.as_slice().try_into().unwrap();
        let path: String = env.get_string(&path).checked()?.into();
        if path.len() > 4096 || path.contains('\0') {
            return Err("Invalid native index path".into());
        }
        let path = PathBuf::from(path);
        if !path.is_absolute() {
            return Err("Native index path must be absolute".into());
        }
        let config = StoreConfig {
            dimensions: dimensions as usize,
            shards: shards as usize,
            cache_bytes: cache_bytes as usize,
        };
        let create = !root.is_null();
        let store = if create {
            let root = floats(env, &root, dimensions as usize)?;
            SqliteIndexStore::create(&path, key, identity, config, &root).checked()?
        } else {
            SqliteIndexStore::open(&path, key, identity, config).checked()?
        };
        let cancelled = Arc::new(AtomicBool::new(false));
        let index = ReplayIndex::attach(store, epoch, cancelled.clone(), create).checked()?;
        owner::add(index, cancelled, dimensions as usize)
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_galaxyssi_chat_KnowledgeNativeBridge_recordsPartitioned(
    env: JNIEnv,
    _: JClass,
    handle: jlong,
) -> jboolean {
    guard(env, |_| {
        owner::access(handle, |engine| {
            Ok(u8::from(engine.index.records_partitioned().checked()?))
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_galaxyssi_chat_KnowledgeNativeBridge_migrateRecords(
    env: JNIEnv,
    _: JClass,
    handle: jlong,
) -> jboolean {
    guard(env, |_| {
        owner::access(handle, |engine| {
            Ok(u8::from(engine.index.migrate_records(64).checked()?))
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_galaxyssi_chat_KnowledgeNativeBridge_checkpoint(
    env: JNIEnv,
    _: JClass,
    handle: jlong,
) -> jbyteArray {
    guard(env, |env| {
        owner::access(handle, |engine| {
            output(env, &engine.index.checkpoint().checked()?.encode())
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_galaxyssi_chat_KnowledgeNativeBridge_beginEvent(
    env: JNIEnv,
    _: JClass,
    handle: jlong,
    event: JByteArray,
    skip: jboolean,
) -> jbyteArray {
    guard(env, |env| {
        let event = Event::decode(&bytes(env, &event, 93, 93)?).checked()?;
        owner::access(handle, |engine| {
            output(
                env,
                &engine
                    .index
                    .begin_event(&event, skip != 0)
                    .checked()?
                    .encode(),
            )
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_galaxyssi_chat_KnowledgeNativeBridge_append(
    env: JNIEnv,
    _: JClass,
    handle: jlong,
    event: JByteArray,
    metadata: JLongArray,
    values: JFloatArray,
) -> jbyteArray {
    guard(env, |env| {
        let event = Event::decode(&bytes(env, &event, 93, 93)?).checked()?;
        let metadata = longs(env, &metadata, 3, 64 * 3)?;
        if metadata.len() % 3 != 0 || metadata.iter().any(|v| *v < 0) {
            return Err("Invalid vector page metadata".into());
        }
        owner::access(handle, |engine| {
            let n = metadata.len() / 3;
            let values = floats(env, &values, n * engine.dimensions)?;
            let chunks: Vec<_> = metadata
                .chunks_exact(3)
                .zip(values.chunks_exact(engine.dimensions))
                .map(|(m, v)| Chunk {
                    ordinal: m[0] as u64,
                    start: m[1] as u64,
                    end: m[2] as u64,
                    vector: Zeroizing::new(v.to_vec()),
                })
                .collect();
            let checkpoint = engine
                .runtime
                .block_on(engine.index.append(&event, &chunks))
                .checked()?;
            output(env, &checkpoint.encode())
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_galaxyssi_chat_KnowledgeNativeBridge_search(
    env: JNIEnv,
    _: JClass,
    handle: jlong,
    query: JFloatArray,
    count: jint,
    breadth: jint,
) -> jbyteArray {
    guard(env, |env| {
        owner::access(handle, |engine| {
            if !(1..=256).contains(&count) || breadth <= count || breadth > 4096 {
                return Err("Invalid native search bounds".into());
            }
            let query = floats(env, &query, engine.dimensions)?;
            let matches = engine
                .runtime
                .block_on(
                    engine
                        .index
                        .search(&query, count as usize, breadth as usize),
                )
                .checked()?;
            let mut result = Zeroizing::new(b"GSM1".to_vec());
            result.extend_from_slice(&(matches.len() as u32).to_le_bytes());
            for m in matches {
                result.extend_from_slice(&m.source.encode());
                result.extend_from_slice(&m.similarity.to_le_bytes());
            }
            output(env, &result)
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_galaxyssi_chat_KnowledgeNativeBridge_nodeCount(
    env: JNIEnv,
    _: JClass,
    handle: jlong,
) -> jlong {
    guard(env, |_| {
        owner::access(handle, |engine| {
            i64::try_from(engine.index.node_count().checked()?).checked()
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_galaxyssi_chat_KnowledgeNativeBridge_cancel(
    env: JNIEnv,
    _: JClass,
    handle: jlong,
) {
    guard(env, |_| owner::cancel(handle));
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_galaxyssi_chat_KnowledgeNativeBridge_closeIndex(
    env: JNIEnv,
    _: JClass,
    handle: jlong,
) {
    guard(env, |_| owner::remove(handle));
}
