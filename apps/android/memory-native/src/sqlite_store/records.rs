use super::{SqlResult, SqliteSession};
use diskann::{ANNError, ANNResult};
use rusqlite::{OptionalExtension, params};
use zeroize::Zeroizing;

/// Per-record bounds, not limits on the number of indexed memories.
const MAX_RECORD_BYTES: usize = 1024;

impl SqliteSession {
    /// Checkpoints and provenance share the graph transaction and encryption key.
    pub fn record(&self, key: &[u8]) -> ANNResult<Option<Zeroizing<Vec<u8>>>> {
        self.call(false, |inner| {
            validate_key(key)?;
            let meta = &inner.active.as_ref().unwrap().meta;
            let row: Option<(i64, Option<Vec<u8>>)> = inner.connection.as_ref().unwrap()
                .prepare_cached("SELECT revision,CASE WHEN length(ciphertext) BETWEEN 28 AND ? THEN ciphertext END \
                    FROM index_records WHERE key=?").ann()?
                .query_row(params![(MAX_RECORD_BYTES + 28) as i64, key], |row| Ok((row.get(0)?, row.get(1)?)))
                .optional().ann()?;
            row.map(|(revision, envelope)| {
                if revision <= 0 || revision as u64 > meta.generation {
                    return Err(ANNError::message("Invalid native index record revision"));
                }
                inner.crypto.as_ref().unwrap().decode_record(meta, key, revision as u64,
                    &envelope.ok_or_else(|| ANNError::message("Invalid native index record envelope"))?)
            }).transpose()
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
            inner.connection.as_ref().unwrap().prepare_cached("INSERT INTO index_records(key,revision,ciphertext) VALUES(?,?,?) \
                ON CONFLICT(key) DO UPDATE SET revision=excluded.revision,ciphertext=excluded.ciphertext").ann()?
                .execute(params![key, active.meta.generation as i64, sealed]).ann()?;
            active.dirty = true;
            Ok(())
        })
    }
}
fn validate_key(key: &[u8]) -> ANNResult<()> {
    if key.is_empty() || key.len() > 64 {
        return Err(ANNError::message("Invalid native index record key"));
    }
    Ok(())
}
