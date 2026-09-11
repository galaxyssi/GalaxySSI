use diskann::{ANNError, ANNResult};
use galaxyssi_memory_native::{
    Index,
    store::{Node, NodeStore, ROOT},
};
use std::{
    collections::BTreeMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
};

struct Store {
    nodes: Mutex<BTreeMap<u64, Node>>,
    reads: AtomicUsize,
    cancelled: AtomicBool,
    fail_next_neighbor_write: AtomicBool,
    failed_writes: AtomicUsize,
}
impl Store {
    fn new(dimensions: usize) -> Arc<Self> {
        let mut root = vec![0.0; dimensions];
        root[0] = 1.0;
        Arc::new(Self {
            nodes: Mutex::new(BTreeMap::from([(ROOT, Node::new(&root))])),
            reads: AtomicUsize::new(0),
            cancelled: AtomicBool::new(false),
            fail_next_neighbor_write: AtomicBool::new(false),
            failed_writes: AtomicUsize::new(0),
        })
    }
    fn transaction<T>(&self, operation: impl FnOnce() -> ANNResult<T>) -> ANNResult<T> {
        let before = self.nodes.lock().unwrap().clone();
        let result = operation();
        if result.is_err() {
            *self.nodes.lock().unwrap() = before;
        }
        result
    }
}
impl NodeStore for Store {
    fn read(&self, id: u64) -> ANNResult<Node> {
        self.reads.fetch_add(1, Ordering::Relaxed);
        self.nodes
            .lock()
            .unwrap()
            .get(&id)
            .cloned()
            .ok_or_else(|| ANNError::message("missing fixture node"))
    }
    fn create(&self, id: u64, vector: &[f32]) -> ANNResult<()> {
        let mut nodes = self.nodes.lock().unwrap();
        if nodes.contains_key(&id) {
            return Err(ANNError::message("duplicate fixture node"));
        }
        nodes.insert(id, Node::new(vector));
        Ok(())
    }
    fn neighbors(&self, id: u64, neighbors: &[u64]) -> ANNResult<()> {
        let mut nodes = self.nodes.lock().unwrap();
        let node = nodes
            .get_mut(&id)
            .ok_or_else(|| ANNError::message("missing fixture node"))?;
        node.neighbors.clear();
        node.neighbors.extend_from_slice(neighbors);
        if self.fail_next_neighbor_write.swap(false, Ordering::SeqCst) {
            self.failed_writes.fetch_add(1, Ordering::Relaxed);
            return Err(ANNError::message(
                "injected failure after neighbor mutation",
            ));
        }
        Ok(())
    }
    fn check_active(&self) -> ANNResult<()> {
        if self.cancelled.load(Ordering::SeqCst) {
            return Err(ANNError::message("fixture cancelled"));
        }
        Ok(())
    }
}
fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .build()
        .unwrap()
}
fn vector(id: u64) -> Vec<f32> {
    let mut state = id + 91;
    let mut values: Vec<f32> = (0..32)
        .map(|_| {
            state = state.wrapping_mul(6364136223846793005).wrapping_add(1);
            (state >> 40) as f32 / 8388608.0 - 1.0
        })
        .collect();
    let norm = values.iter().map(|v| v * v).sum::<f32>().sqrt();
    values.iter_mut().for_each(|v| *v /= norm);
    values
}

#[test]
fn opening_reads_one_root_not_the_corpus() {
    let store = Store::new(32);
    for id in 1..=10_000 {
        store.create(id, &vector(id)).unwrap();
    }
    let _index = Index::open(store.clone(), 32).unwrap();
    assert_eq!(store.reads.load(Ordering::Relaxed), 1);
}

#[test]
fn inserts_and_reopen_use_host_vectors_and_edges() {
    let runtime = runtime();
    let store = Store::new(32);
    let index = Index::open(store.clone(), 32).unwrap();
    for id in 1..=256 {
        store
            .transaction(|| runtime.block_on(index.insert(id, &vector(id))))
            .unwrap();
    }
    drop(index);
    let index = Index::open(store.clone(), 32).unwrap();
    for id in [1, 18, 125, 256] {
        let hits = runtime.block_on(index.search(&vector(id), 8, 128)).unwrap();
        assert_eq!(hits[0].0, id);
        assert!(hits[0].1.abs() < 1e-5);
        assert!(hits.windows(2).all(|rows| rows[0].1 <= rows[1].1));
        assert!(hits.iter().all(|row| row.0 != ROOT));
    }
}

#[test]
fn unsigned_64_bit_ids_survive_search() {
    let runtime = runtime();
    let store = Store::new(32);
    let index = Index::open(store.clone(), 32).unwrap();
    let id = (1u64 << 40) + 7;
    store
        .transaction(|| runtime.block_on(index.insert(id, &vector(id))))
        .unwrap();
    assert_eq!(
        runtime.block_on(index.search(&vector(id), 1, 8)).unwrap()[0].0,
        id
    );
}

#[test]
fn missing_or_malformed_nodes_fail_instead_of_silent_empty_results() {
    let runtime = runtime();
    let store = Store::new(32);
    let index = Index::open(store.clone(), 32).unwrap();
    store.neighbors(ROOT, &[123]).unwrap();
    assert!(runtime.block_on(index.search(&vector(1), 8, 32)).is_err());
    store.create(123, &[f32::NAN; 32]).unwrap();
    assert!(runtime.block_on(index.search(&vector(1), 8, 32)).is_err());
    store.neighbors(ROOT, &[123, 123]).unwrap();
    assert!(runtime.block_on(index.search(&vector(1), 8, 32)).is_err());
}

#[test]
fn duplicate_and_root_inserts_do_not_overwrite_existing_nodes() {
    let runtime = runtime();
    let store = Store::new(32);
    let index = Index::open(store.clone(), 32).unwrap();
    store
        .transaction(|| runtime.block_on(index.insert(1, &vector(1))))
        .unwrap();
    assert!(
        store
            .transaction(|| runtime.block_on(index.insert(1, &vector(2))))
            .is_err()
    );
    assert!(
        store
            .transaction(|| runtime.block_on(index.insert(ROOT, &vector(2))))
            .is_err()
    );
    assert_eq!(store.read(1).unwrap().vector.as_slice(), vector(1));
}

#[test]
fn cancelled_operations_propagate_and_host_transaction_rolls_back() {
    let runtime = runtime();
    let store = Store::new(32);
    let index = Index::open(store.clone(), 32).unwrap();
    store.cancelled.store(true, Ordering::SeqCst);
    assert!(
        store
            .transaction(|| runtime.block_on(index.insert(1, &vector(1))))
            .is_err()
    );
    assert!(runtime.block_on(index.search(&vector(1), 8, 32)).is_err());
    assert_eq!(store.nodes.lock().unwrap().len(), 1);
    store.cancelled.store(false, Ordering::SeqCst);
    store
        .transaction(|| runtime.block_on(index.insert(1, &vector(1))))
        .unwrap();
}

#[test]
fn validates_dimensions_parameters_and_query_before_traversal() {
    let runtime = runtime();
    let store = Store::new(32);
    assert!(Index::open(store.clone(), 0).is_err());
    assert!(Index::open(store.clone(), 33).is_err());
    let index = Index::open(store.clone(), 32).unwrap();
    let before = store.reads.load(Ordering::Relaxed);
    for (query, count, breadth) in [
        (vec![0.0; 31], 8, 32),
        (vec![f32::NAN; 32], 8, 32),
        (vector(1), 0, 32),
        (vector(1), 8, 8),
        (vector(1), 257, 512),
    ] {
        assert!(
            runtime
                .block_on(index.search(&query, count, breadth))
                .is_err()
        );
    }
    assert_eq!(store.reads.load(Ordering::Relaxed), before);
}

#[test]
fn a_zero_centroid_root_or_unnormalized_data_is_rejected() {
    let store = Store::new(32);
    let index = Index::open(store.clone(), 32).unwrap();
    assert!(
        store
            .transaction(|| runtime().block_on(index.insert(1, &[1.0; 32])))
            .is_err()
    );
    assert_eq!(store.nodes.lock().unwrap().len(), 1);
    store
        .nodes
        .lock()
        .unwrap()
        .get_mut(&ROOT)
        .unwrap()
        .vector
        .fill(0.0);
    assert!(Index::open(store, 32).is_err());
}

#[test]
fn held_out_queries_match_exact_top_eight_after_reopen() {
    let runtime = runtime();
    let store = Store::new(32);
    let index = Index::open(store.clone(), 32).unwrap();
    let corpus: Vec<_> = (1..=256).map(|id| (id, vector(id))).collect();
    for (id, value) in &corpus {
        store
            .transaction(|| runtime.block_on(index.insert(*id, value)))
            .unwrap();
    }
    drop(index);
    let index = Index::open(store, 32).unwrap();
    let mut matched = 0;
    let mut minimum = 8;
    for id in 10_001..=10_032 {
        let query = vector(id);
        let mut exact: Vec<_> = corpus
            .iter()
            .map(|(id, value)| {
                let distance: f64 = query
                    .iter()
                    .zip(value)
                    .map(|(a, b)| (f64::from(*a) - f64::from(*b)).powi(2))
                    .sum();
                (*id, distance)
            })
            .collect();
        exact.sort_by(|a, b| a.1.total_cmp(&b.1).then(a.0.cmp(&b.0)));
        let hits = runtime.block_on(index.search(&query, 8, 128)).unwrap();
        assert_eq!(hits.len(), 8);
        let unique: std::collections::BTreeSet<_> = hits.iter().map(|hit| hit.0).collect();
        assert_eq!(unique.len(), 8);
        assert!(!unique.contains(&ROOT));
        let count = exact[..8]
            .iter()
            .filter(|row| unique.contains(&row.0))
            .count();
        minimum = minimum.min(count);
        matched += count;
    }
    // Synthetic graph-quality gate, not evidence for real embedding recall.
    println!(
        "held_out_recall_at_8={matched}/256 minimum_per_query={minimum}/8 queries=32 corpus=256 breadth=128"
    );
    assert!(minimum >= 6, "worst held-out recall@8: {minimum}/8");
    assert!(matched >= 244, "aggregate held-out recall@8: {matched}/256");
}

#[test]
fn host_transaction_rolls_back_partial_neighbor_updates_and_can_retry() {
    let runtime = runtime();
    let store = Store::new(32);
    let index = Index::open(store.clone(), 32).unwrap();
    for id in 1..=16 {
        store
            .transaction(|| runtime.block_on(index.insert(id, &vector(id))))
            .unwrap();
    }
    let before = store.nodes.lock().unwrap().clone();
    store.fail_next_neighbor_write.store(true, Ordering::SeqCst);
    let error = store
        .transaction(|| runtime.block_on(index.insert(17, &vector(17))))
        .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("injected failure after neighbor mutation")
    );
    assert_eq!(store.failed_writes.load(Ordering::Relaxed), 1);
    let after = store.nodes.lock().unwrap();
    assert_eq!(before.len(), after.len());
    for (id, node) in &before {
        assert_eq!(node.vector.as_slice(), after[id].vector.as_slice());
        assert_eq!(node.neighbors.as_slice(), after[id].neighbors.as_slice());
    }
    drop(after);
    store
        .transaction(|| runtime.block_on(index.insert(17, &vector(17))))
        .unwrap();
    assert_eq!(
        runtime.block_on(index.search(&vector(17), 8, 128)).unwrap()[0].0,
        17
    );
}
