mod support;
use diskann::{ANNError, ANNResult};
use galaxyssi_memory_native::{
    Index,
    store::{Node, ROOT},
};
use std::{
    fs::{self, File},
    io::Write,
    path::PathBuf,
    sync::{Arc, atomic::Ordering},
    time::Instant,
};
use support::{COUNT, DIMENSIONS, DiskFixture, vector};

fn run() -> ANNResult<()> {
    let args: Vec<_> = std::env::args().collect();
    if args.len() != 3 {
        return Err(ANNError::message(
            "Expected phase and isolated fixture path",
        ));
    }
    let root = PathBuf::from(&args[2]);
    let fixture = Arc::new(DiskFixture::open(root.clone(), args[1] == "wrong-key")?);
    let runtime = tokio::runtime::Builder::new_current_thread().build()?;
    match args[1].as_str() {
        "prepare" => {
            fs::create_dir(&root)?;
            fixture.write(ROOT, &Node::new(&vector(0)))?;
            let index = Index::open(fixture, DIMENSIONS)?;
            let started = Instant::now();
            for id in 1..=COUNT {
                runtime.block_on(index.insert(id, &vector(id)))?;
            }
            let mut marker = File::create(root.join("ready"))?;
            marker.write_all(&COUNT.to_le_bytes())?;
            marker.sync_all()?;
            #[cfg(unix)]
            File::open(&root)?.sync_all()?;
            println!(
                "prepared count={COUNT} elapsed_ms={:.3}",
                started.elapsed().as_secs_f64() * 1000.0
            );
        }
        "verify" => {
            if fs::read(root.join("ready"))? != COUNT.to_le_bytes() {
                return Err(ANNError::message("Probe fixture was not completed"));
            }
            let started = Instant::now();
            let index = Index::open(fixture.clone(), DIMENSIONS)?;
            let opening_reads = fixture.reads.load(Ordering::Relaxed);
            if opening_reads != 1 {
                return Err(ANNError::message("Opening scanned more than the root"));
            }
            println!(
                "opened nodes_read={opening_reads} elapsed_ms={:.3}",
                started.elapsed().as_secs_f64() * 1000.0
            );
            for id in [1, 8, 32, COUNT] {
                let started = Instant::now();
                let hits = runtime.block_on(index.search(&vector(id), 8, 128))?;
                if hits.first().map(|v| v.0) != Some(id) || hits[0].1.abs() > 1e-5 {
                    return Err(ANNError::message(
                        "Persisted native fixture nearest neighbor mismatch",
                    ));
                }
                println!(
                    "query id={id} elapsed_ms={:.3}",
                    started.elapsed().as_secs_f64() * 1000.0
                );
            }
            println!(
                "verified persisted_encrypted_vectors={COUNT} nodes_read={}",
                fixture.reads.load(Ordering::Relaxed)
            );
        }
        "wrong-key" => {
            Index::open(Arc::new(DiskFixture::open(root, false)?), DIMENSIONS)?;
            let rejected = Index::open(fixture, DIMENSIONS)
                .err()
                .is_some_and(|error| error.to_string().contains("Probe authentication failed"));
            if !rejected {
                return Err(ANNError::message(
                    "Wrong key did not produce an authentication failure",
                ));
            }
            println!("wrong_key_rejected");
        }
        "corrupt" => {
            Index::open(fixture.clone(), DIMENSIONS)?;
            let path = fixture.file(ROOT);
            let original = fs::read(&path)?;
            let mut changed = original.clone();
            if changed.len() < 28 {
                return Err(ANNError::message("Probe root was already damaged"));
            }
            changed[12] ^= 1;
            fs::write(&path, changed)?;
            let rejected = Index::open(fixture, DIMENSIONS)
                .err()
                .is_some_and(|error| error.to_string().contains("Probe authentication failed"));
            fs::write(path, original)?;
            if !rejected {
                return Err(ANNError::message("Corruption unexpectedly accepted"));
            }
            println!("corruption_rejected_original_restored");
        }
        _ => return Err(ANNError::message("Unknown probe phase")),
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("native_memory_probe_failed: {error}");
        std::process::exit(1);
    }
}
