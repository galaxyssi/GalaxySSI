use super::*;
use std::ptr;

fn config() -> OpenConfig {
    OpenConfig { abi_version: 1, dimensions: 2, shards: 4, cache_bytes: 4 * 1024 * 1024,
        key: [0; 32], identity: [1; 32], epoch: [2; 16] }
}

#[test]
fn invalid_open_clears_handle_without_creating_files() {
    let mut handle = 99;
    let path = b"relative-index";
    let result = unsafe { gs_memory_open(path.as_ptr(), path.len(), &config(), ptr::null(), 0, &mut handle) };
    assert_eq!(result, 1);
    assert_eq!(handle, 0);
}

#[test]
fn invalid_configuration_and_null_pointers_are_rejected() {
    assert_eq!(std::mem::size_of::<OpenConfig>(), 104);
    assert_eq!(std::mem::offset_of!(OpenConfig, cache_bytes), 16);
    assert_eq!(std::mem::offset_of!(OpenConfig, key), 24);
    let mut handle = 99;
    assert_eq!(unsafe { gs_memory_open(ptr::null(), 1, ptr::null(), ptr::null(), 0, &mut handle) }, 1);
    assert_eq!(handle, 0);
    let mut settings = config();
    settings.abi_version = 2;
    let path = b"/not-created";
    assert_eq!(unsafe { gs_memory_open(path.as_ptr(), path.len(), &settings, ptr::null(), 0, &mut handle) }, 1);
    assert_eq!(handle, 0);
    assert_eq!(unsafe { gs_memory_open(path.as_ptr(), path.len(), &config(), ptr::null(), 0, ptr::null_mut()) }, 1);
}

#[test]
fn checkpoint_rejects_closed_handles_and_small_buffers() {
    let mut bytes = [7u8; 208];
    let mut written = 99;
    assert_eq!(unsafe { gs_memory_checkpoint(-1, bytes.as_mut_ptr(), bytes.len(), &mut written) }, 1);
    assert_eq!(written, 0);
    assert_eq!(bytes, [7; 208]);
    written = 99;
    assert_eq!(unsafe { gs_memory_checkpoint(-1, bytes.as_mut_ptr(), 1, &mut written) }, 1);
    assert_eq!(written, 0);
}

#[test]
fn begin_rejects_invalid_flag_and_malformed_event() {
    let event = [0u8; 93];
    let mut bytes = [0u8; 208];
    let mut written = 99;
    assert_eq!(unsafe { gs_memory_begin(-1, event.as_ptr(), 93, 2, bytes.as_mut_ptr(), 208, &mut written) }, 1);
    assert_eq!(written, 0);
    assert_eq!(unsafe { gs_memory_begin(-1, event.as_ptr(), 93, 0, bytes.as_mut_ptr(), 208, &mut written) }, 1);
    assert_eq!(unsafe { gs_memory_begin(-1, event.as_ptr(), 92, 0, bytes.as_mut_ptr(), 208, &mut written) }, 1);
    let oversized = Event { sequence: u64::MAX, previous: 0, chunks: 1,
        key: [1; 32], revision: [2; 32], removed: false }.encode();
    assert!(unsafe { decode_event(oversized.as_ptr(), oversized.len()) }.is_err());
}

#[test]
fn append_rejects_malformed_event_before_vector_read() {
    let event = [0u8; 93];
    let mut bytes = [0u8; 208];
    let mut written = 99;
    assert_eq!(unsafe { gs_memory_append(-1, event.as_ptr(), event.len(), ptr::null(), 0,
        ptr::null(), 0, bytes.as_mut_ptr(), 208, &mut written) }, 1);
    assert_eq!(written, 0);
}

#[test]
fn buffers_reject_alignment_lengths_and_nonfinite_vectors() {
    let storage = [0u64; 8];
    let misaligned = unsafe { storage.as_ptr().cast::<u8>().add(1) }.cast::<u64>();
    assert!(unsafe { input(misaligned, 1, 1, 1) }.is_err());
    assert!(unsafe { input(storage.as_ptr(), usize::MAX, 1, usize::MAX) }.is_err());
    let values = [f32::NAN, 1.0];
    assert!(unsafe { floats(values.as_ptr(), 2, 2) }.is_err());
    assert!(unsafe { floats(values.as_ptr(), 1, 2) }.is_err());
}

#[test]
fn search_bounds_fail_without_dereferencing_query() {
    let mut bytes = [0u8; 112];
    let mut written = 0;
    for (count, breadth) in [(0, 1), (257, 512), (1, 1), (1, 4097)] {
        assert_eq!(unsafe { gs_memory_search(-1, ptr::null(), 0, count, breadth,
            bytes.as_mut_ptr(), bytes.len(), &mut written) }, 1);
    }
}

#[test]
fn cancelled_or_closed_unknown_handles_are_idempotent() {
    assert_eq!(gs_memory_cancel(-1), 0);
    assert_eq!(gs_memory_close(-1), 0);
    assert_eq!(gs_memory_close(-1), 0);
    let mut count = 99;
    assert_eq!(unsafe { gs_memory_node_count(-1, &mut count) }, 1);
    assert_eq!(count, 0);
    assert_eq!(unsafe { gs_memory_node_count(-1, ptr::null_mut()) }, 1);
}

#[test]
fn panic_is_contained_at_boundary() {
    assert_eq!(boundary(|| -> Result<()> { panic!("synthetic boundary panic") }), 2);
}

#[test]
fn record_maintenance_rejects_null_outputs_and_clears_error_flags() {
    assert_eq!(unsafe { gs_memory_records_partitioned(-1, ptr::null_mut()) }, 1);
    assert_eq!(unsafe { gs_memory_migrate_records(-1, 64, ptr::null_mut()) }, 1);
    let mut complete = 99;
    assert_eq!(unsafe { gs_memory_records_partitioned(-1, &mut complete) }, 1);
    assert_eq!(complete, 0);
    for limit in [0, 257, u32::MAX] {
        complete = 99;
        assert_eq!(unsafe { gs_memory_migrate_records(-1, limit, &mut complete) }, 1);
        assert_eq!(complete, 0);
    }
}

struct MaintenanceFixture { path: PathBuf, handle: i64 }
impl MaintenanceFixture {
    fn new() -> Self {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let path = std::env::temp_dir().join(format!("galaxyssi-ios-record-maintenance-{}-{}-{}",
            std::process::id(), std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos(),
            NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)));
        let mut fixture = Self { path, handle: 0 };
        fixture.open(true);
        fixture
    }
    fn open(&mut self, create: bool) {
        let text = self.path.to_str().unwrap().as_bytes();
        let root = [1.0, 0.0];
        assert_eq!(unsafe { gs_memory_open(text.as_ptr(), text.len(), &config(),
            if create { root.as_ptr() } else { ptr::null() }, if create { 2 } else { 0 }, &mut self.handle) }, 0);
    }
    fn checkpoint(&self) -> Vec<u8> {
        let mut bytes = vec![0; 208]; let mut written = 0;
        assert_eq!(unsafe { gs_memory_checkpoint(self.handle, bytes.as_mut_ptr(), bytes.len(), &mut written) }, 0);
        bytes.truncate(written); bytes
    }
}
impl Drop for MaintenanceFixture {
    fn drop(&mut self) { gs_memory_close(self.handle); let _ = std::fs::remove_dir_all(&self.path); }
}

#[test]
fn partitioned_store_maintenance_is_idempotent_and_preserves_replay_after_reopen() {
    let mut fixture = MaintenanceFixture::new();
    let before = fixture.checkpoint(); let mut complete = 99;
    assert_eq!(unsafe { gs_memory_records_partitioned(fixture.handle, &mut complete) }, 0);
    assert_eq!(complete, 1);
    for limit in [1, 64, 256] {
        assert_eq!(unsafe { gs_memory_migrate_records(fixture.handle, limit, &mut complete) }, 0);
        assert_eq!(complete, 1); assert_eq!(fixture.checkpoint(), before);
    }
    assert_eq!(gs_memory_close(fixture.handle), 0); fixture.handle = 0;
    fixture.open(false);
    assert_eq!(fixture.checkpoint(), before);
    assert_eq!(unsafe { gs_memory_records_partitioned(fixture.handle, &mut complete) }, 0);
    assert_eq!(complete, 1);
}

#[test]
fn cancelled_or_closed_record_maintenance_cannot_claim_completion() {
    let fixture = MaintenanceFixture::new(); let mut complete = 99;
    assert_eq!(gs_memory_cancel(fixture.handle), 0);
    assert_eq!(unsafe { gs_memory_migrate_records(fixture.handle, 64, &mut complete) }, 1);
    assert_eq!(complete, 0);
    complete = 99;
    assert_eq!(unsafe { gs_memory_records_partitioned(fixture.handle, &mut complete) }, 1);
    assert_eq!(complete, 0);
    assert_eq!(gs_memory_close(fixture.handle), 0);
    complete = 99;
    assert_eq!(unsafe { gs_memory_migrate_records(fixture.handle, 64, &mut complete) }, 1);
    assert_eq!(complete, 0);
}
