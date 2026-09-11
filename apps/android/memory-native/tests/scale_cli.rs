#![cfg(feature = "sqlite-store")]
use std::{
    fs,
    process::Command,
    time::{SystemTime, UNIX_EPOCH},
};

#[test]
fn scale_cli_resumes_real_replay_and_checks_every_persisted_vector() {
    let parent = fs::canonicalize(std::env::temp_dir()).unwrap();
    let path = parent.join(format!(
        "galaxyssi-native-scale-ci-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let run = |mode: &str, rows: &str| {
        let output = Command::new(env!("CARGO_BIN_EXE_memory-native-scale"))
            .args([mode, path.to_str().unwrap(), rows, "16"])
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8(output.stdout).unwrap()
    };
    assert!(run("grow", "64").contains("scale_grown rows=64"));
    assert!(run("grow", "96").contains("scale_grown rows=96"));
    let report = run("measure", "96");
    assert!(report.contains("scale_verified rows=96"));
    let recall = report
        .lines()
        .find(|line| line.starts_with("scale_recall "))
        .unwrap();
    let value = |name: &str| {
        recall
            .split_whitespace()
            .find_map(|field| field.strip_prefix(name))
            .unwrap()
            .parse::<usize>()
            .unwrap()
    };
    assert_eq!(value("expected="), 256);
    // SQ8 may exchange nearly tied neighbors; retain a 99% gate for this tiny corpus.
    assert!(value("found=") >= 254, "{report}");
    assert!(report.contains("max_squared_error="));
    println!("{report}");
    let wrong_count = Command::new(env!("CARGO_BIN_EXE_memory-native-scale"))
        .args(["measure", path.to_str().unwrap(), "64", "16"])
        .output()
        .unwrap();
    assert!(!wrong_count.status.success());
    let resolved = fs::canonicalize(&path).unwrap();
    assert_eq!(resolved.parent().unwrap(), parent);
    assert!(
        resolved
            .file_name()
            .unwrap()
            .to_str()
            .unwrap()
            .starts_with("galaxyssi-native-scale-ci-")
    );
    fs::remove_dir_all(resolved).unwrap();
}
