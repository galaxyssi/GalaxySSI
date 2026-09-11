#![cfg(feature = "sqlite-store")]
use galaxyssi_memory_native::{
    Index,
    sqlite_store::{SqliteIndexStore, StoreConfig},
    store::{NodeStore, ROOT},
};
use rusqlite::{Connection, params};
use std::{
    fs,
    path::PathBuf,
    process::Command,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
};
use zeroize::Zeroizing;

#[path = "sqlite_store/cache.rs"]
mod cache;
#[path = "sqlite_store/growth.rs"]
mod growth;
#[path = "sqlite_store/replay.rs"]
mod replay;

const KEY: [u8; 32] = [0x31; 32]; // Public fixture key, never an App/Keystore key.
const IDENTITY: [u8; 32] = [0x52; 32];
fn config() -> StoreConfig {
    StoreConfig {
        dimensions: 32,
        shards: 4,
        cache_bytes: 2 * 1024 * 1024,
    }
}
fn cancelled() -> Arc<AtomicBool> {
    Arc::new(AtomicBool::new(false))
}
fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .build()
        .unwrap()
}
fn vector(id: u64) -> Vec<f32> {
    let mut state = id.wrapping_add(91);
    let mut values: Vec<_> = (0..32)
        .map(|_| {
            state = state.wrapping_mul(6364136223846793005).wrapping_add(1);
            (state >> 40) as f32 / 8388608.0 - 1.0
        })
        .collect();
    let norm = values.iter().map(|v| v * v).sum::<f32>().sqrt();
    values.iter_mut().for_each(|v| *v /= norm);
    values
}
struct Fixture {
    path: PathBuf,
    parent: PathBuf,
}
impl Fixture {
    fn new() -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(1);
        let parent = fs::canonicalize(std::env::temp_dir()).unwrap();
        let sequence = NEXT.fetch_add(1, Ordering::Relaxed);
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = parent.join(format!(
            "galaxyssi-native-shards-test-{}-{now}-{sequence}",
            std::process::id()
        ));
        assert!(!path.exists());
        Self { path, parent }
    }
    fn create(&self) -> Arc<SqliteIndexStore> {
        SqliteIndexStore::create(
            &self.path,
            Zeroizing::new(KEY),
            IDENTITY,
            config(),
            &vector(0),
        )
        .unwrap()
    }
    fn open(&self) -> Arc<SqliteIndexStore> {
        SqliteIndexStore::open(&self.path, Zeroizing::new(KEY), IDENTITY, config()).unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        if !self.path.exists() {
            return;
        }
        let resolved = fs::canonicalize(&self.path).unwrap();
        assert_eq!(resolved.parent().unwrap(), self.parent);
        assert!(
            resolved
                .file_name()
                .unwrap()
                .to_str()
                .unwrap()
                .starts_with("galaxyssi-native-shards-test-")
        );
        fs::remove_dir_all(resolved).unwrap();
    }
}

#[test]
fn encrypted_graph_round_trip_uses_physical_shards_and_bounded_cache() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let rt = runtime();
    for id in 1..=64 {
        let session = store.begin(true, cancelled()).unwrap();
        let index = Index::open(session.clone(), 32).unwrap();
        rt.block_on(index.insert(id, &vector(id))).unwrap();
        session.commit().unwrap();
    }
    store.close().unwrap();
    drop(store);
    let reopened = fixture.open();
    let session = reopened.begin(false, cancelled()).unwrap();
    assert_eq!(session.node_count().unwrap(), 65);
    assert_eq!(session.generation().unwrap(), 65);
    let index = Index::open(session.clone(), 32).unwrap();
    for id in [1, 17, 32, 64] {
        assert_eq!(
            rt.block_on(index.search(&vector(id), 8, 128)).unwrap()[0].0,
            id
        );
    }
    session.commit().unwrap();
    reopened.close().unwrap();
    let clear: Vec<_> = vector(32).iter().flat_map(|v| v.to_le_bytes()).collect();
    for shard in 0..4 {
        let path = fixture.path.join(format!("nodes-{shard:02x}.sqlite"));
        assert!(path.exists());
        let bytes = fs::read(path).unwrap();
        assert_eq!(u16::from_be_bytes(bytes[16..18].try_into().unwrap()), 16384);
        assert!(!bytes.windows(clear.len()).any(|window| window == clear));
    }
}

#[test]
fn failed_insert_rolls_back_nodes_edges_and_metadata_across_shards() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let session = store.begin(true, cancelled()).unwrap();
    for id in 1..=8 {
        session.create(id, &vector(id)).unwrap();
    }
    session.neighbors(ROOT, &[1, 2, 3, 4, 5, 6, 7, 8]).unwrap();
    assert!(session.create(1, &vector(99)).is_err());
    assert!(session.commit().is_err());
    store.close().unwrap();
    let reopened = fixture.open();
    let session = reopened.begin(false, cancelled()).unwrap();
    assert_eq!(session.node_count().unwrap(), 1);
    assert_eq!(session.generation().unwrap(), 1);
    assert!(session.read(ROOT).unwrap().neighbors.is_empty());
    session.commit().unwrap();
    let session = reopened.begin(true, cancelled()).unwrap();
    for id in 1..=8 {
        session.create(id, &vector(id)).unwrap();
    }
    session.commit().unwrap();
    reopened.close().unwrap();
}

#[test]
fn dropped_and_cancelled_sessions_do_not_publish_or_invalidate_new_owners() {
    let fixture = Fixture::new();
    let store = fixture.create();
    {
        let session = store.begin(true, cancelled()).unwrap();
        session.create(77, &vector(77)).unwrap();
    }
    let cancellation = cancelled();
    let session = store.begin(true, cancellation.clone()).unwrap();
    session.create(77, &vector(77)).unwrap();
    cancellation.store(true, Ordering::Release);
    assert!(session.commit().is_err());
    let next = store.begin(true, cancelled()).unwrap();
    assert!(session.read(ROOT).is_err());
    assert!(session.commit().is_err());
    next.create(77, &vector(77)).unwrap();
    next.commit().unwrap();
    let read = store.begin(false, cancelled()).unwrap();
    assert_eq!(read.node_count().unwrap(), 2);
    assert_eq!(read.generation().unwrap(), 2);
    read.commit().unwrap();
    store.close().unwrap();
}

#[test]
fn read_only_session_cannot_mutate_and_concurrent_lease_is_rejected() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let session = store.begin(false, cancelled()).unwrap();
    assert!(store.begin(true, cancelled()).is_err());
    assert!(store.close().is_err());
    assert!(session.create(1, &vector(1)).is_err());
    assert!(session.commit().is_err());
    let retry = store.begin(false, cancelled()).unwrap();
    assert_eq!(retry.node_count().unwrap(), 1);
    retry.commit().unwrap();
    store.close().unwrap();
}

#[test]
fn wrong_key_identity_dimensions_or_missing_shard_never_create_empty_memory() {
    let fixture = Fixture::new();
    let store = fixture.create();
    store.close().unwrap();
    for (key, identity) in [([0x30; 32], IDENTITY), (KEY, [0x53; 32])] {
        let result = SqliteIndexStore::open(&fixture.path, Zeroizing::new(key), identity, config());
        assert!(
            result
                .err()
                .unwrap()
                .to_string()
                .contains("authentication failed")
        );
    }
    let mut wrong = config();
    wrong.dimensions = 16;
    assert!(SqliteIndexStore::open(&fixture.path, Zeroizing::new(KEY), IDENTITY, wrong).is_err());
    assert!(
        SqliteIndexStore::create(
            &fixture.path,
            Zeroizing::new(KEY),
            IDENTITY,
            config(),
            &vector(0)
        )
        .is_err()
    );
    let missing = fixture.path.join("nodes-02.sqlite");
    let retained = fixture.path.join("retained-ciphertext");
    fs::rename(&missing, &retained).unwrap();
    assert!(
        SqliteIndexStore::open(&fixture.path, Zeroizing::new(KEY), IDENTITY, config()).is_err()
    );
    assert!(!missing.exists());
    fs::rename(retained, missing).unwrap();
    fixture.open().close().unwrap();
}

#[test]
fn modified_ciphertext_or_revision_is_reported_as_authentication_failure() {
    for change_revision in [false, true] {
        let fixture = Fixture::new();
        let store = fixture.create();
        let session = store.begin(true, cancelled()).unwrap();
        session.create(42, &vector(42)).unwrap();
        session.commit().unwrap();
        store.close().unwrap();
        let shard = store.shard_for(42);
        let connection =
            Connection::open(fixture.path.join(format!("nodes-{shard:02x}.sqlite"))).unwrap();
        if change_revision {
            connection
                .execute(
                    "UPDATE nodes SET revision=1 WHERE id=?",
                    [42u64.to_le_bytes().as_slice()],
                )
                .unwrap();
        } else {
            let mut blob: Vec<u8> = connection
                .query_row(
                    "SELECT ciphertext FROM nodes WHERE id=?",
                    [42u64.to_le_bytes().as_slice()],
                    |row| row.get(0),
                )
                .unwrap();
            blob[20] ^= 1;
            connection
                .execute(
                    "UPDATE nodes SET ciphertext=? WHERE id=?",
                    params![blob, 42u64.to_le_bytes().as_slice()],
                )
                .unwrap();
        }
        drop(connection);
        let reopened = fixture.open();
        let session = reopened.begin(false, cancelled()).unwrap();
        assert!(
            session
                .read(42)
                .err()
                .unwrap()
                .to_string()
                .contains("authentication failed")
        );
        assert!(session.commit().is_err());
        reopened.close().unwrap();
    }
}

#[test]
fn a_reader_snapshot_blocks_cross_connection_commit_and_writer_can_retry() {
    let fixture = Fixture::new();
    let first = fixture.create();
    let second = fixture.open();
    let reader = first.begin(false, cancelled()).unwrap();
    assert_eq!(reader.node_count().unwrap(), 1);
    let writer = second.begin(true, cancelled()).unwrap();
    writer.create(2, &vector(2)).unwrap();
    assert!(writer.commit().is_err());
    assert_eq!(reader.node_count().unwrap(), 1);
    reader.commit().unwrap();
    let writer = second.begin(true, cancelled()).unwrap();
    writer.create(2, &vector(2)).unwrap();
    writer.commit().unwrap();
    let reader = first.begin(false, cancelled()).unwrap();
    assert_eq!(reader.node_count().unwrap(), 2);
    assert_eq!(reader.read(2).unwrap().vector.as_slice(), vector(2));
    reader.commit().unwrap();
    first.close().unwrap();
    second.close().unwrap();
}

#[test]
fn topology_and_cache_targets_do_not_change_node_identity() {
    let fixture = Fixture::new();
    let mut cfg = config();
    cfg.shards = 64;
    let store = SqliteIndexStore::create(
        &fixture.path,
        Zeroizing::new(KEY),
        IDENTITY,
        cfg,
        &vector(0),
    )
    .unwrap();
    let session = store.begin(true, cancelled()).unwrap();
    for id in [1, (1u64 << 40) + 9, u64::MAX] {
        session.create(id, &vector(id)).unwrap();
    }
    session.commit().unwrap();
    store.close().unwrap();
    cfg.cache_bytes *= 2;
    let reopened =
        SqliteIndexStore::open(&fixture.path, Zeroizing::new(KEY), IDENTITY, cfg).unwrap();
    let session = reopened.begin(false, cancelled()).unwrap();
    assert_eq!(session.node_count().unwrap(), 4);
    for id in [1, (1u64 << 40) + 9, u64::MAX] {
        assert_eq!(session.read(id).unwrap().vector.as_slice(), vector(id));
    }
    session.commit().unwrap();
    reopened.close().unwrap();
}

#[test]
fn uncommitted_process_exit_rolls_back_all_shards() {
    process_exit(false);
}
#[test]
fn committed_process_exit_preserves_all_shards() {
    process_exit(true);
}
fn process_exit(committed: bool) {
    let fixture = Fixture::new();
    fixture.create().close().unwrap();
    let output = Command::new(std::env::current_exe().unwrap())
        .args(["--ignored", "--exact", "crash_child", "--nocapture"])
        .env("GALAXYSSI_NATIVE_CRASH_ROOT", &fixture.path)
        .env(
            "GALAXYSSI_NATIVE_CRASH_COMMIT",
            if committed { "1" } else { "0" },
        )
        .output()
        .unwrap();
    assert_eq!(
        output.status.code(),
        Some(73),
        "{} {}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(String::from_utf8_lossy(&output.stdout).contains("staged=1024"));
    if !committed {
        let journals = fs::read_dir(&fixture.path)
            .unwrap()
            .filter_map(Result::ok)
            .filter(|entry| {
                entry.file_name().to_string_lossy().ends_with("-journal")
                    && entry.metadata().unwrap().len() > 0
            })
            .count();
        assert!(
            journals >= 2,
            "No multi-shard rollback journals survived the abrupt exit"
        );
    }
    let store = fixture.open();
    let session = store.begin(false, cancelled()).unwrap();
    assert_eq!(
        session.node_count().unwrap(),
        if committed { 1025 } else { 1 }
    );
    assert_eq!(
        session
            .record(b"crash-checkpoint")
            .unwrap()
            .as_deref()
            .map(|v| v.as_slice()),
        if committed {
            Some(b"staged=1024".as_slice())
        } else {
            None
        }
    );
    assert_eq!(session.generation().unwrap(), if committed { 2 } else { 1 });
    assert_eq!(
        session.read(ROOT).unwrap().neighbors.as_slice(),
        if committed { &[1, 2][..] } else { &[][..] }
    );
    if committed {
        for id in 1..=1024 {
            assert_eq!(session.read(id).unwrap().vector.as_slice(), vector(id));
        }
    }
    session.commit().unwrap();
    store.close().unwrap();
    let physical_count: i64 = (0..config().shards)
        .map(|shard| {
            let connection =
                Connection::open(fixture.path.join(format!("nodes-{shard:02x}.sqlite"))).unwrap();
            connection
                .query_row("SELECT count(*) FROM nodes", [], |row| row.get::<_, i64>(0))
                .unwrap()
        })
        .sum();
    assert_eq!(physical_count, if committed { 1025 } else { 1 });
    println!(
        "process_exit committed={committed} physical_nodes={physical_count} sqlite={}",
        rusqlite::version()
    );
}

#[test]
#[ignore = "Spawned by process-exit tests with an isolated fixture"]
fn crash_child() {
    let root = PathBuf::from(std::env::var_os("GALAXYSSI_NATIVE_CRASH_ROOT").unwrap());
    assert!(
        root.file_name()
            .unwrap()
            .to_str()
            .unwrap()
            .starts_with("galaxyssi-native-shards-test-")
    );
    assert_eq!(
        fs::canonicalize(root.parent().unwrap()).unwrap(),
        fs::canonicalize(std::env::temp_dir()).unwrap()
    );
    if std::env::var("GALAXYSSI_NATIVE_REPLAY_RESUME").as_deref() == Ok("1") {
        replay::crash_replay(&root);
    }
    let mut cfg = config();
    cfg.cache_bytes = (cfg.shards + 1) * 16 * 1024;
    let store = SqliteIndexStore::open(&root, Zeroizing::new(KEY), IDENTITY, cfg).unwrap();
    let session = store.begin(true, cancelled()).unwrap();
    for id in 1..=1024 {
        session.create(id, &vector(id)).unwrap();
    }
    session.neighbors(ROOT, &[1, 2]).unwrap();
    session
        .put_record(b"crash-checkpoint", b"staged=1024")
        .unwrap();
    if std::env::var("GALAXYSSI_NATIVE_CRASH_COMMIT").unwrap() == "1" {
        session.commit().unwrap();
    }
    println!("staged=1024");
    // Exit without Rust destructors or an explicit SQLite close/rollback.
    std::process::exit(73);
}
