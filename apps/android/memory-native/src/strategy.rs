use crate::{
    provider::{Context, Neighbors, Provider},
    store::{NodeStore, ROOT, validate_vector},
};
use diskann::graph::glue::SearchStrategy;
use diskann::{
    ANNError, ANNResult, default_post_processor,
    error::Infallible,
    graph::{glue, workingset},
    provider,
    utils::VectorRepr,
};
use diskann_vector::{DistanceFunction, distance::Metric};
use zeroize::Zeroizing;

pub(crate) struct Search<'a, S: NodeStore> {
    provider: &'a Provider<S>,
    query: Zeroizing<Vec<f32>>,
}
impl<S: NodeStore> provider::HasId for Search<'_, S> {
    type Id = u64;
}
impl<S: NodeStore> Search<'_, S> {
    fn distance(&self, id: u64) -> ANNResult<f32> {
        let node = self.provider.read(id)?;
        let distance = f32::distance(Metric::L2, Some(self.provider.dimensions))
            .evaluate_similarity(self.query.as_slice(), node.vector.as_slice());
        if !distance.is_finite() {
            return Err(ANNError::message("Non-finite native memory distance"));
        }
        Ok(distance)
    }
}
impl<S: NodeStore> glue::SearchAccessor for Search<'_, S> {
    async fn starting_points(&self) -> ANNResult<Vec<u64>> {
        Ok(vec![ROOT])
    }
    async fn start_point_distances<F>(&mut self, mut callback: F) -> ANNResult<()>
    where
        F: FnMut(u64, f32) + Send,
    {
        callback(ROOT, self.distance(ROOT)?);
        Ok(())
    }
    async fn expand_beam<I, P, F>(
        &mut self,
        ids: I,
        mut predicate: P,
        mut callback: F,
    ) -> ANNResult<()>
    where
        I: Iterator<Item = u64> + Send,
        P: glue::HybridPredicate<u64> + Send + Sync,
        F: FnMut(u64, f32) + Send,
    {
        for id in ids {
            let node = self.provider.read(id)?;
            for next in node.neighbors.iter().filter(|id| predicate.eval_mut(id)) {
                callback(*next, self.distance(*next)?);
            }
        }
        Ok(())
    }
}

// Only the bounded prune working set is retained, never all persisted vectors.
pub(crate) struct Vector(Zeroizing<Vec<f32>>);
impl workingset::map::Project<workingset::map::Ref<[f32]>> for Vector {
    fn project(&self) -> &[f32] {
        self.0.as_slice()
    }
}
type Set = workingset::Map<u64, Vector, workingset::map::Ref<[f32]>>;
type View<'a> = workingset::map::View<'a, u64, Vector, workingset::map::Ref<[f32]>>;
pub(crate) struct Prune<'a, S: NodeStore> {
    provider: &'a Provider<S>,
    set: Set,
}
impl<S: NodeStore> provider::HasId for Prune<'_, S> {
    type Id = u64;
}
impl<S: NodeStore> glue::PruneAccessor for Prune<'_, S> {
    type ElementRef<'a> = &'a [f32];
    type View<'a>
        = View<'a>
    where
        Self: 'a;
    type Distance<'a>
        = <f32 as VectorRepr>::Distance
    where
        Self: 'a;
    type Neighbors<'a>
        = Neighbors<'a, S>
    where
        Self: 'a;
    async fn fill<I>(&mut self, ids: I) -> ANNResult<(Self::View<'_>, Self::Distance<'_>)>
    where
        I: ExactSizeIterator<Item = u64> + Clone + Send + Sync,
    {
        let view = self.set.fill(ids, |id| {
            self.provider.read(id).map(|node| Some(Vector(node.vector)))
        })?;
        Ok((
            view,
            f32::distance(Metric::L2, Some(self.provider.dimensions)),
        ))
    }
    fn neighbors(&mut self) -> Self::Neighbors<'_> {
        Neighbors(self.provider)
    }
}

#[derive(Clone)]
pub(crate) struct Strategy;
impl<'a, S: NodeStore> glue::SearchStrategy<'a, Provider<S>, &'a [f32]> for Strategy {
    type SearchAccessorError = diskann::ANNError;
    type SearchAccessor = Search<'a, S>;
    fn search_accessor(
        &'a self,
        provider: &'a Provider<S>,
        _: &'a Context,
        query: &'a [f32],
    ) -> ANNResult<Self::SearchAccessor> {
        validate_vector(query, provider.dimensions)?;
        Ok(Search {
            provider,
            query: Zeroizing::new(query.to_vec()),
        })
    }
}
impl<'a, S: NodeStore> glue::DefaultPostProcessor<'a, Provider<S>, &'a [f32]> for Strategy {
    default_post_processor!(glue::Pipeline<glue::FilterStartPoints, glue::CopyIds>);
}
impl<S: NodeStore> glue::PruneStrategy<Provider<S>> for Strategy {
    type PruneAccessor<'a> = Prune<'a, S>;
    type PruneAccessorError = Infallible;
    fn prune_accessor<'a>(
        &'a self,
        provider: &'a Provider<S>,
        _: &'a Context,
        capacity: usize,
    ) -> Result<Self::PruneAccessor<'a>, Infallible> {
        Ok(Prune {
            provider,
            set: workingset::map::Builder::new(workingset::map::Capacity::None).build(capacity),
        })
    }
}
impl<'a, S: NodeStore> glue::InsertStrategy<'a, Provider<S>, &'a [f32]> for Strategy {
    type PruneStrategy = Self;
    fn prune_strategy(&self) -> Self {
        self.clone()
    }
    fn insert_search_accessor(
        &'a self,
        provider: &'a Provider<S>,
        context: &'a Context,
        vector: &'a [f32],
    ) -> ANNResult<Self::SearchAccessor> {
        self.search_accessor(provider, context, vector)
    }
}
