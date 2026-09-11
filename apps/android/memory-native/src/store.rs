use diskann::{ANNError, ANNResult};
use zeroize::Zeroizing;

pub const ROOT: u64 = 0;
pub const MAX_NEIGHBORS: usize = 128;

pub(crate) fn validate_vector(vector: &[f32], dimensions: usize) -> ANNResult<()> {
    let norm: f64 = vector.iter().map(|v| f64::from(*v).powi(2)).sum();
    if vector.len() != dimensions || !norm.is_finite() || (norm - 1.0).abs() >= 0.001 {
        return Err(ANNError::message(
            "Native memory vectors and root must be normalized",
        ));
    }
    Ok(())
}

/// Decrypted per-node working data. Never serialize this as a plaintext index.
#[derive(Clone)]
pub struct Node {
    pub vector: Zeroizing<Vec<f32>>,
    pub neighbors: Zeroizing<Vec<u64>>,
}

impl Node {
    pub fn new(vector: &[f32]) -> Self {
        Self {
            vector: Zeroizing::new(vector.to_vec()),
            neighbors: Zeroizing::new(Vec::new()),
        }
    }

    pub fn validate(&self, dimensions: usize) -> ANNResult<()> {
        validate_vector(&self.vector, dimensions)?;
        if self.neighbors.len() > MAX_NEIGHBORS {
            return Err(ANNError::message("Invalid native memory adjacency length"));
        }
        let mut ids = Zeroizing::new(self.neighbors.to_vec());
        ids.sort_unstable();
        ids.dedup();
        if ids.len() != self.neighbors.len() {
            return Err(ANNError::message("Duplicate native memory neighbors"));
        }
        Ok(())
    }
}

/// Host-owned, authenticated storage. One operation must see a stable snapshot.
/// Every insert, including neighbor updates, must be enclosed in one durable
/// host transaction. A failed/cancelled insert MUST roll back that transaction.
/// The adapter has no filesystem fallback and no corpus-sized vector cache.
/// ROOT must be a persisted normalized representative of the same embedding
/// space, not an all-zero centroid (which disconnects normalized data during pruning).
pub trait NodeStore: Send + Sync + 'static {
    fn read(&self, id: u64) -> ANNResult<Node>;
    fn create(&self, id: u64, vector: &[f32]) -> ANNResult<()>;
    fn neighbors(&self, id: u64, values: &[u64]) -> ANNResult<()>;
    fn check_active(&self) -> ANNResult<()>;
}
