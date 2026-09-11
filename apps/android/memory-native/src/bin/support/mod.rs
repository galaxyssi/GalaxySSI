// Probe-only file-per-node fixture with a PUBLIC TEST KEY. Not a production
// storage layout, key-management implementation, or transaction implementation.
use aes_gcm::{
    Aes256Gcm, KeyInit, Nonce,
    aead::{Aead, AeadCore, OsRng, Payload},
};
use diskann::{ANNError, ANNResult};
use galaxyssi_memory_native::store::{MAX_NEIGHBORS, Node, NodeStore};
use std::{
    fs::{self, File},
    io::{Read, Write},
    path::PathBuf,
    sync::atomic::{AtomicUsize, Ordering},
};
use zeroize::Zeroizing;

pub const DIMENSIONS: usize = 32;
pub const COUNT: u64 = 64;
pub struct DiskFixture {
    pub root: PathBuf,
    cipher: Aes256Gcm,
    pub reads: AtomicUsize,
}
impl DiskFixture {
    pub fn open(root: PathBuf, wrong_key: bool) -> ANNResult<Self> {
        if !root
            .file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| name.starts_with("galaxyssi-native-memory-"))
        {
            return Err(ANNError::message(
                "Probe requires an isolated fixture directory",
            ));
        }
        Ok(Self {
            root,
            cipher: Aes256Gcm::new_from_slice(&[if wrong_key { 0x74 } else { 0x73 }; 32]).unwrap(),
            reads: AtomicUsize::new(0),
        })
    }
    pub fn file(&self, id: u64) -> PathBuf {
        self.root.join(format!("{id:016x}.node"))
    }
    fn aad(&self, id: u64) -> Vec<u8> {
        let mut aad = b"galaxyssi-native-probe:v1\0".to_vec();
        aad.extend_from_slice(self.root.file_name().unwrap().as_encoded_bytes());
        aad.extend_from_slice(&id.to_le_bytes());
        aad
    }
    pub fn write(&self, id: u64, node: &Node) -> ANNResult<()> {
        node.validate(DIMENSIONS)?;
        let mut bytes = Zeroizing::new(Vec::new());
        bytes.extend_from_slice(&1u32.to_le_bytes());
        bytes.extend_from_slice(&(DIMENSIONS as u32).to_le_bytes());
        bytes.extend_from_slice(&(node.neighbors.len() as u32).to_le_bytes());
        for value in node.vector.iter() {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        for value in node.neighbors.iter() {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
        let encrypted = self
            .cipher
            .encrypt(
                &nonce,
                Payload {
                    msg: &bytes,
                    aad: &self.aad(id),
                },
            )
            .map_err(|_| ANNError::message("Probe encryption failed"))?;
        let temporary = self.root.join(format!("{id:016x}.pending"));
        let mut output = File::create(&temporary)?;
        output.write_all(&nonce)?;
        output.write_all(&encrypted)?;
        output.sync_all()?;
        fs::rename(temporary, self.file(id))?;
        Ok(())
    }
}
impl NodeStore for DiskFixture {
    fn read(&self, id: u64) -> ANNResult<Node> {
        self.reads.fetch_add(1, Ordering::Relaxed);
        let mut encrypted = Zeroizing::new(Vec::new());
        File::open(self.file(id))?
            .take(4097)
            .read_to_end(&mut encrypted)?;
        if encrypted.len() < 28 || encrypted.len() > 4096 {
            return Err(ANNError::message("Invalid probe envelope length"));
        }
        let bytes = Zeroizing::new(
            self.cipher
                .decrypt(
                    Nonce::from_slice(&encrypted[..12]),
                    Payload {
                        msg: &encrypted[12..],
                        aad: &self.aad(id),
                    },
                )
                .map_err(|_| ANNError::message("Probe authentication failed"))?,
        );
        if bytes.len() < 12 {
            return Err(ANNError::message("Truncated probe node"));
        }
        let number =
            |offset| u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap()) as usize;
        let degree = number(8);
        if number(0) != 1
            || number(4) != DIMENSIONS
            || degree > MAX_NEIGHBORS
            || bytes.len() != 12 + DIMENSIONS * 4 + degree * 8
        {
            return Err(ANNError::message("Invalid probe node dimensions"));
        }
        let vector = Zeroizing::new(
            bytes[12..12 + DIMENSIONS * 4]
                .chunks_exact(4)
                .map(|v| f32::from_le_bytes(v.try_into().unwrap()))
                .collect::<Vec<_>>(),
        );
        let neighbors = Zeroizing::new(
            bytes[12 + DIMENSIONS * 4..]
                .chunks_exact(8)
                .map(|v| u64::from_le_bytes(v.try_into().unwrap()))
                .collect(),
        );
        let mut node = Node::new(&vector);
        node.neighbors = neighbors;
        node.validate(DIMENSIONS)?;
        Ok(node)
    }
    fn create(&self, id: u64, vector: &[f32]) -> ANNResult<()> {
        if self.file(id).exists() {
            return Err(ANNError::message("Duplicate probe node"));
        }
        self.write(id, &Node::new(vector))
    }
    fn neighbors(&self, id: u64, values: &[u64]) -> ANNResult<()> {
        let mut node = self.read(id)?;
        node.neighbors.clear();
        node.neighbors.extend_from_slice(values);
        self.write(id, &node)
    }
    fn check_active(&self) -> ANNResult<()> {
        Ok(())
    }
}
pub fn vector(id: u64) -> Vec<f32> {
    let mut state = id + 91;
    let mut values: Vec<f32> = (0..DIMENSIONS)
        .map(|_| {
            state = state.wrapping_mul(6364136223846793005).wrapping_add(1);
            (state >> 40) as f32 / 8388608.0 - 1.0
        })
        .collect();
    let norm = values.iter().map(|v| v * v).sum::<f32>().sqrt();
    values.iter_mut().for_each(|v| *v /= norm);
    values
}
