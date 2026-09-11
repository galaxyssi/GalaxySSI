use diskann::{ANNError, ANNResult};
use zeroize::Zeroizing;

pub type Key = [u8; 32];
pub const CURSOR_KEY: &[u8] = b"c";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Event {
    pub sequence: u64,
    pub previous: u64,
    pub key: Key,
    pub revision: Key,
    pub chunks: u64,
    pub removed: bool,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Pending {
    pub event: Event,
    pub next: u64,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Checkpoint {
    pub epoch: [u8; 16],
    pub last: Option<Event>,
    pub pending: Option<Pending>,
}
impl Checkpoint {
    pub fn sequence(&self) -> u64 {
        self.last.as_ref().map_or(0, |e| e.sequence)
    }
    pub fn encode(&self) -> Zeroizing<Vec<u8>> {
        let mut out = Zeroizing::new(b"GSC1".to_vec());
        out.extend_from_slice(&self.epoch);
        out.push(u8::from(self.last.is_some()));
        if let Some(event) = &self.last {
            encode_event(&mut out, event);
        }
        out.push(u8::from(self.pending.is_some()));
        if let Some(pending) = &self.pending {
            encode_event(&mut out, &pending.event);
            out.extend_from_slice(&pending.next.to_le_bytes());
        }
        out
    }
    pub fn decode(bytes: &[u8]) -> ANNResult<Self> {
        let mut input = Reader(bytes);
        if input.bytes::<4>()? != *b"GSC1" {
            return Err(invalid());
        }
        let epoch = input.bytes()?;
        let last = if input.boolean()? {
            Some(input.event()?)
        } else {
            None
        };
        let pending = if input.boolean()? {
            Some(Pending {
                event: input.event()?,
                next: input.number()?,
            })
        } else {
            None
        };
        input.end()?;
        let result = Self {
            epoch,
            last,
            pending,
        };
        if let Some(p) = &result.pending {
            if p.event.removed || p.event.previous != result.sequence() || p.next >= p.event.chunks
            {
                return Err(invalid());
            }
        }
        Ok(result)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Provenance {
    pub key: Key,
    pub revision: Key,
    pub sequence: u64,
    pub ordinal: u64,
    pub start: u64,
    pub end: u64,
}
impl Provenance {
    pub fn encode(&self) -> Zeroizing<Vec<u8>> {
        let mut bytes = Zeroizing::new(b"GSN1".to_vec());
        bytes.extend_from_slice(&self.key);
        bytes.extend_from_slice(&self.revision);
        for number in [self.sequence, self.ordinal, self.start, self.end] {
            bytes.extend_from_slice(&number.to_le_bytes());
        }
        bytes
    }
    pub fn decode(bytes: &[u8]) -> ANNResult<Self> {
        let mut input = Reader(bytes);
        if input.bytes::<4>()? != *b"GSN1" {
            return Err(invalid());
        }
        let result = Self {
            key: input.bytes()?,
            revision: input.bytes()?,
            sequence: input.number()?,
            ordinal: input.number()?,
            start: input.number()?,
            end: input.number()?,
        };
        input.end()?;
        if result.sequence == 0 || result.start >= result.end {
            return Err(invalid());
        }
        Ok(result)
    }
}
pub(super) struct Document {
    pub revision: Key,
    pub sequence: u64,
    pub count: u64,
    pub complete: bool,
}
impl Document {
    pub fn encode(&self) -> Zeroizing<Vec<u8>> {
        let mut bytes = Zeroizing::new(b"GSD1".to_vec());
        bytes.extend_from_slice(&self.revision);
        bytes.extend_from_slice(&self.sequence.to_le_bytes());
        bytes.extend_from_slice(&self.count.to_le_bytes());
        bytes.push(u8::from(self.complete));
        bytes
    }
    pub fn decode(bytes: &[u8]) -> ANNResult<Self> {
        let mut input = Reader(bytes);
        if input.bytes::<4>()? != *b"GSD1" {
            return Err(invalid());
        }
        let result = Self {
            revision: input.bytes()?,
            sequence: input.number()?,
            count: input.number()?,
            complete: input.boolean()?,
        };
        input.end()?;
        if result.sequence == 0 {
            return Err(invalid());
        }
        Ok(result)
    }
}
pub(super) fn document_key(key: &Key) -> Vec<u8> {
    [b"d".as_slice(), key].concat()
}
pub(super) fn node_key(id: u64) -> Vec<u8> {
    [b"n".as_slice(), &id.to_le_bytes()].concat()
}
fn encode_event(out: &mut Vec<u8>, event: &Event) {
    out.extend_from_slice(&event.sequence.to_le_bytes());
    out.extend_from_slice(&event.previous.to_le_bytes());
    out.extend_from_slice(&event.key);
    out.extend_from_slice(&event.revision);
    out.extend_from_slice(&event.chunks.to_le_bytes());
    out.push(u8::from(event.removed));
}
struct Reader<'a>(&'a [u8]);
impl Reader<'_> {
    fn bytes<const N: usize>(&mut self) -> ANNResult<[u8; N]> {
        let (head, rest) = self.0.split_at_checked(N).ok_or_else(invalid)?;
        self.0 = rest;
        Ok(head.try_into().unwrap())
    }
    fn number(&mut self) -> ANNResult<u64> {
        Ok(u64::from_le_bytes(self.bytes()?))
    }
    fn boolean(&mut self) -> ANNResult<bool> {
        match self.bytes::<1>()?[0] {
            0 => Ok(false),
            1 => Ok(true),
            _ => Err(invalid()),
        }
    }
    fn event(&mut self) -> ANNResult<Event> {
        let event = Event {
            sequence: self.number()?,
            previous: self.number()?,
            key: self.bytes()?,
            revision: self.bytes()?,
            chunks: self.number()?,
            removed: self.boolean()?,
        };
        event.validate()?;
        Ok(event)
    }
    fn end(&self) -> ANNResult<()> {
        if self.0.is_empty() {
            Ok(())
        } else {
            Err(invalid())
        }
    }
}
impl Event {
    pub fn validate(&self) -> ANNResult<()> {
        if self.sequence == 0 || self.sequence <= self.previous {
            return Err(invalid());
        }
        Ok(())
    }
}
fn invalid() -> ANNError {
    ANNError::message("Invalid native replay record")
}
