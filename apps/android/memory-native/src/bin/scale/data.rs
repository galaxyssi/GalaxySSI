pub const DIMENSIONS: usize = 512;
pub const QUERIES: usize = 32;

fn random(seed: u64) -> Vec<f32> {
    let mut state = seed;
    (0..DIMENSIONS)
        .map(|_| {
            state = state.wrapping_add(0x9e3779b97f4a7c15);
            let mut n = state;
            n = (n ^ (n >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
            n = (n ^ (n >> 27)).wrapping_mul(0x94d049bb133111eb);
            ((n ^ (n >> 31)) >> 40) as f32 / 8388608.0 - 1.0
        })
        .collect()
}
pub fn vector(id: u64) -> Vec<f32> {
    // Reproducible clustered synthetic vectors, not a real embedding-quality corpus.
    let topic = random((id % 64).wrapping_add(0xfeed0000));
    let mut values = random(id.wrapping_add(0x120000000));
    for (value, center) in values.iter_mut().zip(topic) {
        *value = *value * 0.22 + center;
    }
    let norm = values.iter().map(|v| v * v).sum::<f32>().sqrt();
    values.iter_mut().for_each(|v| *v /= norm);
    values
}
pub fn queries() -> Vec<Vec<f32>> {
    (0..QUERIES)
        .map(|i| vector((1 << 48) + i as u64 * 977))
        .collect()
}
pub fn dot(a: &[f32], b: &[f32]) -> f32 {
    a.iter().zip(b).map(|(a, b)| a * b).sum()
}
pub fn exact(rows: u64, queries: &[Vec<f32>]) -> Vec<Vec<u64>> {
    let mut best: Vec<Vec<(f32, u64)>> = vec![Vec::new(); queries.len()];
    // Stream the complete corpus and retain only top eight per held-out query.
    for id in 1..=rows {
        let vector = vector(id);
        for (query, best) in queries.iter().zip(best.iter_mut()) {
            let score = dot(query, &vector);
            if best.len() < 8 || score > best.last().unwrap().0 {
                best.push((score, id));
                best.sort_unstable_by(|a, b| b.0.total_cmp(&a.0).then(a.1.cmp(&b.1)));
                best.truncate(8);
            }
        }
    }
    best.into_iter()
        .map(|top| top.into_iter().map(|(_, id)| id).collect())
        .collect()
}
pub fn report(rows: u64, phase: &str, samples: &[f64]) {
    let mut sorted = samples.to_vec();
    sorted.sort_by(f64::total_cmp);
    let p = |v: usize| sorted[(sorted.len() * v).div_ceil(100) - 1];
    println!(
        "scale_latency rows={rows} phase={phase} n={} p50_ms={:.3} p95_ms={:.3} p99_ms={:.3} max_ms={:.3}",
        samples.len(),
        p(50),
        p(95),
        p(99),
        sorted.last().unwrap()
    );
    println!("scale_raw rows={rows} phase={phase} ms={samples:?}");
}
