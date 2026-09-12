use super::*;
use aes_gcm::{
    Aes256Gcm, KeyInit, Nonce,
    aead::{Aead, AeadCore, OsRng, Payload},
};

pub(super) fn attached(fixture: &Fixture) -> Connection {
    let connection = Connection::open(fixture.path.join("catalog.sqlite")).unwrap();
    for shard in 0..config().shards {
        connection
            .execute(
                &format!("ATTACH DATABASE ? AS s{shard}"),
                [fixture
                    .path
                    .join(format!("nodes-{shard:02x}.sqlite"))
                    .to_str()
                    .unwrap()],
            )
            .unwrap();
    }
    connection
}

pub(super) fn location(connection: &Connection, key: &[u8]) -> String {
    (0..config().shards)
        .map(|s| format!("s{s}"))
        .find(|schema| {
            connection
                .query_row(
                    &format!("SELECT EXISTS(SELECT 1 FROM {schema}.index_records WHERE key=?)"),
                    [key],
                    |r| r.get::<_, bool>(0),
                )
                .unwrap()
        })
        .expect("Fixture record must exist in exactly one shard")
}

fn remaining(fixture: &Fixture) -> i64 {
    attached(fixture)
        .query_row("SELECT count(*) FROM main.index_records", [], |r| r.get(0))
        .unwrap()
}

// Reproduce the previous release's on-disk layout with the public fixture key.
// Production code has no downgrade/import hook and cannot access this helper.
fn legacy(fixture: &Fixture, count: usize) {
    let store = fixture.create();
    let writer = store.begin(true, cancelled()).unwrap();
    for n in 0..count {
        writer
            .put_record(&(n as u64).to_be_bytes(), &vec![n as u8; 1024])
            .unwrap();
    }
    writer.commit().unwrap();
    store.close().unwrap();
    downgrade(fixture);
}

pub(super) fn downgrade(fixture: &Fixture) {
    let connection = attached(fixture);
    connection.execute_batch("BEGIN IMMEDIATE").unwrap();
    for shard in 0..config().shards {
        connection.execute_batch(&format!("INSERT INTO main.index_records SELECT * FROM s{shard}.index_records; DROP TABLE s{shard}.index_records")).unwrap();
    }
    let envelope: Vec<u8> = connection
        .query_row("SELECT sealed FROM index_state WHERE id=1", [], |r| {
            r.get(0)
        })
        .unwrap();
    let mut aad = b"galaxyssi:disk-memory:v1\0".to_vec();
    aad.extend_from_slice(&IDENTITY);
    aad.extend_from_slice(b"metadata");
    let cipher = Aes256Gcm::new_from_slice(&KEY).unwrap();
    let mut bytes = cipher
        .decrypt(
            Nonce::from_slice(&envelope[..12]),
            Payload {
                msg: &envelope[12..],
                aad: &aad,
            },
        )
        .unwrap();
    assert_eq!(&bytes[..8], b"GSAN0002");
    bytes.truncate(48);
    bytes[..8].copy_from_slice(b"GSAN0001");
    let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
    let mut sealed = nonce.to_vec();
    sealed.extend(
        cipher
            .encrypt(
                &nonce,
                Payload {
                    msg: &bytes,
                    aad: &aad,
                },
            )
            .unwrap(),
    );
    connection
        .execute("UPDATE index_state SET sealed=? WHERE id=1", [sealed])
        .unwrap();
    connection.execute_batch("COMMIT").unwrap();
}

#[test]
fn new_records_use_all_shards_and_indexed_point_lookups() {
    let fixture = Fixture::new();
    let store = fixture.create();
    let writer = store.begin(true, cancelled()).unwrap();
    assert!(writer.records_partitioned().unwrap());
    for n in 0..1024u64 {
        writer
            .put_record(&n.to_be_bytes(), b"private-source")
            .unwrap();
    }
    writer.commit().unwrap();
    assert_eq!(remaining(&fixture), 0);
    let connection = attached(&fixture);
    for shard in 0..4 {
        let count: i64 = connection
            .query_row(
                &format!("SELECT count(*) FROM s{shard}.index_records"),
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(count, 256);
        let plan: String = connection
            .query_row(
                &format!(
                    "EXPLAIN QUERY PLAN SELECT ciphertext FROM s{shard}.index_records WHERE key=?"
                ),
                [&0u64.to_be_bytes()],
                |r| r.get(3),
            )
            .unwrap();
        assert!(
            plan.contains("SEARCH") && plan.contains("PRIMARY KEY"),
            "{plan}"
        );
    }
    store.close().unwrap();
}

#[test]
fn legacy_migration_is_bounded_resumable_and_preserves_every_record() {
    let fixture = Fixture::new();
    legacy(&fixture, 513);
    let catalog_before = fs::read(fixture.path.join("catalog.sqlite")).unwrap();
    let store = fixture.open();
    let reader = store.begin(false, cancelled()).unwrap();
    assert!(!reader.records_partitioned().unwrap());
    assert_eq!(
        reader.record(&512u64.to_be_bytes()).unwrap().unwrap().len(),
        1024
    );
    reader.commit().unwrap();
    store.close().unwrap();
    assert_eq!(
        fs::read(fixture.path.join("catalog.sqlite")).unwrap(),
        catalog_before,
        "Opening must not migrate"
    );
    for batch in 0..9 {
        let store = fixture.open();
        let writer = store.begin(true, cancelled()).unwrap();
        assert_eq!(writer.migrate_records(64).unwrap(), batch == 8);
        writer.commit().unwrap();
        assert_eq!(remaining(&fixture), (513 - (batch + 1) * 64).max(0));
        let reader = store.begin(false, cancelled()).unwrap();
        for n in 0..513u64 {
            assert_eq!(
                reader.record(&n.to_be_bytes()).unwrap().unwrap().as_slice(),
                &vec![n as u8; 1024]
            );
        }
        assert_eq!(reader.node_count().unwrap(), 1);
        reader.commit().unwrap();
        store.close().unwrap();
    }
}

#[test]
fn legacy_and_partitioned_updates_remain_atomic_during_migration() {
    let fixture = Fixture::new();
    legacy(&fixture, 80);
    let store = fixture.open();
    let writer = store.begin(true, cancelled()).unwrap();
    assert!(!writer.migrate_records(1).unwrap());
    writer
        .put_record(&79u64.to_be_bytes(), b"updated-legacy-source")
        .unwrap();
    writer
        .put_record(&0u64.to_be_bytes(), b"updated-migrated-source")
        .unwrap();
    writer.put_record(b"new-source", b"new-value").unwrap();
    writer.commit().unwrap();
    assert_eq!(remaining(&fixture), 78);
    let writer = store.begin(true, cancelled()).unwrap();
    writer.migrate_records(64).unwrap();
    writer
        .put_record(&79u64.to_be_bytes(), b"must-rollback")
        .unwrap();
    writer.rollback().unwrap();
    assert_eq!(remaining(&fixture), 78);
    let reader = store.begin(false, cancelled()).unwrap();
    assert_eq!(
        &**reader
            .record(&79u64.to_be_bytes())
            .unwrap()
            .as_ref()
            .unwrap(),
        b"updated-legacy-source"
    );
    reader.commit().unwrap();
    store.close().unwrap();
}

#[test]
fn corrupt_legacy_record_rolls_back_schema_and_all_prior_rows_in_page() {
    let fixture = Fixture::new();
    legacy(&fixture, 80);
    let connection = attached(&fixture);
    connection
        .execute(
            "UPDATE main.index_records SET ciphertext=zeroblob(length(ciphertext)) WHERE key=?",
            [&63u64.to_be_bytes()],
        )
        .unwrap();
    let store = fixture.open();
    let writer = store.begin(true, cancelled()).unwrap();
    assert!(writer.migrate_records(64).is_err());
    assert!(writer.commit().is_err());
    assert_eq!(remaining(&fixture), 80);
    assert!(
        connection
            .prepare("SELECT * FROM s0.index_records")
            .is_err()
    );
    store.close().unwrap();
}

#[test]
fn duplicate_and_missing_partition_tables_are_not_treated_as_empty_memory() {
    let fixture = Fixture::new();
    legacy(&fixture, 80);
    let store = fixture.open();
    let writer = store.begin(true, cancelled()).unwrap();
    writer.migrate_records(1).unwrap();
    writer.commit().unwrap();
    let connection = attached(&fixture);
    let target = location(&connection, &0u64.to_be_bytes());
    connection
        .execute_batch(&format!(
            "INSERT INTO main.index_records SELECT * FROM {target}.index_records"
        ))
        .unwrap();
    let reader = store.begin(false, cancelled()).unwrap();
    assert!(reader.record(&0u64.to_be_bytes()).is_err());
    assert!(reader.commit().is_err());
    let writer = store.begin(true, cancelled()).unwrap();
    assert!(writer.migrate_records(64).is_err());
    assert!(writer.commit().is_err());
    store.close().unwrap();
    connection
        .execute_batch("DROP TABLE s3.index_records")
        .unwrap();
    assert!(
        SqliteIndexStore::open(&fixture.path, Zeroizing::new(KEY), IDENTITY, config()).is_err()
    );
}

#[test]
fn migration_validates_bounds_read_only_and_cancellation() {
    let fixture = Fixture::new();
    legacy(&fixture, 80);
    let store = fixture.open();
    for limit in [0, 257, usize::MAX] {
        let writer = store.begin(true, cancelled()).unwrap();
        assert!(writer.migrate_records(limit).is_err());
        assert!(writer.commit().is_err());
    }
    let reader = store.begin(false, cancelled()).unwrap();
    assert!(reader.migrate_records(1).is_err());
    assert!(reader.commit().is_err());
    let stop = cancelled();
    let writer = store.begin(true, stop.clone()).unwrap();
    writer.migrate_records(64).unwrap();
    stop.store(true, Ordering::Release);
    assert!(writer.commit().is_err());
    assert_eq!(remaining(&fixture), 80);
    store.close().unwrap();
}

#[test]
fn migration_survives_process_exit_before_and_after_commit() {
    for commit in [false, true] {
        let fixture = Fixture::new();
        legacy(&fixture, 513);
        let output = Command::new(std::env::current_exe().unwrap())
            .args(["--ignored", "--exact", "crash_child", "--nocapture"])
            .env("GALAXYSSI_NATIVE_CRASH_ROOT", &fixture.path)
            .env(
                "GALAXYSSI_NATIVE_MIGRATION_CRASH",
                if commit { "commit" } else { "rollback" },
            )
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(75), "{output:?}");
        let store = fixture.open();
        assert_eq!(remaining(&fixture), if commit { 449 } else { 513 });
        loop {
            let writer = store.begin(true, cancelled()).unwrap();
            let complete = writer.migrate_records(64).unwrap();
            writer.commit().unwrap();
            if complete {
                break;
            }
        }
        let reader = store.begin(false, cancelled()).unwrap();
        for n in 0..513u64 {
            assert_eq!(
                reader.record(&n.to_be_bytes()).unwrap().unwrap().as_slice(),
                &vec![n as u8; 1024]
            );
        }
        reader.commit().unwrap();
        store.close().unwrap();
    }
}

pub(super) fn crash(root: &std::path::Path, commit: bool) -> ! {
    let store = SqliteIndexStore::open(root, Zeroizing::new(KEY), IDENTITY, config()).unwrap();
    let writer = store.begin(true, cancelled()).unwrap();
    assert!(!writer.migrate_records(64).unwrap());
    if commit {
        writer.commit().unwrap();
    }
    std::process::exit(75)
}
