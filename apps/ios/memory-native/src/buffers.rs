use crate::Result;
use std::{mem, ptr, slice};
use zeroize::{Zeroize, Zeroizing};

pub(crate) fn aligned<T>(pointer: *const T) -> bool {
    !pointer.is_null() && (pointer as usize) % mem::align_of::<T>() == 0
}

// The C caller owns valid, non-overlapping regions for the duration of each call.
pub(crate) unsafe fn input<T: Copy + Zeroize>(pointer: *const T, count: usize,
    minimum: usize, maximum: usize) -> Result<Zeroizing<Vec<T>>> {
    if !(minimum..=maximum).contains(&count) || !aligned(pointer)
        || count > (isize::MAX as usize) / mem::size_of::<T>() {
        return Err("Invalid input buffer".into());
    }
    Ok(Zeroizing::new(unsafe { slice::from_raw_parts(pointer, count) }.to_vec()))
}

pub(crate) unsafe fn floats(pointer: *const f32, count: usize, expected: usize) -> Result<Zeroizing<Vec<f32>>> {
    let values = unsafe { input(pointer, count, expected, expected) }?;
    if values.iter().any(|value| !value.is_finite()) { return Err("Non-finite vector".into()); }
    Ok(values)
}

pub(crate) struct Output {
    bytes: *mut u8,
    capacity: usize,
    written: *mut usize,
}

impl Output {
    pub(crate) unsafe fn prepare(bytes: *mut u8, capacity: usize, written: *mut usize, required: usize) -> Result<Self> {
        if !aligned(written) { return Err("Invalid output length".into()); }
        unsafe { written.write(0); }
        if !aligned(bytes) || capacity < required || capacity > isize::MAX as usize {
            return Err("Insufficient output buffer".into());
        }
        Ok(Self { bytes, capacity, written })
    }

    pub(crate) unsafe fn write(&self, data: &[u8]) -> Result<()> {
        if data.len() > self.capacity { return Err("Oversized native result".into()); }
        unsafe {
            ptr::copy_nonoverlapping(data.as_ptr(), self.bytes, data.len());
            self.written.write(data.len());
        }
        Ok(())
    }
}
