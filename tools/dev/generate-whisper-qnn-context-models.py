#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["onnx==1.18.0"]
# ///
"""Generate deterministic ONNX EPContext wrappers for Qualcomm Whisper binaries."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

import onnx
from onnx import TensorProto, helper


QNN_EP_DOMAIN = "com.microsoft"
QNN_EP_SOURCE = "QNNExecutionProvider"
QAIRT_BUILD_VERSION = "2.45.0.260326154327"


@dataclass(frozen=True)
class Profile:
    mel_bins: int
    layers: int
    heads: int
    vocabulary: int
    quantized: bool = False


PROFILES = {
    "large-v3-turbo": Profile(128, 4, 20, 51866),
    "tiny-float": Profile(80, 4, 6, 51865),
    "base-float": Profile(80, 6, 8, 51865),
    "small-w8a16": Profile(80, 12, 12, 51865, True),
    "small-float": Profile(80, 12, 12, 51865),
}


def value(name: str, data_type: int, shape: tuple[int, ...]):
    return helper.make_tensor_value_info(name, data_type, shape)


def context_model(graph_name: str, binary_name: str, inputs: list, outputs: list) -> onnx.ModelProto:
    node = helper.make_node(
        "EPContext",
        [item.name for item in inputs],
        [item.name for item in outputs],
        name=graph_name,
        domain=QNN_EP_DOMAIN,
        embed_mode=0,
        ep_cache_context=binary_name,
        ep_sdk_version=QAIRT_BUILD_VERSION,
        is_multi_soc_ep_context=0,
        partition_name=graph_name,
        source=QNN_EP_SOURCE,
    )
    graph = helper.make_graph([node], graph_name, inputs, outputs)
    model = helper.make_model(
        graph,
        producer_name="GalaxySSI",
        producer_version="0.4",
        opset_imports=[helper.make_operatorsetid("", 11), helper.make_operatorsetid(QNN_EP_DOMAIN, 1)],
    )
    model.ir_version = 10
    model.model_version = 1
    onnx.checker.check_model(model, check_custom_domain=False)
    return model


def encoder_model(profile: Profile) -> onnx.ModelProto:
    activation = TensorProto.UINT16 if profile.quantized else TensorProto.FLOAT16
    cache = TensorProto.UINT8 if profile.quantized else TensorProto.FLOAT16
    inputs = [value("input_features", activation, (1, profile.mel_bins, 3000))]
    outputs = []
    for layer in range(profile.layers):
        outputs.extend([
            value(f"k_cache_cross_{layer}", cache, (profile.heads, 1, 64, 1500)),
            value(f"v_cache_cross_{layer}", cache, (profile.heads, 1, 1500, 64)),
        ])
    return context_model("hf_whisper_encoder", "encoder.bin", inputs, outputs)


def decoder_model(profile: Profile) -> onnx.ModelProto:
    activation = TensorProto.UINT16 if profile.quantized else TensorProto.FLOAT16
    cache = TensorProto.UINT8 if profile.quantized else TensorProto.FLOAT16
    inputs = [
        value("input_ids", TensorProto.INT32, (1, 1)),
        value("attention_mask", activation, (1, 1, 1, 200)),
    ]
    for layer in range(profile.layers):
        inputs.extend([
            value(f"k_cache_self_{layer}_in", cache, (profile.heads, 1, 64, 199)),
            value(f"v_cache_self_{layer}_in", cache, (profile.heads, 1, 199, 64)),
        ])
    for layer in range(profile.layers):
        inputs.extend([
            value(f"k_cache_cross_{layer}", cache, (profile.heads, 1, 64, 1500)),
            value(f"v_cache_cross_{layer}", cache, (profile.heads, 1, 1500, 64)),
        ])
    inputs.append(value("position_ids", TensorProto.INT32, (1,)))
    outputs = [value("logits", activation, (1, profile.vocabulary, 1, 1))]
    for layer in range(profile.layers):
        outputs.extend([
            value(f"k_cache_self_{layer}_out", cache, (profile.heads, 1, 64, 199)),
            value(f"v_cache_self_{layer}_out", cache, (profile.heads, 1, 199, 64)),
        ])
    return context_model("hf_whisper_decoder", "decoder.bin", inputs, outputs)


def write_model(model: onnx.ModelProto, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(model.SerializeToString(deterministic=True))
    loaded = onnx.load(destination)
    onnx.checker.check_model(loaded, check_custom_domain=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--profile", choices=PROFILES, default="large-v3-turbo")
    args = parser.parse_args()
    profile = PROFILES[args.profile]
    write_model(encoder_model(profile), args.output / "encoder_context.onnx")
    write_model(decoder_model(profile), args.output / "decoder_context.onnx")


if __name__ == "__main__":
    main()
