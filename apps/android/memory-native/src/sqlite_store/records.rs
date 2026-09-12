use super::{
    SqlResult, SqliteSession,
    codec::{Crypto, Metadata, RecordLayout},
};
use diskann::{ANNError, ANNResult};
use rusqlite::{Connection, OptionalExtension, params};
use zeroize::Zeroizing;

/// Per-record bounds, not limits on the number of indexed memories.
pub(super) const MAX_RECORD_BYTES: usize = 1024;

pub(super) fn schema(key: &[u8], meta: &Metadata) -> String {
    if meta.records == RecordLayout::Legacy {
        return "main".into();
    }
    // Persisted FNV-1a routing over the complete opaque key; never Rust's randomized hasher.
    let hash = key.iter().fold(0xcbf29ce484222325u64, |h, b| {
        (h ^ u64::from(*b)).wrapping_mul(0x100000001b3)
    });
    format!("s{}", hash as usize & (meta.shards - 1))
}

pub(super) fn create_table(connection: &Connection, schema: &str) -> ANNResult<()> {
    connection
        .execute_batch(&format!(
            "CREATE TABLE {schema}.index_records (key BLOB PRIMARY KEY \
        CHECK(length(key) BETWEEN 1 AND 64), revision INTEGER NOT NULL CHECK(revision>0), \
        ciphertext BLOB NOT NULL) WITHOUT ROWID"
        ))
        .ann()
}

pub(super) fn check_tables(connection: &Connection, meta: &Metadata) -> ANNResult<()> {
    connection
        .prepare("SELECT key,revision,ciphertext FROM main.index_records LIMIT 0")
        .ann()?;
    if meta.records != RecordLayout::Legacy {
        for shard in 0..meta.shards {
            connection
                .prepare(&format!(
                    "SELECT key,revision,ciphertext FROM s{shard}.index_records LIMIT 0"
                ))
                .ann()?;
        }
    }
    Ok(())
}

pub(super) fn decode(
    crypto: &Crypto,
    meta: &Metadata,
    key: &[u8],
    revision: i64,
    envelope: Option<Vec<u8>>,
) -> ANNResult<Zeroizing<Vec<u8>>> {
    if revision <= 0 || revision as u64 > meta.generation {
        return Err(ANNError::message("Invalid native index record revision"));
    }
    crypto.decode_record(
        meta,
        key,
        revision as u64,
        &envelope.ok_or_else(|| ANNError::message("Invalid native index record envelope"))?,
    )
}

fn read(
    connection: &Connection,
    schema: &str,
    key: &[u8],
) -> ANNResult<Option<(i64, Option<Vec<u8>>)>> {
    connection
        .prepare_cached(&format!(
            "SELECT revision,CASE WHEN length(ciphertext) BETWEEN 28 AND ? THEN ciphertext END \
        FROM {schema}.index_records WHERE key=?"
        ))
        .ann()?
        .query_row(params![(MAX_RECORD_BYTES + 28) as i64, key], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })
        .optional()
        .ann()
}

impl SqliteSession {
    /// Checkpoints and provenance share the graph transaction and encryption key.
    pub fn record(&self, key: &[u8]) -> ANNResult<Option<Zeroizing<Vec<u8>>>> {
        self.call(false, |inner| {
            validate_key(key)?;
            let meta = &inner.active.as_ref().unwrap().meta;
            let connection = inner.connection.as_ref().unwrap();
            let mut row = read(connection, &schema(key, meta), key)?;
            if meta.records == RecordLayout::Migrating {
                let legacy = read(connection, "main", key)?;
                if row.is_some() && legacy.is_some() {
                    return Err(ANNError::message(
                        "Duplicate native index record during migration",
                    ));
                }
                row = row.or(legacy);
            }
            row.map(|(revision, envelope)| {
                decode(
                    inner.crypto.as_ref().unwrap(),
                    meta,
                    key,
                    revision,
                    envelope,
                )
            })
            .transpose()
        })
    }
    pub fn put_record(&self, key: &[u8], value: &[u8]) -> ANNResult<()> {
        self.call(true, |inner| {
            validate_key(key)?;
            if value.len() > MAX_RECORD_BYTES {
                return Err(ANNError::message("Native index record exceeds its bounded layout"));
            }
            let active = inner.active.as_mut().unwrap();
            let sealed = inner.crypto.as_ref().unwrap().encode_record(&active.meta, key, value)?;
            let connection = inner.connection.as_ref().unwrap();
            let target = schema(key, &active.meta);
            if active.meta.records == RecordLayout::Migrating {
                let old = read(connection, "main", key)?;
                if old.is_some() && read(connection, &target, key)?.is_some() {
                    return Err(ANNError::message("Duplicate native index record during migration"));
                }
                if let Some((revision, envelope)) = old {
                    decode(inner.crypto.as_ref().unwrap(), &active.meta, key, revision, envelope)?;
                    connection.execute("DELETE FROM main.index_records WHERE key=?", [key]).ann()?;
                }
            }
            connection.prepare_cached(&format!("INSERT INTO {target}.index_records(key,revision,ciphertext) VALUES(?,?,?) \
                ON CONFLICT(key) DO UPDATE SET revision=excluded.revision,ciphertext=excluded.ciphertext")).ann()?
                .execute(params![key, active.meta.generation as i64, sealed]).ann()?;
            active.dirty = true;
            Ok(())
        })
    }
}
pub(super) fn validate_key(key: &[u8]) -> ANNResult<()> {
    if key.is_empty() || key.len() > 64 {
        return Err(ANNError::message("Invalid native index record key"));
    }
    Ok(())
}
