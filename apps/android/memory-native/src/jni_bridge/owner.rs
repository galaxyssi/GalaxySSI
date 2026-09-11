use super::{Checked, Result};
use crate::replay::ReplayIndex;
use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, AtomicI64, Ordering},
    },
};
use tokio::runtime::Runtime;

pub(super) struct Engine {
    pub index: ReplayIndex,
    pub runtime: Runtime,
    pub dimensions: usize,
}
struct Owner {
    engine: Mutex<Engine>,
    cancelled: Arc<AtomicBool>,
}
static OWNERS: OnceLock<Mutex<HashMap<i64, Arc<Owner>>>> = OnceLock::new();
static NEXT: AtomicI64 = AtomicI64::new(1);
fn registry() -> &'static Mutex<HashMap<i64, Arc<Owner>>> {
    OWNERS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(super) fn add(
    index: ReplayIndex,
    cancelled: Arc<AtomicBool>,
    dimensions: usize,
) -> Result<i64> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .build()
        .checked()?;
    let id = NEXT
        .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |n| n.checked_add(1))
        .checked()?;
    registry()
        .lock()
        .map_err(|_| "Native owner registry poisoned")?
        .insert(
            id,
            Arc::new(Owner {
                engine: Mutex::new(Engine {
                    index,
                    runtime,
                    dimensions,
                }),
                cancelled,
            }),
        );
    Ok(id)
}
pub(super) fn access<T>(id: i64, call: impl FnOnce(&mut Engine) -> Result<T>) -> Result<T> {
    let owner = registry()
        .lock()
        .map_err(|_| "Native owner registry poisoned")?
        .get(&id)
        .cloned()
        .ok_or("Native index handle is closed")?;
    let mut engine = owner
        .engine
        .lock()
        .map_err(|_| "Native index operation panicked; reopen required")?;
    if owner.cancelled.load(Ordering::Acquire) {
        return Err("Native index was cancelled".into());
    }
    call(&mut engine)
}
pub(super) fn cancel(id: i64) -> Result<()> {
    if let Some(owner) = registry()
        .lock()
        .map_err(|_| "Native owner registry poisoned")?
        .get(&id)
    {
        owner.cancelled.store(true, Ordering::Release);
    }
    Ok(())
}
pub(super) fn remove(id: i64) -> Result<()> {
    // Drop outside the registry lock; cancellation never waits on an active operation.
    let owner = registry()
        .lock()
        .map_err(|_| "Native owner registry poisoned")?
        .remove(&id);
    if let Some(owner) = owner {
        owner.cancelled.store(true, Ordering::Release);
    }
    Ok(())
}
