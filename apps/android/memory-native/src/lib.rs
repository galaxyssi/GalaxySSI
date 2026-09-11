#[cfg(feature = "android-jni")]
mod jni_bridge;
mod provider;
#[cfg(feature = "sqlite-store")]
pub mod replay;
#[cfg(feature = "sqlite-store")]
pub mod sqlite_store;
pub mod store;
mod strategy;

use crate::{
    provider::{Context, Provider},
    store::{NodeStore, ROOT},
    strategy::Strategy,
};
use diskann::{
    ANNError, ANNResult,
    graph::{self, DiskANNIndex},
};
use diskann_vector::distance::Metric;
use std::{num::NonZeroUsize, sync::Arc};

/// Disk graph engine. The caller supplies authenticated storage and owns the
/// transaction/snapshot and lifecycle boundaries for every operation.
pub struct Index<S: NodeStore> {
    graph: DiskANNIndex<Provider<S>>,
}

impl<S: NodeStore> Index<S> {
    pub fn open(store: Arc<S>, dimensions: usize) -> ANNResult<Self> {
        if !(1..=8192).contains(&dimensions) {
            return Err(ANNError::message("Invalid native memory dimensions"));
        }
        let provider = Provider { store, dimensions };
        provider.read(ROOT)?;
        let config = graph::config::Builder::new(
            32,
            graph::config::MaxDegree::default_slack(),
            128,
            Metric::L2.into(),
        )
        .build()?;
        Ok(Self {
            graph: DiskANNIndex::new(config, provider, NonZeroUsize::new(1)),
        })
    }

    /// Caller must roll back the entire host transaction on failure.
    pub async fn insert(&self, id: u64, vector: &[f32]) -> ANNResult<()> {
        self.graph.insert(&Strategy, &Context, &id, vector).await
    }

    pub async fn search(
        &self,
        query: &[f32],
        count: usize,
        breadth: usize,
    ) -> ANNResult<Vec<(u64, f32)>> {
        if count == 0 || count > 256 || breadth <= count || breadth > 4096 {
            return Err(ANNError::message("Invalid native memory search parameters"));
        }
        let mut ids = vec![0; count];
        let mut distances = vec![0.0; count];
        let mut output = graph::search_output_buffer::IdDistance::new(&mut ids, &mut distances);
        let result = self
            .graph
            .search(
                graph::search::Knn::new_default(breadth)?,
                &Strategy,
                &Context,
                query,
                &mut output,
            )
            .await?;
        Ok(ids
            .into_iter()
            .zip(distances)
            .take(result.result_count as usize)
            .collect())
    }
}
