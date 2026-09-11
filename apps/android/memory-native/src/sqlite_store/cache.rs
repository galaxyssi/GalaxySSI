use crate::store::{MAX_NEIGHBORS, Node};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct NodeCacheStats {
    pub hits: u64,
    pub misses: u64,
    pub slots: usize,
    pub occupied: usize,
    /// Conservative payload/slot accounting, not allocator or whole-process RSS.
    pub reserved_bytes: usize,
}

/// A direct-mapped, transaction-local cache. Collisions only cause rereads.
/// Node owns Zeroizing vectors/edges, so replacement and transaction exit wipe data.
pub(super) struct NodeCache {
    slots: Vec<Option<(u64, Node)>>,
    stats: NodeCacheStats,
}
impl NodeCache {
    pub fn new(bytes: usize, dimensions: usize) -> Self {
        let entry_bytes = std::mem::size_of::<Option<(u64, Node)>>()
            + dimensions * std::mem::size_of::<f32>()
            + MAX_NEIGHBORS * std::mem::size_of::<u64>();
        let count = bytes / entry_bytes;
        Self {
            slots: std::iter::repeat_with(|| None).take(count).collect(),
            stats: NodeCacheStats {
                slots: count,
                reserved_bytes: count * entry_bytes,
                ..NodeCacheStats::default()
            },
        }
    }
    fn slot(&self, id: u64) -> usize {
        // IDs are distributed even when the source assigns sequential node IDs.
        let mut x = id.wrapping_add(0x9e3779b97f4a7c15);
        x = (x ^ (x >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        x = (x ^ (x >> 27)).wrapping_mul(0x94d049bb133111eb);
        ((x ^ (x >> 31)) % self.slots.len() as u64) as usize
    }
    pub fn get(&mut self, id: u64) -> Option<Node> {
        let hit = if self.slots.is_empty() {
            None
        } else {
            self.slots[self.slot(id)]
                .as_ref()
                .filter(|(key, _)| *key == id)
                .map(|(_, node)| node.clone())
        };
        if hit.is_some() {
            self.stats.hits += 1;
        } else {
            self.stats.misses += 1;
        }
        hit
    }
    pub fn insert(&mut self, id: u64, node: &Node) {
        if self.slots.is_empty() {
            return;
        }
        let slot = self.slot(id);
        if self.slots[slot].is_none() {
            self.stats.occupied += 1;
        }
        self.slots[slot] = Some((id, node.clone()));
    }
    pub fn stats(&self) -> NodeCacheStats {
        self.stats
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn cache_is_bounded_and_collisions_never_change_identity() {
        let mut cache = NodeCache::new(4096, 512);
        assert_eq!(cache.stats().slots, 1);
        let node = Node::new(&[1.0]);
        cache.insert(1, &node);
        assert!(cache.get(1).is_some());
        cache.insert(2, &node);
        assert!(cache.get(1).is_none());
        assert!(cache.get(2).is_some());
        assert_eq!(cache.stats().occupied, 1);
        assert!(cache.stats().reserved_bytes <= 4096);
    }
    #[test]
    fn tiny_budgets_do_not_force_an_allocation() {
        let mut cache = NodeCache::new(1, 512);
        cache.insert(1, &Node::new(&[1.0]));
        assert!(cache.get(1).is_none());
        assert_eq!(cache.stats().reserved_bytes, 0);
    }
}
