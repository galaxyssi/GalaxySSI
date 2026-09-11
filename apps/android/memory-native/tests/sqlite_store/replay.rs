use super::*;
use galaxyssi_memory_native::replay::{
    Chunk, ReplayIndex,
    format::{CURSOR_KEY, Checkpoint, Event},
};
const EPOCH: [u8; 16] = [0x61; 16];
fn event(sequence: u64, previous: u64, key: u8, revision: u8, chunks: u64) -> Event {
    Event {
        sequence,
        previous,
        key: [key; 32],
        revision: [revision; 32],
        chunks,
        removed: false,
    }
}
fn chunks(start: u64, end: u64, seed: u64) -> Vec<Chunk> {
    (start..end)
        .map(|ordinal| Chunk {
            ordinal,
            start: ordinal * 10,
            end: ordinal * 10 + 10,
            vector: Zeroizing::new(vector(seed + ordinal)),
        })
        .collect()
}
fn attach(store: Arc<SqliteIndexStore>, initialize: bool) -> ReplayIndex {
    ReplayIndex::attach(store, EPOCH, cancelled(), initialize).unwrap()
}

#[test]
fn replay_partial_pages_survive_reopen_and_retries_do_not_duplicate_nodes() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let index = attach(store.clone(), true);
    let rt = runtime();
    let e = event(7, 0, 1, 2, 5);
    index.begin_event(&e, false).unwrap();
    let pending = rt.block_on(index.append(&e, &chunks(0, 2, 1))).unwrap();
    assert_eq!(pending.sequence(), 0);
    assert_eq!(pending.pending.as_ref().unwrap().next, 2);
    assert!(
        rt.block_on(index.search(&vector(1), 8, 128))
            .unwrap()
            .is_empty()
    );
    assert_eq!(index.node_count().unwrap(), 3);
    store.close().unwrap();
    drop(index);
    drop(store);
    let store = fixture.open();
    let index = attach(store.clone(), false);
    assert_eq!(index.checkpoint().unwrap(), pending);
    rt.block_on(index.append(&e, &chunks(0, 2, 1))).unwrap();
    assert_eq!(index.node_count().unwrap(), 3);
    let complete = rt.block_on(index.append(&e, &chunks(2, 5, 1))).unwrap();
    assert!(complete.pending.is_none());
    assert_eq!(complete.sequence(), 7);
    assert_eq!(index.node_count().unwrap(), 6);
    rt.block_on(index.append(&e, &chunks(2, 5, 1))).unwrap();
    assert_eq!(index.node_count().unwrap(), 6);
    for ordinal in 0..5 {
        let hits = rt
            .block_on(index.search(&vector(1 + ordinal), 8, 128))
            .unwrap();
        assert_eq!(hits[0].source.ordinal, ordinal);
        assert_eq!(hits[0].source.key, e.key);
        assert_eq!(hits[0].source.revision, e.revision);
        assert!(hits[0].similarity > 0.999);
    }
    store.close().unwrap();
}

#[test]
fn replay_replacement_and_removal_filter_stale_sources_without_loading_the_corpus() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let index = attach(store.clone(), true);
    let rt = runtime();
    let mut previous = 0;
    for id in 1..=16 {
        let e = event(id * 3, previous, id as u8, 1, 1);
        index.begin_event(&e, false).unwrap();
        rt.block_on(index.append(&e, &chunks(0, 1, id))).unwrap();
        previous = e.sequence;
    }
    let replacement = event(60, previous, 1, 2, 1);
    index.begin_event(&replacement, false).unwrap();
    assert!(
        rt.block_on(index.search(&vector(1), 16, 128))
            .unwrap()
            .iter()
            .all(|hit| hit.source.key != [1; 32])
    );
    rt.block_on(index.append(&replacement, &chunks(0, 1, 99)))
        .unwrap();
    let hits = rt.block_on(index.search(&vector(99), 16, 128)).unwrap();
    assert_eq!(hits[0].source.revision, [2; 32]);
    assert_eq!(hits[0].source.key, [1; 32]);
    let mut removal = event(90, 60, 1, 2, 1);
    removal.removed = true;
    index.begin_event(&removal, false).unwrap();
    assert_eq!(index.node_count().unwrap(), 18);
    store.close().unwrap();
    drop(index);
    drop(store);
    let store = fixture.open();
    let index = attach(store.clone(), false);
    let hits = rt.block_on(index.search(&vector(99), 16, 128)).unwrap();
    assert_eq!(hits.len(), 15);
    assert!(hits.iter().all(|hit| hit.source.key != [1; 32]));
    store.close().unwrap();
}

#[test]
fn replay_readding_the_same_revision_does_not_resurrect_older_vectors() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let index = attach(store.clone(), true);
    let rt = runtime();
    let original = event(1, 0, 1, 2, 1);
    index.begin_event(&original, false).unwrap();
    rt.block_on(index.append(&original, &chunks(0, 1, 7)))
        .unwrap();
    let mut removal = event(2, 1, 1, 2, 1);
    removal.removed = true;
    index.begin_event(&removal, false).unwrap();
    let restored = event(3, 2, 1, 2, 1);
    index.begin_event(&restored, false).unwrap();
    rt.block_on(index.append(&restored, &chunks(0, 1, 7)))
        .unwrap();
    let hits = rt.block_on(index.search(&vector(7), 8, 128)).unwrap();
    assert_eq!(index.node_count().unwrap(), 3);
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].source.revision, original.revision);
    assert_eq!(hits[0].source.sequence, restored.sequence);
    store.close().unwrap();
}

#[test]
fn replay_provenance_failure_rolls_back_graph_and_cursor_in_the_same_transaction() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let index = attach(store.clone(), true);
    let rt = runtime();
    let e = event(1, 0, 1, 2, 2);
    let before = index.begin_event(&e, false).unwrap();
    let external = Connection::open(fixture.path.join("catalog.sqlite")).unwrap();
    external.execute_batch("CREATE TRIGGER reject_node_record BEFORE INSERT ON index_records \
        WHEN substr(NEW.key,1,1)=x'6e' BEGIN SELECT RAISE(ABORT,'synthetic provenance failure'); END").unwrap();
    assert!(rt.block_on(index.append(&e, &chunks(0, 2, 1))).is_err());
    assert_eq!(index.node_count().unwrap(), 1);
    assert_eq!(index.checkpoint().unwrap(), before);
    external
        .execute_batch("DROP TRIGGER reject_node_record")
        .unwrap();
    rt.block_on(index.append(&e, &chunks(0, 2, 1))).unwrap();
    assert_eq!(index.node_count().unwrap(), 3);
    assert_eq!(index.checkpoint().unwrap().sequence(), 1);
    store.close().unwrap();
}

#[test]
fn replay_rejects_gaps_foreign_epochs_and_changed_retries_but_can_skip_obsolete_work() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let index = attach(store.clone(), true);
    let rt = runtime();
    let e = event(10, 0, 1, 2, 3);
    index.begin_event(&e, false).unwrap();
    rt.block_on(index.append(&e, &chunks(0, 1, 1))).unwrap();
    assert!(index.begin_event(&event(11, 10, 2, 2, 1), false).is_err());
    assert!(rt.block_on(index.append(&e, &chunks(2, 3, 1))).is_err());
    assert!(rt.block_on(index.append(&e, &chunks(0, 2, 1))).is_err());
    index.begin_event(&e, true).unwrap();
    assert_eq!(index.checkpoint().unwrap().sequence(), 10);
    assert!(
        rt.block_on(index.search(&vector(1), 8, 128))
            .unwrap()
            .is_empty()
    );
    assert!(ReplayIndex::attach(store.clone(), [9; 16], cancelled(), false).is_err());
    assert!(index.begin_event(&event(10, 0, 1, 99, 3), false).is_err());
    assert!(index.begin_event(&event(20, 11, 1, 3, 1), false).is_err());
    let next = event(20, 10, 1, 3, 1);
    index.begin_event(&next, false).unwrap();
    rt.block_on(index.append(&next, &chunks(0, 1, 90))).unwrap();
    assert_eq!(
        rt.block_on(index.search(&vector(90), 8, 128)).unwrap()[0]
            .source
            .revision,
        [3; 32]
    );
    store.close().unwrap();
}

#[test]
fn encrypted_records_are_bounded_bound_to_their_key_and_poison_failed_transactions() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let writer = store.begin(true, cancelled()).unwrap();
    writer.put_record(b"a", b"synthetic-checkpoint").unwrap();
    writer.put_record(b"b", b"another-checkpoint").unwrap();
    writer.commit().unwrap();
    let writer = store.begin(true, cancelled()).unwrap();
    assert!(writer.put_record(b"c", &[1; 1025]).is_err());
    assert!(writer.put_record(b"c", b"must-not-commit").is_err());
    assert!(writer.commit().is_err());
    let reader = store.begin(false, cancelled()).unwrap();
    assert!(reader.record(b"c").unwrap().is_none());
    assert_eq!(
        reader.record(b"a").unwrap().unwrap().as_slice(),
        b"synthetic-checkpoint"
    );
    reader.commit().unwrap();
    let external = Connection::open(fixture.path.join("catalog.sqlite")).unwrap();
    external.execute_batch("UPDATE index_records SET ciphertext=(SELECT ciphertext FROM index_records WHERE key=x'61'),\
        revision=(SELECT revision FROM index_records WHERE key=x'61') WHERE key=x'62'").unwrap();
    let reader = store.begin(false, cancelled()).unwrap();
    assert!(reader.record(b"b").is_err());
    assert!(reader.commit().is_err());
    assert!(
        !fs::read(fixture.path.join("catalog.sqlite"))
            .unwrap()
            .windows(20)
            .any(|part| part == b"synthetic-checkpoint")
    );
    store.close().unwrap();
}

#[test]
fn replay_cancellation_and_corruption_cannot_return_partial_matches() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let stop = cancelled();
    let index = ReplayIndex::attach(store.clone(), EPOCH, stop.clone(), true).unwrap();
    let rt = runtime();
    let e = event(1, 0, 1, 2, 1);
    index.begin_event(&e, false).unwrap();
    stop.store(true, Ordering::Release);
    assert!(rt.block_on(index.append(&e, &chunks(0, 1, 1))).is_err());
    stop.store(false, Ordering::Release);
    assert_eq!(index.node_count().unwrap(), 1);
    rt.block_on(index.append(&e, &chunks(0, 1, 1))).unwrap();
    let external = Connection::open(fixture.path.join("catalog.sqlite")).unwrap();
    external.execute_batch("UPDATE index_records SET ciphertext=zeroblob(length(ciphertext)) WHERE substr(key,1,1)=x'6e'").unwrap();
    assert!(rt.block_on(index.search(&vector(1), 8, 128)).is_err());
    assert_eq!(index.checkpoint().unwrap().sequence(), 1);
    store.close().unwrap();
}

#[test]
fn replay_resumes_after_real_process_exit_without_reinserting_a_committed_page() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let index = attach(store.clone(), true);
    let e = event(7, 0, 1, 2, 3);
    index.begin_event(&e, false).unwrap();
    store.close().unwrap();
    drop(index);
    drop(store);
    let output = Command::new(std::env::current_exe().unwrap())
        .args(["--ignored", "--exact", "crash_child", "--nocapture"])
        .env("GALAXYSSI_NATIVE_CRASH_ROOT", &fixture.path)
        .env("GALAXYSSI_NATIVE_REPLAY_RESUME", "1")
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(74), "{:?}", output);
    let store = fixture.open();
    let index = attach(store.clone(), false);
    assert_eq!(index.checkpoint().unwrap().pending.unwrap().next, 2);
    assert_eq!(index.node_count().unwrap(), 3);
    let rt = runtime();
    rt.block_on(index.append(&e, &chunks(0, 2, 1))).unwrap();
    assert_eq!(index.node_count().unwrap(), 3);
    rt.block_on(index.append(&e, &chunks(2, 3, 1))).unwrap();
    assert_eq!(index.checkpoint().unwrap().sequence(), 7);
    assert_eq!(index.node_count().unwrap(), 4);
    assert_eq!(
        rt.block_on(index.search(&vector(3), 8, 128)).unwrap()[0]
            .source
            .ordinal,
        2
    );
    let session = store.begin(false, cancelled()).unwrap();
    let bytes = session.record(CURSOR_KEY).unwrap().unwrap();
    let checkpoint = Checkpoint::decode(&bytes).unwrap();
    for length in 0..bytes.len() {
        assert!(Checkpoint::decode(&bytes[..length]).is_err());
    }
    assert_eq!(checkpoint.sequence(), 7);
    session.commit().unwrap();
    store.close().unwrap();
}

pub(super) fn crash_replay(root: &std::path::Path) -> ! {
    let store = SqliteIndexStore::open(root, Zeroizing::new(KEY), IDENTITY, config()).unwrap();
    let index = attach(store, false);
    runtime()
        .block_on(index.append(&event(7, 0, 1, 2, 3), &chunks(0, 2, 1)))
        .unwrap();
    println!("replay_staged=2");
    std::process::exit(74);
}
