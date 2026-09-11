use crate::store::{MAX_NEIGHBORS, Node, NodeStore, ROOT, validate_vector};
use diskann::{ANNError, ANNResult, error::Infallible, graph::AdjacencyList, provider};
use std::sync::Arc;

#[derive(Clone)]
pub(crate) struct Context;
impl provider::ExecutionContext for Context {}

pub(crate) struct Provider<S: NodeStore> {
    pub store: Arc<S>,
    pub dimensions: usize,
}

impl<S: NodeStore> Provider<S> {
    pub fn read(&self, id: u64) -> ANNResult<Node> {
        self.store.check_active()?;
        let node = self.store.read(id)?;
        node.validate(self.dimensions)?;
        Ok(node)
    }
}

impl<S: NodeStore> provider::DataProvider for Provider<S> {
    type Context = Context;
    type InternalId = u64;
    type ExternalId = u64;
    type Error = Infallible;
    type Guard = provider::NoopGuard<u64>;
    fn to_internal_id(&self, _: &Context, id: &u64) -> Result<u64, Infallible> {
        Ok(*id)
    }
    fn to_external_id(&self, _: &Context, id: u64) -> Result<u64, Infallible> {
        Ok(id)
    }
}

impl<S: NodeStore> provider::SetElement<&[f32]> for Provider<S> {
    type SetError = diskann::ANNError;
    async fn set_element(&self, _: &Context, id: &u64, vector: &[f32]) -> ANNResult<Self::Guard> {
        self.store.check_active()?;
        if *id == ROOT {
            return Err(ANNError::message("Cannot insert the native memory root"));
        }
        validate_vector(vector, self.dimensions)?;
        self.store.create(*id, vector)?;
        Ok(provider::NoopGuard::new(*id))
    }
}

pub(crate) struct Neighbors<'a, S: NodeStore>(pub &'a Provider<S>);
impl<S: NodeStore> provider::HasId for Neighbors<'_, S> {
    type Id = u64;
}
impl<S: NodeStore> provider::DefaultAccessor for Provider<S> {
    type Accessor<'a> = Neighbors<'a, S>;
    fn default_accessor(&self) -> Self::Accessor<'_> {
        Neighbors(self)
    }
}
impl<S: NodeStore> provider::NeighborAccessor for Neighbors<'_, S> {
    async fn get_neighbors(&mut self, id: u64, output: &mut AdjacencyList<u64>) -> ANNResult<()> {
        let node = self.0.read(id)?;
        output.clear();
        output.extend_from_slice(&node.neighbors);
        Ok(())
    }
}
impl<S: NodeStore> provider::NeighborAccessorMut for Neighbors<'_, S> {
    async fn set_neighbors(&mut self, id: u64, values: &[u64]) -> ANNResult<()> {
        self.0.store.check_active()?;
        if values.len() > MAX_NEIGHBORS {
            return Err(ANNError::message(
                "Native memory adjacency exceeds its format",
            ));
        }
        self.0.store.neighbors(id, values)
    }
    async fn append_vector(&mut self, id: u64, values: &[u64]) -> ANNResult<()> {
        let mut node = self.0.read(id)?;
        for value in values {
            if !node.neighbors.contains(value) {
                node.neighbors.push(*value);
            }
        }
        self.set_neighbors(id, &node.neighbors).await
    }
}
