use super::{Fixture, IDENTITY, KEY, cancelled, config};
use galaxyssi_memory_native::{sqlite_store::SqliteIndexStore, store::NodeStore};
use std::{fs, time::Instant};
use zeroize::Zeroizing;

fn vector(id: u64) -> Vec<f32> {
    let mut seed = id.wrapping_add(853);
    let mut values: Vec<_> = (0..384)
        .map(|_| {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
            (seed >> 40) as f32 / 8388608.0 - 1.0
        })
        .collect();
    let length = values.iter().map(|v| v * v).sum::<f32>().sqrt();
    values.iter_mut().for_each(|v| *v /= length);
    values
}

fn report(rows: u64, phase: &str, samples: &[f64]) {
    let mut sorted = samples.to_vec();
    sorted.sort_by(f64::total_cmp);
    let percentile = |percent: usize| sorted[(sorted.len() * percent).div_ceil(100) - 1];
    println!(
        "point_io rows={rows} phase={phase} n={} p50_ms={:.3} p95_ms={:.3} p99_ms={:.3} max_ms={:.3}",
        sorted.len(),
        percentile(50),
        percentile(95),
        percentile(99),
        sorted.last().unwrap()
    );
    // Keep every sample, including outliers; these are not production recall gates.
    println!("point_io_raw rows={rows} phase={phase} ms={samples:?}");
}

#[test]
fn increasing_cardinality_retains_nodes_with_fixed_pager_target() {
    let fixture = Fixture::new();
    let mut cfg = config();
    cfg.dimensions = 384;
    let mut store = SqliteIndexStore::create(
        &fixture.path,
        Zeroizing::new(KEY),
        IDENTITY,
        cfg,
        &vector(0),
    )
    .unwrap();
    let mut inserted = 0;
    for target in [100, 1_000, 10_000] {
        let prepare = Instant::now();
        // Seed only bounded batches; never assemble the corpus in memory.
        while inserted < target {
            let session = store.begin(true, cancelled()).unwrap();
            let end = (inserted + 128).min(target);
            for id in inserted + 1..=end {
                session.create(id, &vector(id)).unwrap();
            }
            session.commit().unwrap();
            inserted = end;
        }
        println!(
            "point_io_seed rows={inserted} elapsed_ms={:.3}",
            prepare.elapsed().as_secs_f64() * 1000.0
        );
        store.close().unwrap();
        drop(store);
        let start = Instant::now();
        store = SqliteIndexStore::open(&fixture.path, Zeroizing::new(KEY), IDENTITY, cfg).unwrap();
        println!(
            "point_io_reopen rows={inserted} elapsed_ms={:.3} os_cache_not_dropped=true",
            start.elapsed().as_secs_f64() * 1000.0
        );
        let mut reads = Vec::new();
        let mut writes = Vec::new();
        for sample in 0..32 {
            let id = 1 + (sample * 977) % target;
            let expected = vector(id);
            let start = Instant::now();
            let session = store.begin(false, cancelled()).unwrap();
            let node = session.read(id).unwrap();
            session.commit().unwrap();
            reads.push(start.elapsed().as_secs_f64() * 1000.0);
            super::compact::assert_reconstruction(&node.vector, &expected);

            let value = vector(inserted + 1);
            let start = Instant::now();
            let session = store.begin(true, cancelled()).unwrap();
            session.create(inserted + 1, &value).unwrap();
            session.commit().unwrap();
            writes.push(start.elapsed().as_secs_f64() * 1000.0);
            inserted += 1;
        }
        report(target, "read", &reads);
        report(target, "durable_write", &writes);
        let session = store.begin(false, cancelled()).unwrap();
        assert_eq!(session.node_count().unwrap(), inserted + 1);
        // Verify ALL retained vectors, not only the timed sample or catalog count.
        for id in 1..=inserted {
            super::compact::assert_reconstruction(&session.read(id).unwrap().vector, &vector(id));
        }
        session.commit().unwrap();
        let disk_bytes: u64 = fs::read_dir(&fixture.path)
            .unwrap()
            .map(|entry| entry.unwrap().metadata().unwrap().len())
            .sum();
        println!(
            "point_io_storage rows={inserted} disk_bytes={disk_bytes} pager_target_bytes={}",
            cfg.cache_bytes
        );
        if target == 10_000 {
            assert!(disk_bytes > cfg.cache_bytes as u64);
        }
        #[cfg(target_os = "android")]
        for line in fs::read_to_string("/proc/self/status")
            .unwrap()
            .lines()
            .filter(|line| line.starts_with("VmRSS:") || line.starts_with("VmHWM:"))
        {
            println!("point_io_process rows={inserted} {line}");
        }
    }
    store.close().unwrap();
}
