use super::{Inner, NodeCacheStats, SqlResult, SqliteIndexStore, read_node, write_node};
use crate::store::{Node, NodeStore, ROOT};
use diskann::{ANNError, ANNResult};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

/// Owns one SQLite snapshot/transaction. Index handles cannot outlive this lease.
pub struct SqliteSession {
    owner: Arc<SqliteIndexStore>,
    token: u64,
    cancelled: Arc<AtomicBool>,
    finished: AtomicBool,
}
impl SqliteSession {
    pub(super) fn new(
        owner: Arc<SqliteIndexStore>,
        token: u64,
        cancelled: Arc<AtomicBool>,
    ) -> Self {
        Self {
            owner,
            token,
            cancelled,
            finished: AtomicBool::new(false),
        }
    }
    pub(super) fn call<T>(
        &self,
        write: bool,
        operation: impl FnOnce(&mut Inner) -> ANNResult<T>,
    ) -> ANNResult<T> {
        let mut inner = self
            .owner
            .inner
            .lock()
            .map_err(|_| ANNError::message("Native index owner poisoned"))?;
        let active = inner
            .active
            .as_mut()
            .filter(|active| active.token == self.token)
            .ok_or_else(|| ANNError::message("Native index session is no longer active"))?;
        if self.finished.load(Ordering::Acquire)
            || self.cancelled.load(Ordering::Acquire)
            || active.failed
            || (write && !active.writable)
        {
            active.failed = true;
            return Err(ANNError::message(
                "Native index session cancelled, failed or read-only",
            ));
        }
        let result = operation(&mut inner);
        if result.is_err() {
            inner.active.as_mut().unwrap().failed = true;
        }
        result
    }
    pub fn node_count(&self) -> ANNResult<u64> {
        self.call(false, |inner| Ok(inner.active.as_ref().unwrap().meta.count))
    }
    pub fn node_cache_stats(&self) -> ANNResult<NodeCacheStats> {
        self.call(false, |inner| {
            Ok(inner.active.as_ref().unwrap().cache.stats())
        })
    }
    pub fn generation(&self) -> ANNResult<u64> {
        self.call(false, |inner| {
            Ok(inner.active.as_ref().unwrap().meta.generation)
        })
    }
    pub fn commit(&self) -> ANNResult<()> {
        self.finish(true)
    }
    pub fn rollback(&self) -> ANNResult<()> {
        self.finish(false)
    }
    fn finish(&self, commit: bool) -> ANNResult<()> {
        if self.finished.swap(true, Ordering::AcqRel) {
            return Err(ANNError::message("Native index session already finished"));
        }
        let mut inner = self
            .owner
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if !inner.active.as_ref().is_some_and(|v| v.token == self.token) {
            return Err(ANNError::message("Native index session owner changed"));
        }
        let active = inner.active.take().unwrap();
        let connection = inner
            .connection
            .as_ref()
            .ok_or_else(|| ANNError::message("Native index is closed"))?;
        let failed = active.failed || self.cancelled.load(Ordering::Acquire);
        let result = if commit && !failed {
            (|| -> ANNResult<()> {
                if active.dirty {
                    let encrypted = inner.crypto.as_ref().unwrap().encode_meta(&active.meta)?;
                    if connection
                        .execute("UPDATE index_state SET sealed=? WHERE id=1", [encrypted])
                        .ann()?
                        != 1
                    {
                        return Err(ANNError::message(
                            "Native index metadata publication failed",
                        ));
                    }
                }
                connection.execute_batch("COMMIT").ann()?;
                Ok(())
            })()
        } else if commit {
            Err(ANNError::message(
                "Failed or cancelled native index transaction cannot commit",
            ))
        } else {
            Ok(())
        };
        if !commit || result.is_err() {
            if connection.execute_batch("ROLLBACK").is_err() {
                inner.connection = None;
                inner.crypto = None;
                return Err(ANNError::message(
                    "Native index rollback failed; reopen the store",
                ));
            }
        }
        result
    }
}
impl NodeStore for SqliteSession {
    fn read(&self, id: u64) -> ANNResult<Node> {
        self.call(false, |inner| {
            let active = inner.active.as_mut().unwrap();
            if let Some(node) = active.cache.get(id) {
                return Ok(node);
            }
            let node = read_node(
                inner.connection.as_ref().unwrap(),
                inner.crypto.as_ref().unwrap(),
                self.owner.config,
                &active.meta,
                id,
            )?
            .ok_or_else(|| ANNError::message("Native index node is missing"))?;
            active.cache.insert(id, &node);
            Ok(node)
        })
    }
    fn create(&self, id: u64, vector: &[f32]) -> ANNResult<()> {
        self.call(true, |inner| {
            if id == ROOT {
                return Err(ANNError::message("Cannot replace the native index root"));
            }
            let active = inner.active.as_mut().unwrap();
            let next_count = active
                .meta
                .count
                .checked_add(1)
                .ok_or_else(|| ANNError::message("Native index node count overflow"))?;
            let node = Node::new(vector);
            write_node(
                inner.connection.as_ref().unwrap(),
                inner.crypto.as_ref().unwrap(),
                self.owner.config,
                &active.meta,
                id,
                &node,
                true,
            )?;
            active.cache.insert(id, &node);
            active.meta.count = next_count;
            active.dirty = true;
            Ok(())
        })
    }
    fn neighbors(&self, id: u64, values: &[u64]) -> ANNResult<()> {
        self.call(true, |inner| {
            let active = inner.active.as_mut().unwrap();
            let connection = inner.connection.as_ref().unwrap();
            let crypto = inner.crypto.as_ref().unwrap();
            let mut node = if let Some(node) = active.cache.get(id) {
                node
            } else {
                read_node(connection, crypto, self.owner.config, &active.meta, id)?
                    .ok_or_else(|| ANNError::message("Native index neighbor target is missing"))?
            };
            node.neighbors.clear();
            node.neighbors.extend_from_slice(values);
            write_node(
                connection,
                crypto,
                self.owner.config,
                &active.meta,
                id,
                &node,
                false,
            )?;
            active.cache.insert(id, &node);
            active.dirty = true;
            Ok(())
        })
    }
    fn check_active(&self) -> ANNResult<()> {
        self.call(false, |_| Ok(()))
    }
}
impl Drop for SqliteSession {
    fn drop(&mut self) {
        if !self.finished.load(Ordering::Acquire) {
            let _ = self.finish(false);
        }
    }
}
