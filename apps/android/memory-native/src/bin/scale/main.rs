mod data;
use galaxyssi_memory_native::{
    replay::{Chunk, ReplayIndex, format::Event},
    sqlite_store::{SqliteIndexStore, StoreConfig},
    store::NodeStore,
};
use std::{
    fs,
    path::Path,
    sync::{Arc, atomic::AtomicBool},
    time::Instant,
};
use zeroize::Zeroizing;
const KEY: [u8; 32] = [0x68; 32]; // Public synthetic fixture key; never access App data.
const IDENTITY: [u8; 32] = [0x74; 32];
const EPOCH: [u8; 16] = [0x46; 16];
fn cancelled() -> Arc<AtomicBool> {
    Arc::new(AtomicBool::new(false))
}
fn ms(start: Instant) -> f64 {
    start.elapsed().as_secs_f64() * 1000.0
}
fn start_id(key: &[u8; 32]) -> u64 {
    u64::from_le_bytes(key[..8].try_into().unwrap())
}
fn event(sequence: u64, first: u64, count: u64) -> Event {
    let mut key = [0x51; 32];
    key[..8].copy_from_slice(&first.to_le_bytes());
    Event {
        sequence,
        previous: sequence - 1,
        key,
        revision: [0x13; 32],
        chunks: count,
        removed: false,
    }
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().collect();
    if args.len() != 5 {
        return Err(
            "Usage: memory-native-scale <grow|measure> <fixture-path> <target-rows> <batch-1..64>"
                .into(),
        );
    }
    let mode = &args[1];
    if mode != "grow" && mode != "measure" {
        return Err("Unknown scale mode".into());
    }
    let path = Path::new(&args[2]);
    if !path.is_absolute()
        || !path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .starts_with("galaxyssi-native-scale-")
    {
        return Err("Use an absolute, isolated galaxyssi-native-scale-* fixture path".into());
    }
    let target: u64 = args[3].parse()?;
    let batch: u64 = args[4].parse()?;
    if target < 64 || !(1..=64).contains(&batch) {
        return Err("At least 64 rows and a 1..64 vector replay page are required".into());
    }
    let cfg = StoreConfig {
        dimensions: data::DIMENSIONS,
        shards: 4,
        cache_bytes: 8 * 1024 * 1024,
    };
    let create = !path.exists();
    if create && mode == "measure" {
        return Err("Measurement requires an existing fixture".into());
    }
    let opened = Instant::now();
    let store = if create {
        SqliteIndexStore::create(path, Zeroizing::new(KEY), IDENTITY, cfg, &data::vector(0))?
    } else {
        SqliteIndexStore::open(path, Zeroizing::new(KEY), IDENTITY, cfg)?
    };
    let index = ReplayIndex::attach(store.clone(), EPOCH, cancelled(), create)?;
    let rt = tokio::runtime::Builder::new_current_thread().build()?;
    println!(
        "scale_open rows={} ms={:.3} pager_target_bytes={} os_cache_not_dropped=true",
        index.node_count()? - 1,
        ms(opened),
        cfg.cache_bytes
    );
    if mode == "grow" {
        let started = Instant::now();
        let mut rows = index.node_count()? - 1;
        if rows > target {
            return Err("Growth target is below the already committed row count".into());
        }
        let mut checkpoint = index.checkpoint()?;
        let mut timings = Vec::with_capacity(256);
        while rows < target || checkpoint.pending.is_some() {
            let event = checkpoint
                .pending
                .as_ref()
                .map(|p| p.event.clone())
                .unwrap_or_else(|| {
                    event(
                        checkpoint.sequence() + 1,
                        rows + 1,
                        batch.min(target - rows),
                    )
                });
            let next = checkpoint.pending.as_ref().map_or(0, |p| p.next);
            if start_id(&event.key) + event.chunks - 1 > target {
                return Err("Requested target is below pending committed work".into());
            }
            let chunks: Vec<_> = (next..event.chunks)
                .map(|ordinal| Chunk {
                    ordinal,
                    start: ordinal * 10,
                    end: ordinal * 10 + 10,
                    vector: Zeroizing::new(data::vector(start_id(&event.key) + ordinal)),
                })
                .collect();
            let write = Instant::now();
            index.begin_event(&event, false)?;
            checkpoint = rt.block_on(index.append(&event, &chunks))?;
            timings.push(ms(write));
            rows = index.node_count()? - 1;
            if timings.len() == 128 || rows == target {
                data::report(rows, "durable_replay_page", &timings);
                timings.clear();
                println!(
                    "scale_progress rows={rows} target={target} elapsed_ms={:.3}",
                    ms(started)
                );
            }
        }
        assert!(checkpoint.pending.is_none());
        println!(
            "scale_grown rows={rows} elapsed_ms={:.3} batch={batch}",
            ms(started)
        );
    } else {
        let rows = index.node_count()? - 1;
        if rows != target || index.checkpoint()?.pending.is_some() {
            return Err("Actual row count/checkpoint does not match measurement target".into());
        }
        let queries = data::queries();
        let oracle_start = Instant::now();
        let exact = data::exact(rows, &queries);
        println!(
            "scale_oracle rows={rows} ms={:.3} streaming=true",
            ms(oracle_start)
        );
        let mut timings = Vec::new();
        let mut recall = 0;
        for (query, exact) in queries.iter().zip(exact) {
            let start = Instant::now();
            let matches = rt.block_on(index.search(query, 8, 256))?;
            timings.push(ms(start));
            let ids: Vec<_> = matches
                .iter()
                .map(|m| start_id(&m.source.key) + m.source.ordinal)
                .collect();
            let mut unique = ids.clone();
            unique.sort_unstable();
            unique.dedup();
            assert_eq!(ids.len(), unique.len());
            let snapshot = store.begin(false, cancelled())?;
            for m in &matches {
                let id = start_id(&m.source.key) + m.source.ordinal;
                assert!((1..=rows).contains(&id));
                let decoded = snapshot.read(id)?;
                assert!((m.similarity - data::dot(query, &decoded.vector)).abs() < 1e-5);
            }
            snapshot.commit()?;
            recall += exact.iter().filter(|id| ids.contains(id)).count();
        }
        data::report(rows, "heldout_ann", &timings);
        println!(
            "scale_recall rows={rows} found={recall} expected={} breadth=256",
            data::QUERIES * 8
        );
        // Full persisted-vector verification, separate from timed ANN and exact oracle.
        let verify = Instant::now();
        let session = store.begin(false, cancelled())?;
        let mut max_squared_error = 0.0f64;
        for id in 1..=rows {
            let actual = session.read(id)?;
            let squared_error: f64 = actual
                .vector
                .iter()
                .zip(data::vector(id))
                .map(|(a, b)| (f64::from(*a) - f64::from(b)).powi(2))
                .sum();
            assert!(
                squared_error <= 0.0001,
                "node={id} squared_error={squared_error}"
            );
            max_squared_error = max_squared_error.max(squared_error);
        }
        session.commit()?;
        println!(
            "scale_verified rows={rows} ms={:.3} max_squared_error={max_squared_error:.9}",
            ms(verify)
        );
    }
    let bytes: u64 = fs::read_dir(path)?
        .map(|e| e.unwrap().metadata().unwrap().len())
        .sum();
    println!("scale_files bytes={bytes}");
    if let Ok(status) = fs::read_to_string("/proc/self/status") {
        for line in status
            .lines()
            .filter(|s| s.starts_with("VmRSS:") || s.starts_with("VmHWM:"))
        {
            println!("scale_memory {line}");
        }
    }
    store.close()?;
    Ok(())
}
