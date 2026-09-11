use crate::store::{Node, PackedVector, validate_vector};
use diskann::{ANNError, ANNResult};
use diskann_quantization::{
    CompressInto,
    bits::{MutBitSlice, Unsigned},
    scalar::ScalarQuantizer,
};
use zeroize::Zeroizing;

// Small vectors avoid quantizer setup. Try FP16 when SQ8 cannot meet this
// per-vector squared-L2 reconstruction bound; keep FP32 if neither codec can.
const MIN_DIMENSIONS: usize = 128;
const MAX_SQUARED_ERROR: f64 = 0.0001;

pub(super) fn node(vector: &[f32]) -> ANNResult<Node> {
    validate_vector(vector, vector.len())?;
    if vector.len() < MIN_DIMENSIONS {
        return Ok(Node::new(vector));
    }
    let maximum = vector.iter().map(|v| v.abs()).fold(0.0f32, f32::max);
    let scaled = Zeroizing::new(vector.iter().map(|v| v / maximum).collect::<Vec<_>>());
    let mut codes = Zeroizing::new(vec![0u8; vector.len()]);
    // The quantizer owns only public constants. Its borrowed compression path
    // creates no plaintext vector copies; our input/output buffers are wiped.
    let quantizer = ScalarQuantizer::new(2.0, vec![-1.0; vector.len()], None);
    let output = MutBitSlice::<8, Unsigned>::new(codes.as_mut_slice(), vector.len())
        .map_err(|_| ANNError::message("Invalid native SQ8 buffer"))?;
    quantizer
        .compress_into(scaled.as_slice(), output)
        .map_err(|_| ANNError::message("Native SQ8 compression failed"))?;
    if let Some(node) = checked_node(
        vector,
        PackedVector {
            format: 2,
            bytes: codes,
        },
    )? {
        return Ok(node);
    }
    let mut bytes = Zeroizing::new(Vec::with_capacity(vector.len() * 2));
    for value in vector {
        bytes.extend_from_slice(&half::f16::from_f32(*value).to_bits().to_le_bytes());
    }
    Ok(checked_node(vector, PackedVector { format: 3, bytes })?
        .unwrap_or_else(|| Node::new(vector)))
}

fn checked_node(vector: &[f32], packed: PackedVector) -> ANNResult<Option<Node>> {
    let decoded = decode(packed.format, &packed.bytes, vector.len())?;
    let error: f64 = vector
        .iter()
        .zip(decoded.iter())
        .map(|(a, b)| (f64::from(*a) - f64::from(*b)).powi(2))
        .sum();
    if error > MAX_SQUARED_ERROR {
        return Ok(None);
    }
    Ok(Some(Node {
        vector: decoded,
        neighbors: Zeroizing::new(Vec::new()),
        packed_vector: Some(packed),
    }))
}

pub(super) fn decode(
    format: u32,
    codes: &[u8],
    dimensions: usize,
) -> ANNResult<Zeroizing<Vec<f32>>> {
    let width = match format {
        2 => 1,
        3 => 2,
        _ => return Err(ANNError::message("Unsupported compact vector codec")),
    };
    if !(MIN_DIMENSIONS..=8192).contains(&dimensions) || codes.len() != dimensions * width {
        return Err(ANNError::message("Invalid native compact vector layout"));
    }
    // Max-absolute scaling cancels after normalization. The immutable byte codes
    // alone represent the direction; no learned codebook or per-node scale is needed.
    let mut values = Zeroizing::new(if format == 2 {
        codes
            .iter()
            .map(|code| f32::from(*code) * (2.0 / 255.0) - 1.0)
            .collect::<Vec<_>>()
    } else {
        codes
            .chunks_exact(2)
            .map(|bytes| {
                half::f16::from_bits(u16::from_le_bytes(bytes.try_into().unwrap())).to_f32()
            })
            .collect()
    });
    let norm = values
        .iter()
        .map(|v| f64::from(*v).powi(2))
        .sum::<f64>()
        .sqrt();
    if !norm.is_finite() || norm <= 0.0 {
        return Err(ANNError::message("Invalid native compact vector norm"));
    }
    values
        .iter_mut()
        .for_each(|v| *v = (f64::from(*v) / norm) as f32);
    validate_vector(&values, dimensions)?;
    Ok(values)
}
