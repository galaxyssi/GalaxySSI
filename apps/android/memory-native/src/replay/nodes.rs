use super::format::{Document, Provenance, document_key, node_key};
use crate::{
    sqlite_store::SqliteSession,
    store::{Node, NodeStore, ROOT},
};
use diskann::{ANNError, ANNResult};
use std::sync::Arc;

pub(super) struct SourceNodes {
    pub session: Arc<SqliteSession>,
    pub live_only: bool,
}
impl SourceNodes {
    pub fn provenance(&self, id: u64) -> ANNResult<Provenance> {
        let record = self
            .session
            .record(&node_key(id))?
            .ok_or_else(|| ANNError::message("Native node provenance is missing"))?;
        Provenance::decode(&record)
    }
}
impl NodeStore for SourceNodes {
    fn read(&self, id: u64) -> ANNResult<Node> {
        self.session.read(id)
    }
    fn create(&self, id: u64, vector: &[f32]) -> ANNResult<()> {
        self.session.create(id, vector)
    }
    fn neighbors(&self, id: u64, values: &[u64]) -> ANNResult<()> {
        self.session.neighbors(id, values)
    }
    fn check_active(&self) -> ANNResult<()> {
        self.session.check_active()
    }
    fn visible(&self, id: u64) -> ANNResult<bool> {
        if id == ROOT {
            return Ok(false);
        }
        if !self.live_only {
            return Ok(true);
        }
        let provenance = self.provenance(id)?;
        let bytes = self
            .session
            .record(&document_key(&provenance.key))?
            .ok_or_else(|| ANNError::message("Native source state is missing"))?;
        let document = Document::decode(&bytes)?;
        Ok(document.complete
            && document.revision == provenance.revision
            && document.sequence == provenance.sequence
            && provenance.ordinal < document.count)
    }
}
