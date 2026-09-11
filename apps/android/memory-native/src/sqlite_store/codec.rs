use crate::store::{MAX_NEIGHBORS, Node, PackedVector};
use aes_gcm::{
    Aes256Gcm, KeyInit, Nonce,
    aead::{Aead, AeadCore, OsRng, Payload},
};
use diskann::{ANNError, ANNResult};
use zeroize::Zeroizing;

#[derive(Clone)]
pub(super) struct Metadata {
    pub dimensions: usize,
    pub shards: usize,
    pub generation: u64,
    pub count: u64,
    pub instance: [u8; 16],
}

pub(super) struct Crypto {
    cipher: Aes256Gcm,
    identity: [u8; 32],
}
impl Crypto {
    pub fn new(key: Zeroizing<[u8; 32]>, identity: [u8; 32]) -> Self {
        Self {
            cipher: Aes256Gcm::new_from_slice(key.as_slice()).unwrap(),
            identity,
        }
    }
    fn aad(&self, domain: &[u8]) -> Vec<u8> {
        let mut aad = b"galaxyssi:disk-memory:v1\0".to_vec();
        aad.extend_from_slice(&self.identity);
        aad.extend_from_slice(domain);
        aad
    }
    fn seal(&self, bytes: &[u8], aad: &[u8]) -> ANNResult<Vec<u8>> {
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
        let encrypted = self
            .cipher
            .encrypt(&nonce, Payload { msg: bytes, aad })
            .map_err(|_| ANNError::message("Native index encryption failed"))?;
        let mut result = nonce.to_vec();
        result.extend_from_slice(&encrypted);
        Ok(result)
    }
    fn unseal(&self, bytes: &[u8], aad: &[u8]) -> ANNResult<Zeroizing<Vec<u8>>> {
        if bytes.len() < 28 {
            return Err(ANNError::message("Truncated native index envelope"));
        }
        self.cipher
            .decrypt(
                Nonce::from_slice(&bytes[..12]),
                Payload {
                    msg: &bytes[12..],
                    aad,
                },
            )
            .map(Zeroizing::new)
            .map_err(|_| ANNError::message("Native index authentication failed"))
    }
    pub fn encode_meta(&self, meta: &Metadata) -> ANNResult<Vec<u8>> {
        let mut bytes = Zeroizing::new(Vec::with_capacity(48));
        bytes.extend_from_slice(b"GSAN0001");
        bytes.extend_from_slice(&(meta.dimensions as u32).to_le_bytes());
        bytes.extend_from_slice(&(meta.shards as u32).to_le_bytes());
        bytes.extend_from_slice(&meta.generation.to_le_bytes());
        bytes.extend_from_slice(&meta.count.to_le_bytes());
        bytes.extend_from_slice(&meta.instance);
        self.seal(&bytes, &self.aad(b"metadata"))
    }
    pub fn decode_meta(&self, envelope: &[u8]) -> ANNResult<Metadata> {
        if envelope.len() != 76 {
            return Err(ANNError::message("Invalid native index metadata size"));
        }
        let bytes = self.unseal(envelope, &self.aad(b"metadata"))?;
        if &bytes[..8] != b"GSAN0001" {
            return Err(ANNError::message("Unsupported native index format"));
        }
        Ok(Metadata {
            dimensions: u32::from_le_bytes(bytes[8..12].try_into().unwrap()) as usize,
            shards: u32::from_le_bytes(bytes[12..16].try_into().unwrap()) as usize,
            generation: u64::from_le_bytes(bytes[16..24].try_into().unwrap()),
            count: u64::from_le_bytes(bytes[24..32].try_into().unwrap()),
            instance: bytes[32..48].try_into().unwrap(),
        })
    }
    fn node_aad(&self, meta: &Metadata, id: u64, revision: u64) -> Vec<u8> {
        let mut aad = self.aad(b"node");
        aad.extend_from_slice(&meta.instance);
        aad.extend_from_slice(&(meta.dimensions as u32).to_le_bytes());
        aad.extend_from_slice(&(meta.shards as u32).to_le_bytes());
        aad.extend_from_slice(&id.to_le_bytes());
        aad.extend_from_slice(&revision.to_le_bytes());
        aad
    }
    fn record_aad(&self, meta: &Metadata, key: &[u8], revision: u64) -> Vec<u8> {
        let mut aad = self.aad(b"record");
        aad.extend_from_slice(&meta.instance);
        aad.extend_from_slice(&revision.to_le_bytes());
        aad.extend_from_slice(&(key.len() as u32).to_le_bytes());
        aad.extend_from_slice(key);
        aad
    }
    pub fn encode_record(&self, meta: &Metadata, key: &[u8], bytes: &[u8]) -> ANNResult<Vec<u8>> {
        self.seal(bytes, &self.record_aad(meta, key, meta.generation))
    }
    pub fn decode_record(
        &self,
        meta: &Metadata,
        key: &[u8],
        revision: u64,
        envelope: &[u8],
    ) -> ANNResult<Zeroizing<Vec<u8>>> {
        self.unseal(envelope, &self.record_aad(meta, key, revision))
    }
    pub fn encode_node(
        &self,
        meta: &Metadata,
        id: u64,
        revision: u64,
        node: &Node,
    ) -> ANNResult<Vec<u8>> {
        node.validate(meta.dimensions)?;
        let version = node
            .packed_vector
            .as_ref()
            .map_or(1, |packed| packed.format);
        let vector_bytes = match version {
            1 => meta.dimensions * 4,
            2 => meta.dimensions,
            3 => meta.dimensions * 2,
            _ => return Err(ANNError::message("Unsupported native node codec")),
        };
        let mut bytes = Zeroizing::new(Vec::with_capacity(
            12 + vector_bytes + node.neighbors.len() * 8,
        ));
        bytes.extend_from_slice(&version.to_le_bytes());
        bytes.extend_from_slice(&(meta.dimensions as u32).to_le_bytes());
        bytes.extend_from_slice(&(node.neighbors.len() as u32).to_le_bytes());
        if let Some(packed) = &node.packed_vector {
            if super::compact::decode(packed.format, &packed.bytes, meta.dimensions)?.as_slice()
                != node.vector.as_slice()
            {
                return Err(ANNError::message("Native compact codes/vector mismatch"));
            }
            bytes.extend_from_slice(&packed.bytes);
        } else {
            for value in node.vector.iter() {
                bytes.extend_from_slice(&value.to_le_bytes());
            }
        }
        for id in node.neighbors.iter() {
            bytes.extend_from_slice(&id.to_le_bytes());
        }
        self.seal(&bytes, &self.node_aad(meta, id, revision))
    }
    pub fn decode_node(
        &self,
        meta: &Metadata,
        id: u64,
        revision: u64,
        envelope: &[u8],
    ) -> ANNResult<Node> {
        let bytes = self.unseal(envelope, &self.node_aad(meta, id, revision))?;
        if bytes.len() < 12 {
            return Err(ANNError::message("Truncated native index node"));
        }
        let number =
            |offset| u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap()) as usize;
        let degree = number(8);
        let vector_bytes = match number(0) {
            1 => meta.dimensions * 4,
            2 => meta.dimensions,
            3 => meta.dimensions * 2,
            _ => return Err(ANNError::message("Unsupported native node codec")),
        };
        if number(4) != meta.dimensions
            || degree > MAX_NEIGHBORS
            || bytes.len() != 12 + vector_bytes + degree * 8
        {
            return Err(ANNError::message("Invalid native index node layout"));
        }
        let payload = &bytes[12..12 + vector_bytes];
        let packed_vector = (number(0) != 1).then(|| PackedVector {
            format: number(0) as u32,
            bytes: Zeroizing::new(payload.to_vec()),
        });
        let vector = if packed_vector.is_some() {
            super::compact::decode(number(0) as u32, payload, meta.dimensions)?
        } else {
            Zeroizing::new(
                payload
                    .chunks_exact(4)
                    .map(|v| f32::from_le_bytes(v.try_into().unwrap()))
                    .collect(),
            )
        };
        let node = Node {
            vector,
            packed_vector,
            neighbors: Zeroizing::new(
                bytes[12 + vector_bytes..]
                    .chunks_exact(8)
                    .map(|v| u64::from_le_bytes(v.try_into().unwrap()))
                    .collect(),
            ),
        };
        node.validate(meta.dimensions)?;
        Ok(node)
    }
}
