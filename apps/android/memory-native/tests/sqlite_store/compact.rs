use super::*;
use aes_gcm::{
    Aes256Gcm, KeyInit, Nonce,
    aead::{Aead, Payload},
};
use std::time::Instant;

const DIMENSIONS: usize = 512;

fn vector(id: u64) -> Vec<f32> {
    let mut seed = id.wrapping_add(853);
    let mut values: Vec<_> = (0..DIMENSIONS)
        .map(|_| {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
            (seed >> 40) as f32 / 8388608.0 - 1.0
        })
        .collect();
    let norm = values
        .iter()
        .map(|v| f64::from(*v).powi(2))
        .sum::<f64>()
        .sqrt();
    values
        .iter_mut()
        .for_each(|v| *v = (f64::from(*v) / norm) as f32);
    values
}

pub(super) fn assert_reconstruction(actual: &[f32], expected: &[f32]) {
    assert_eq!(actual.len(), expected.len());
    let squared_error: f64 = actual
        .iter()
        .zip(expected)
        .map(|(a, b)| (f64::from(*a) - f64::from(*b)).powi(2))
        .sum();
    assert!(squared_error <= 0.0001, "squared_error={squared_error}");
    let norm: f64 = actual.iter().map(|v| f64::from(*v).powi(2)).sum();
    assert!((norm - 1.0).abs() < 0.001);
}

fn config() -> StoreConfig {
    StoreConfig {
        dimensions: DIMENSIONS,
        ..super::config()
    }
}

fn create(fixture: &Fixture) -> Arc<SqliteIndexStore> {
    SqliteIndexStore::create(
        &fixture.path,
        Zeroizing::new(KEY),
        IDENTITY,
        config(),
        &vector(0),
    )
    .unwrap()
}

fn aad(domain: &[u8]) -> Vec<u8> {
    let mut result = b"galaxyssi:disk-memory:v1\0".to_vec();
    result.extend_from_slice(&IDENTITY);
    result.extend_from_slice(domain);
    result
}

// Independent envelope reader/writer uses only public synthetic fixture keys.
// This verifies legacy compatibility without relying on the new codec to encode it.
fn node_frame(fixture: &Fixture, store: &SqliteIndexStore, id: u64) -> (Vec<u8>, Vec<u8>, i64) {
    let catalog = Connection::open(fixture.path.join("catalog.sqlite")).unwrap();
    let metadata: Vec<u8> = catalog
        .query_row("SELECT sealed FROM index_state WHERE id=1", [], |r| {
            r.get(0)
        })
        .unwrap();
    let cipher = Aes256Gcm::new_from_slice(&KEY).unwrap();
    let metadata = cipher
        .decrypt(
            Nonce::from_slice(&metadata[..12]),
            Payload {
                msg: &metadata[12..],
                aad: &aad(b"metadata"),
            },
        )
        .unwrap();
    let shard = Connection::open(
        fixture
            .path
            .join(format!("nodes-{:02x}.sqlite", store.shard_for(id))),
    )
    .unwrap();
    let (revision, frame): (i64, Vec<u8>) = shard
        .query_row(
            "SELECT revision,ciphertext FROM nodes WHERE id=?",
            [id.to_le_bytes().as_slice()],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    let mut binding = aad(b"node");
    binding.extend_from_slice(&metadata[32..48]);
    binding.extend_from_slice(&(DIMENSIONS as u32).to_le_bytes());
    binding.extend_from_slice(&(config().shards as u32).to_le_bytes());
    binding.extend_from_slice(&id.to_le_bytes());
    binding.extend_from_slice(&revision.to_le_bytes());
    let body = cipher
        .decrypt(
            Nonce::from_slice(&frame[..12]),
            Payload {
                msg: &frame[12..],
                aad: &binding,
            },
        )
        .unwrap();
    (body, binding, revision)
}

fn replace_frame(
    fixture: &Fixture,
    store: &SqliteIndexStore,
    id: u64,
    body: &[u8],
    binding: &[u8],
) {
    // A distinct nonce on each synthetic rewrite, including malformed-body cases.
    static NONCE: AtomicU64 = AtomicU64::new(1);
    let mut nonce = [0u8; 12];
    nonce[..8].copy_from_slice(&NONCE.fetch_add(1, Ordering::Relaxed).to_le_bytes());
    nonce[8..].copy_from_slice(b"test");
    let mut frame = nonce.to_vec();
    frame.extend_from_slice(
        &Aes256Gcm::new_from_slice(&KEY)
            .unwrap()
            .encrypt(
                Nonce::from_slice(&nonce),
                Payload {
                    msg: body,
                    aad: binding,
                },
            )
            .unwrap(),
    );
    let shard = Connection::open(
        fixture
            .path
            .join(format!("nodes-{:02x}.sqlite", store.shard_for(id))),
    )
    .unwrap();
    assert_eq!(
        shard
            .execute(
                "UPDATE nodes SET ciphertext=? WHERE id=?",
                params![frame, id.to_le_bytes().as_slice()]
            )
            .unwrap(),
        1
    );
}

#[test]
fn compact_nodes_reduce_encrypted_payload_and_reopen_without_drift() {
    let fixture = Fixture::new();
    let store = create(&fixture);
    let write = store.begin(true, cancelled()).unwrap();
    write.create(1, &vector(1)).unwrap();
    let original = write.read(1).unwrap().vector;
    assert_reconstruction(&original, &vector(1));
    write.commit().unwrap();
    let before = node_frame(&fixture, &store, 1).0;
    assert_eq!(u32::from_le_bytes(before[..4].try_into().unwrap()), 2);
    assert_eq!(before.len() + 28, 552);
    // Separate transactions force authenticated disk reads, not only cache reuse.
    for pass in 0..64 {
        let write = store.begin(true, cancelled()).unwrap();
        write.neighbors(1, &[pass + 2]).unwrap();
        assert_eq!(
            write.read(1).unwrap().vector.as_slice(),
            original.as_slice()
        );
        write.commit().unwrap();
    }
    let after = node_frame(&fixture, &store, 1).0;
    assert_eq!(&before[12..], &after[12..12 + DIMENSIONS]);
    store.close().unwrap();
    let reopened =
        SqliteIndexStore::open(&fixture.path, Zeroizing::new(KEY), IDENTITY, config()).unwrap();
    let read = reopened.begin(false, cancelled()).unwrap();
    assert_eq!(read.read(1).unwrap().vector.as_slice(), original.as_slice());
    assert_eq!(read.read(1).unwrap().neighbors.as_slice(), &[65]);
    read.commit().unwrap();
}

#[test]
fn sparse_vectors_use_lossless_fp16_instead_of_exceeding_sq8_error_bound() {
    let fixture = Fixture::new();
    let store = create(&fixture);
    let mut sparse = vec![0.0; DIMENSIONS];
    sparse[17] = 1.0;
    let write = store.begin(true, cancelled()).unwrap();
    write.create(1, &sparse).unwrap();
    write.commit().unwrap();
    let frame = node_frame(&fixture, &store, 1).0;
    assert_eq!(u32::from_le_bytes(frame[..4].try_into().unwrap()), 3);
    assert_eq!(frame.len() + 28, 1064);
    let read = store.begin(false, cancelled()).unwrap();
    assert_eq!(read.read(1).unwrap().vector.as_slice(), sparse);
    read.commit().unwrap();
}

#[test]
fn legacy_fp32_nodes_survive_mixed_codec_reads_and_adjacency_updates() {
    let fixture = Fixture::new();
    let store = create(&fixture);
    let write = store.begin(true, cancelled()).unwrap();
    write.create(1, &vector(1)).unwrap();
    write.create(2, &vector(2)).unwrap();
    write.commit().unwrap();
    let (_, binding, _) = node_frame(&fixture, &store, 1);
    let mut legacy = Vec::new();
    legacy.extend_from_slice(&1u32.to_le_bytes());
    legacy.extend_from_slice(&(DIMENSIONS as u32).to_le_bytes());
    legacy.extend_from_slice(&0u32.to_le_bytes());
    for value in vector(1) {
        legacy.extend_from_slice(&value.to_le_bytes());
    }
    replace_frame(&fixture, &store, 1, &legacy, &binding);
    let write = store.begin(true, cancelled()).unwrap();
    assert_eq!(write.read(1).unwrap().vector.as_slice(), vector(1));
    assert_reconstruction(&write.read(2).unwrap().vector, &vector(2));
    write.neighbors(1, &[2]).unwrap();
    write.commit().unwrap();
    let updated = node_frame(&fixture, &store, 1).0;
    assert_eq!(&updated[12..12 + DIMENSIONS * 4], &legacy[12..]);
    assert_eq!(u32::from_le_bytes(updated[..4].try_into().unwrap()), 1);
}

#[test]
fn outlier_fp16_nodes_do_not_drift_and_nonfinite_payloads_fail() {
    let fixture = Fixture::new();
    let store = create(&fixture);
    let mut values = vector(9);
    values.iter_mut().for_each(|v| *v *= 0.1);
    values[0] = 1.0;
    let norm = values
        .iter()
        .map(|v| f64::from(*v).powi(2))
        .sum::<f64>()
        .sqrt();
    values
        .iter_mut()
        .for_each(|v| *v = (f64::from(*v) / norm) as f32);
    let write = store.begin(true, cancelled()).unwrap();
    write.create(1, &values).unwrap();
    let decoded = write.read(1).unwrap().vector;
    assert_reconstruction(&decoded, &values);
    write.commit().unwrap();
    let before = node_frame(&fixture, &store, 1).0;
    assert_eq!(u32::from_le_bytes(before[..4].try_into().unwrap()), 3);
    for pass in 0..64 {
        let write = store.begin(true, cancelled()).unwrap();
        write.neighbors(1, &[2 + pass]).unwrap();
        assert_eq!(write.read(1).unwrap().vector.as_slice(), decoded.as_slice());
        write.commit().unwrap();
    }
    let (good, binding, _) = node_frame(&fixture, &store, 1);
    assert_eq!(&before[12..], &good[12..12 + DIMENSIONS * 2]);
    for code in [0x7e00u16, 0x7c00, 0xfc00] {
        let mut bad = good.clone();
        bad[12..14].copy_from_slice(&code.to_le_bytes());
        replace_frame(&fixture, &store, 1, &bad, &binding);
        let read = store.begin(false, cancelled()).unwrap();
        assert!(read.read(1).is_err());
        assert!(read.commit().is_err());
    }
    replace_frame(&fixture, &store, 1, &good, &binding);
    store.close().unwrap();
    let store =
        SqliteIndexStore::open(&fixture.path, Zeroizing::new(KEY), IDENTITY, config()).unwrap();
    let read = store.begin(false, cancelled()).unwrap();
    assert_eq!(read.read(1).unwrap().vector.as_slice(), decoded.as_slice());
    read.commit().unwrap();
}

#[test]
fn authenticated_invalid_compact_layouts_are_rejected_and_rollback() {
    let fixture = Fixture::new();
    let store = create(&fixture);
    let write = store.begin(true, cancelled()).unwrap();
    write.create(1, &vector(1)).unwrap();
    write.commit().unwrap();
    let (good, binding, _) = node_frame(&fixture, &store, 1);
    for case in 0..5 {
        let mut bad = good.clone();
        match case {
            0 => bad[..4].copy_from_slice(&4u32.to_le_bytes()),
            1 => bad[4..8].copy_from_slice(&8193u32.to_le_bytes()),
            2 => bad[8..12].copy_from_slice(&129u32.to_le_bytes()),
            3 => {
                bad.pop();
            }
            _ => bad.push(0),
        }
        replace_frame(&fixture, &store, 1, &bad, &binding);
        let write = store.begin(true, cancelled()).unwrap();
        assert!(write.read(1).is_err(), "case={case}");
        assert!(write.commit().is_err());
    }
    replace_frame(&fixture, &store, 1, &good, &binding);
    let read = store.begin(false, cancelled()).unwrap();
    assert_reconstruction(&read.read(1).unwrap().vector, &vector(1));
    read.commit().unwrap();
}

#[test]
fn compact_ann_is_measured_against_full_precision_exact_neighbors() {
    let fixture = Fixture::new();
    let store = create(&fixture);
    let rt = runtime();
    let start = Instant::now();
    for batch in 0..10 {
        let write = store.begin(true, cancelled()).unwrap();
        let index = Index::open(write.clone(), DIMENSIONS).unwrap();
        for id in batch * 32 + 1..=(batch + 1) * 32 {
            rt.block_on(index.insert(id, &vector(id))).unwrap();
        }
        write.commit().unwrap();
    }
    let insert_ms = start.elapsed().as_secs_f64() * 1000.0;
    store.close().unwrap();
    let store =
        SqliteIndexStore::open(&fixture.path, Zeroizing::new(KEY), IDENTITY, config()).unwrap();
    let mut hits = 0;
    let mut samples = Vec::new();
    for q in 0..64 {
        let query = vector(10_000 + q);
        let mut truth: Vec<_> = (1..=320)
            .map(|id| {
                let distance: f64 = query
                    .iter()
                    .zip(vector(id))
                    .map(|(a, b)| (f64::from(*a) - f64::from(b)).powi(2))
                    .sum();
                (id, distance)
            })
            .collect();
        truth.sort_by(|a, b| a.1.total_cmp(&b.1));
        let start = Instant::now();
        let read = store.begin(false, cancelled()).unwrap();
        let index = Index::open(read.clone(), DIMENSIONS).unwrap();
        let results = rt.block_on(index.search(&query, 10, 128)).unwrap();
        read.commit().unwrap();
        samples.push(start.elapsed().as_secs_f64() * 1000.0);
        hits += results
            .iter()
            .filter(|result| truth[..10].iter().any(|item| item.0 == result.0))
            .count();
    }
    let recall = hits as f64 / 640.0;
    println!(
        "sq8_ann rows=320 dims=512 queries=64 recall_at_10={recall:.6} insert_ms={insert_ms:.3}"
    );
    println!("sq8_ann_raw_ms={samples:?}");
    samples.sort_by(f64::total_cmp);
    println!(
        "sq8_ann p50_ms={:.3} p95_ms={:.3} p99_ms={:.3}",
        samples[31], samples[60], samples[63]
    );
    assert!(recall >= 0.95, "recall={recall}");
    assert!(samples[60] < 200.0, "p95_ms={}", samples[60]);
}
