use super::{Checked, Result};
use jni::{
    JNIEnv,
    objects::{JByteArray, JFloatArray, JLongArray},
    sys::jbyteArray,
};
use zeroize::Zeroizing;

pub(super) fn bytes(
    env: &JNIEnv,
    array: &JByteArray,
    min: usize,
    max: usize,
) -> Result<Zeroizing<Vec<u8>>> {
    let n = env.get_array_length(array).checked()? as usize;
    if n < min || n > max {
        return Err("Invalid native byte array size".into());
    }
    env.convert_byte_array(array).checked().map(Zeroizing::new)
}
pub(super) fn floats(
    env: &JNIEnv,
    array: &JFloatArray,
    size: usize,
) -> Result<Zeroizing<Vec<f32>>> {
    if size > 64 * 8192 || env.get_array_length(array).checked()? as usize != size {
        return Err("Invalid native vector array size".into());
    }
    let mut values = Zeroizing::new(vec![0f32; size]);
    env.get_float_array_region(array, 0, &mut values)
        .checked()?;
    Ok(values)
}
pub(super) fn longs(
    env: &JNIEnv,
    array: &JLongArray,
    min: usize,
    max: usize,
) -> Result<Zeroizing<Vec<i64>>> {
    let n = env.get_array_length(array).checked()? as usize;
    if n < min || n > max {
        return Err("Invalid native metadata array size".into());
    }
    let mut values = Zeroizing::new(vec![0i64; n]);
    env.get_long_array_region(array, 0, &mut values).checked()?;
    Ok(values)
}
pub(super) fn output(env: &JNIEnv, bytes: &[u8]) -> Result<jbyteArray> {
    if bytes.len() > 8 + 256 * 104 {
        return Err("Native result exceeds bounded layout".into());
    }
    Ok(env.byte_array_from_slice(bytes).checked()?.into_raw())
}
