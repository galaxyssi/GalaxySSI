use super::{SqlResult, SqliteSession, codec::RecordLayout, records};
use diskann::{ANNError, ANNResult};
use rusqlite::params;

impl SqliteSession {
    pub fn records_partitioned(&self) -> ANNResult<bool> {
        self.call(false, |inner| {
            Ok(inner.active.as_ref().unwrap().meta.records == RecordLayout::Sharded)
        })
    }
    /// Move a bounded page atomically with the authenticated layout checkpoint.
    /// Existing graph IDs, source revisions and replay cursors do not change.
    pub fn migrate_records(&self, limit: usize) -> ANNResult<bool> {
        self.call(true, |inner| {
            if !(1..=256).contains(&limit) {
                return Err(ANNError::message(
                    "Invalid native record migration page size",
                ));
            }
            let active = inner.active.as_mut().unwrap();
            if active.meta.records == RecordLayout::Sharded {
                return Ok(true);
            }
            let connection = inner.connection.as_ref().unwrap();
            let crypto = inner.crypto.as_ref().unwrap();
            if active.meta.records == RecordLayout::Legacy {
                for shard in 0..active.meta.shards {
                    records::create_table(connection, &format!("s{shard}"))?;
                }
                active.meta.records = RecordLayout::Migrating;
            }
            let mut statement = connection
                .prepare(
                    "SELECT CASE WHEN length(key) BETWEEN 1 AND 64 THEN key END,revision, \
                CASE WHEN length(ciphertext) BETWEEN 28 AND 1052 THEN ciphertext END \
                FROM main.index_records ORDER BY key LIMIT ?",
                )
                .ann()?;
            let page = statement
                .query_map([limit as i64], |row| {
                    Ok((
                        row.get::<_, Option<Vec<u8>>>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, Option<Vec<u8>>>(2)?,
                    ))
                })
                .ann()?
                .collect::<rusqlite::Result<Vec<_>>>()
                .ann()?;
            drop(statement);
            for (key, revision, envelope) in page {
                let key =
                    key.ok_or_else(|| ANNError::message("Invalid native index migration key"))?;
                records::validate_key(&key)?;
                let envelope = envelope
                    .ok_or_else(|| ANNError::message("Invalid native index migration envelope"))?;
                records::decode(crypto, &active.meta, &key, revision, Some(envelope.clone()))?;
                let target = records::schema(&key, &active.meta);
                // A duplicate is corruption, not an invitation to overwrite newer provenance.
                connection
                    .prepare_cached(&format!(
                        "INSERT INTO {target}.index_records(key,revision,ciphertext) VALUES(?,?,?)"
                    ))
                    .ann()?
                    .execute(params![key, revision, envelope])
                    .ann()?;
                if connection
                    .execute("DELETE FROM main.index_records WHERE key=?", [&key])
                    .ann()?
                    != 1
                {
                    return Err(ANNError::message("Native index migration source changed"));
                }
            }
            let remaining: bool = connection
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM main.index_records LIMIT 1)",
                    [],
                    |r| r.get(0),
                )
                .ann()?;
            if !remaining {
                active.meta.records = RecordLayout::Sharded;
            }
            active.dirty = true;
            Ok(!remaining)
        })
    }
}
