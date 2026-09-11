//! Bounded source replay and provenance are committed with the encrypted graph.
pub mod format;
mod nodes;
use crate::{
    Index,
    sqlite_store::{SqliteIndexStore, SqliteSession},
    store::NodeStore,
};
use diskann::{ANNError, ANNResult};
use format::{
    CURSOR_KEY, Checkpoint, Document, Event, Pending, Provenance, document_key, node_key,
};
use nodes::SourceNodes;
use std::sync::{Arc, atomic::AtomicBool};
use zeroize::Zeroizing;

pub struct Chunk {
    pub ordinal: u64,
    pub start: u64,
    pub end: u64,
    pub vector: Zeroizing<Vec<f32>>,
}
pub struct Match {
    pub source: Provenance,
    pub similarity: f32,
}
pub struct ReplayIndex {
    store: Arc<SqliteIndexStore>,
    epoch: [u8; 16],
    cancelled: Arc<AtomicBool>,
}
impl ReplayIndex {
    pub fn attach(
        store: Arc<SqliteIndexStore>,
        epoch: [u8; 16],
        cancelled: Arc<AtomicBool>,
        initialize: bool,
    ) -> ANNResult<Self> {
        let session = store.begin(initialize, cancelled.clone())?;
        let current = session.record(CURSOR_KEY)?;
        match current {
            Some(bytes) => {
                if Checkpoint::decode(&bytes)?.epoch != epoch {
                    return Err(error("Native replay epoch changed"));
                }
            }
            None if initialize && session.node_count()? == 1 => {
                session.put_record(
                    CURSOR_KEY,
                    &Checkpoint {
                        epoch,
                        last: None,
                        pending: None,
                    }
                    .encode(),
                )?;
            }
            None => {
                return Err(error(
                    "Native replay checkpoint is missing; rebuild the derived index",
                ));
            }
        }
        session.commit()?;
        Ok(Self {
            store,
            epoch,
            cancelled,
        })
    }
    fn checkpoint_in(&self, session: &SqliteSession) -> ANNResult<Checkpoint> {
        let bytes = session
            .record(CURSOR_KEY)?
            .ok_or_else(|| error("Native replay checkpoint is missing"))?;
        let checkpoint = Checkpoint::decode(&bytes)?;
        if checkpoint.epoch != self.epoch {
            return Err(error("Native replay epoch changed"));
        }
        Ok(checkpoint)
    }
    pub fn checkpoint(&self) -> ANNResult<Checkpoint> {
        let session = self.store.begin(false, self.cancelled.clone())?;
        let checkpoint = self.checkpoint_in(&session)?;
        session.commit()?;
        Ok(checkpoint)
    }
    pub fn node_count(&self) -> ANNResult<u64> {
        let session = self.store.begin(false, self.cancelled.clone())?;
        let count = session.node_count()?;
        session.commit()?;
        Ok(count)
    }
    /// Skip is used when the authoritative source no longer matches a ready event.
    pub fn begin_event(&self, event: &Event, skip: bool) -> ANNResult<Checkpoint> {
        event.validate()?;
        let session = self.store.begin(true, self.cancelled.clone())?;
        let mut checkpoint = self.checkpoint_in(&session)?;
        if event.sequence <= checkpoint.sequence() {
            if checkpoint
                .last
                .as_ref()
                .is_some_and(|last| last.sequence == event.sequence && last != event)
            {
                return Err(error("Replayed event changed its identity"));
            }
            session.commit()?;
            return Ok(checkpoint);
        }
        if event.previous != checkpoint.sequence() {
            return Err(error("Native replay has a missing predecessor"));
        }
        if let Some(pending) = &checkpoint.pending {
            if pending.event != *event {
                return Err(error("Finish or invalidate the pending native event first"));
            }
            if !skip {
                session.commit()?;
                return Ok(checkpoint);
            }
        }
        let complete = !event.removed && !skip && event.chunks == 0;
        session.put_record(
            &document_key(&event.key),
            &Document {
                revision: event.revision,
                sequence: event.sequence,
                count: event.chunks,
                complete,
            }
            .encode(),
        )?;
        if skip || event.removed || complete {
            checkpoint.last = Some(event.clone());
            checkpoint.pending = None;
        } else {
            checkpoint.pending = Some(Pending {
                event: event.clone(),
                next: 0,
            });
        }
        session.put_record(CURSOR_KEY, &checkpoint.encode())?;
        session.commit()?;
        Ok(checkpoint)
    }
    pub async fn append(&self, event: &Event, chunks: &[Chunk]) -> ANNResult<Checkpoint> {
        if chunks.is_empty() || chunks.len() > 64 {
            return Err(error("Invalid native replay batch size"));
        }
        let session = self.store.begin(true, self.cancelled.clone())?;
        let mut checkpoint = self.checkpoint_in(&session)?;
        if checkpoint.last.as_ref() == Some(event) {
            session.commit()?;
            return Ok(checkpoint);
        }
        let pending = checkpoint
            .pending
            .as_mut()
            .filter(|p| p.event == *event)
            .ok_or_else(|| error("Native vector batch has no matching pending event"))?;
        let first = chunks[0].ordinal;
        let end = first
            .checked_add(chunks.len() as u64)
            .ok_or_else(|| error("Native ordinal overflow"))?;
        if end <= pending.next {
            session.commit()?;
            return Ok(checkpoint);
        }
        if first != pending.next || end > event.chunks {
            return Err(error("Native vector batch has a gap or overlap"));
        }
        let nodes = Arc::new(SourceNodes {
            session: session.clone(),
            live_only: false,
        });
        let index = Index::open(nodes, self.store.config().dimensions)?;
        for (offset, chunk) in chunks.iter().enumerate() {
            if chunk.ordinal != first + offset as u64 || chunk.start >= chunk.end {
                return Err(error("Invalid native vector provenance"));
            }
            let id = session.node_count()?;
            index.insert(id, &chunk.vector).await?;
            session.put_record(
                &node_key(id),
                &Provenance {
                    key: event.key,
                    revision: event.revision,
                    sequence: event.sequence,
                    ordinal: chunk.ordinal,
                    start: chunk.start,
                    end: chunk.end,
                }
                .encode(),
            )?;
        }
        pending.next = end;
        if end == event.chunks {
            session.put_record(
                &document_key(&event.key),
                &Document {
                    revision: event.revision,
                    sequence: event.sequence,
                    count: event.chunks,
                    complete: true,
                }
                .encode(),
            )?;
            checkpoint.pending = None;
            checkpoint.last = Some(event.clone());
        }
        session.put_record(CURSOR_KEY, &checkpoint.encode())?;
        session.commit()?;
        Ok(checkpoint)
    }
    pub async fn search(
        &self,
        query: &[f32],
        count: usize,
        breadth: usize,
    ) -> ANNResult<Vec<Match>> {
        let session = self.store.begin(false, self.cancelled.clone())?;
        self.checkpoint_in(&session)?;
        let nodes = Arc::new(SourceNodes {
            session: session.clone(),
            live_only: true,
        });
        let index = Index::open(nodes.clone(), self.store.config().dimensions)?;
        let candidates = index.search(query, count, breadth).await?;
        let mut results = Vec::with_capacity(candidates.len());
        for (id, _) in candidates {
            let node = session.read(id)?;
            let similarity = node
                .vector
                .iter()
                .zip(query)
                .map(|(a, b)| a * b)
                .sum::<f32>()
                .clamp(-1.0, 1.0);
            results.push(Match {
                source: nodes.provenance(id)?,
                similarity,
            });
        }
        session.commit()?;
        Ok(results)
    }
}
fn error(message: &'static str) -> ANNError {
    ANNError::message(message)
}
