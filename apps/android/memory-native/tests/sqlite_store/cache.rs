use super::*;

#[test]
fn transaction_cache_reuses_authenticated_nodes_and_updates_neighbors() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let write = store.begin(true, cancelled()).unwrap();
    write.create(1, &vector(1)).unwrap();
    write.create(2, &vector(2)).unwrap();
    write.commit().unwrap();
    let write = store.begin(true, cancelled()).unwrap();
    assert_eq!(write.node_cache_stats().unwrap().hits, 0);
    assert_eq!(write.read(1).unwrap().vector.as_slice(), vector(1));
    assert_eq!(write.node_cache_stats().unwrap().misses, 1);
    assert!(write.read(1).unwrap().neighbors.is_empty());
    assert_eq!(write.node_cache_stats().unwrap().hits, 1);
    write.neighbors(1, &[2]).unwrap();
    assert_eq!(*write.read(1).unwrap().neighbors, vec![2]);
    assert_eq!(write.node_cache_stats().unwrap().misses, 1);
    write.commit().unwrap();
    let read = store.begin(false, cancelled()).unwrap();
    assert_eq!(read.node_cache_stats().unwrap().occupied, 0);
    assert_eq!(*read.read(1).unwrap().neighbors, vec![2]);
    assert_eq!(read.node_cache_stats().unwrap().misses, 1);
    read.commit().unwrap();
}

#[test]
fn transaction_cache_does_not_outlive_rollback_cancellation_or_commit() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let write = store.begin(true, cancelled()).unwrap();
    write.create(1, &vector(1)).unwrap();
    write.commit().unwrap();
    let write = store.begin(true, cancelled()).unwrap();
    write.neighbors(ROOT, &[1]).unwrap();
    assert_eq!(*write.read(ROOT).unwrap().neighbors, vec![1]);
    write.rollback().unwrap();
    let cancel = cancelled();
    let read = store.begin(false, cancel.clone()).unwrap();
    assert!(read.read(ROOT).unwrap().neighbors.is_empty());
    read.read(ROOT).unwrap();
    assert_eq!(read.node_cache_stats().unwrap().hits, 1);
    cancel.store(true, Ordering::Release);
    assert!(read.read(ROOT).is_err());
    assert!(read.commit().is_err());
    let next = store.begin(false, cancelled()).unwrap();
    assert_eq!(next.node_cache_stats().unwrap().occupied, 0);
    assert!(read.read(ROOT).is_err());
    assert!(next.read(ROOT).unwrap().neighbors.is_empty());
    next.commit().unwrap();
    assert!(next.read(ROOT).is_err());
}

#[test]
fn node_cache_shares_the_fixed_budget_and_eviction_retains_correctness() {
    let fixture = Fixture::new();
    let cfg = StoreConfig {
        cache_bytes: 128 * 1024,
        ..config()
    };
    let store = SqliteIndexStore::create(
        &fixture.path,
        Zeroizing::new(KEY),
        IDENTITY,
        cfg,
        &vector(0),
    )
    .unwrap();
    let write = store.begin(true, cancelled()).unwrap();
    for id in 1..=128 {
        write.create(id, &vector(id)).unwrap();
    }
    let stats = write.node_cache_stats().unwrap();
    assert!(stats.slots < 128 && stats.slots > 0);
    assert!(stats.occupied <= stats.slots);
    assert!(stats.reserved_bytes <= cfg.node_cache_bytes());
    for id in 1..=128 {
        assert_eq!(write.read(id).unwrap().vector.as_slice(), vector(id));
    }
    write.commit().unwrap();
    let read = store.begin(false, cancelled()).unwrap();
    for id in (1..=128).rev() {
        assert_eq!(read.read(id).unwrap().vector.as_slice(), vector(id));
    }
    read.commit().unwrap();
    let minimum = StoreConfig {
        cache_bytes: (cfg.shards + 1) * 16 * 1024,
        ..cfg
    };
    assert_eq!(minimum.node_cache_bytes(), 0);
    assert!(cfg.node_cache_bytes() <= 4 * 1024 * 1024);
    store.close().unwrap();
    let uncached =
        SqliteIndexStore::open(&fixture.path, Zeroizing::new(KEY), IDENTITY, minimum).unwrap();
    let read = uncached.begin(false, cancelled()).unwrap();
    read.read(1).unwrap();
    read.read(1).unwrap();
    let stats = read.node_cache_stats().unwrap();
    assert_eq!(stats.slots, 0);
    assert_eq!(stats.hits, 0);
    assert_eq!(stats.misses, 2);
    read.commit().unwrap();
}

#[test]
fn a_new_snapshot_reauthenticates_nodes_after_prior_cache_hits() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let write = store.begin(true, cancelled()).unwrap();
    write.create(1, &vector(1)).unwrap();
    write.read(1).unwrap();
    assert!(write.node_cache_stats().unwrap().hits > 0);
    write.commit().unwrap();
    let file = fixture
        .path
        .join(format!("nodes-{:02x}.sqlite", store.shard_for(1)));
    let connection = Connection::open(file).unwrap();
    connection
        .execute(
            "UPDATE nodes SET ciphertext=zeroblob(length(ciphertext)) WHERE id=?",
            [1u64.to_le_bytes().as_slice()],
        )
        .unwrap();
    drop(connection);
    let read = store.begin(false, cancelled()).unwrap();
    assert!(read.read(1).is_err());
    assert!(read.commit().is_err());
}
