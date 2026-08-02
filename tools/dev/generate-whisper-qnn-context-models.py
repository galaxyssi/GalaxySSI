#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["onnx==1.18.0"]
# ///
"""Generate deterministic ONNX EPContext wrappers for Qualcomm Whisper binaries."""

from __future__ import annotations

import argparse
from pathlib import Path

import onnx
from onnx import TensorProto, helper


QNN_EP_DOMAIN = "com.microsoft"
QNN_EP_SOURCE = "QNNExecutionProvider"
QAIRT_BUILD_VERSION = "2.45.0.260326154327"


def value(name: str, data_type: int, shape: tuple[int, ...]):
    return helper.make_tensor_value_info(name, data_type, shape)


def context_model(
    graph_name: str,
    binary_name: str,
    inputs: list,
    outputs: list,
) -> onnx.ModelProto:
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
        producer_name="SignalASI",
        producer_version="0.3",
        opset_imports=[
            helper.make_operatorsetid("", 11),
            helper.make_operatorsetid(QNN_EP_DOMAIN, 1),
        ],
    )
    model.ir_version = 10
    model.model_version = 1
    onnx.checker.check_model(model, check_custom_domain=False)
    return model


def encoder_model() -> onnx.ModelProto:
    inputs = [value("input_features", TensorProto.FLOAT16, (1, 128, 3000))]
    outputs = []
    for layer in range(4):
        outputs.extend(
            [
                value(f"k_cache_cross_{layer}", TensorProto.FLOAT16, (20, 1, 64, 1500)),
                value(f"v_cache_cross_{layer}", TensorProto.FLOAT16, (20, 1, 1500, 64)),
            ]
        )
    return context_model("hf_whisper_encoder", "encoder.bin", inputs, outputs)


def decoder_model() -> onnx.ModelProto:
    inputs = [
        value("input_ids", TensorProto.INT32, (1, 1)),
        value("attention_mask", TensorProto.FLOAT16, (1, 1, 1, 200)),
    ]
    for layer in range(4):
        inputs.extend(
            [
                value(f"k_cache_self_{layer}_in", TensorProto.FLOAT16, (20, 1, 64, 199)),
                value(f"v_cache_self_{layer}_in", TensorProto.FLOAT16, (20, 1, 199, 64)),
            ]
        )
    for layer in range(4):
        inputs.extend(
            [
                value(f"k_cache_cross_{layer}", TensorProto.FLOAT16, (20, 1, 64, 1500)),
                value(f"v_cache_cross_{layer}", TensorProto.FLOAT16, (20, 1, 1500, 64)),
            ]
        )
    inputs.append(value("position_ids", TensorProto.INT32, (1,)))

    outputs = [value("logits", TensorProto.FLOAT16, (1, 51866, 1, 1))]
    for layer in range(4):
        outputs.extend(
            [
                value(f"k_cache_self_{layer}_out", TensorProto.FLOAT16, (20, 1, 64, 199)),
                value(f"v_cache_self_{layer}_out", TensorProto.FLOAT16, (20, 1, 199, 64)),
            ]
        )
    return context_model("hf_whisper_decoder", "decoder.bin", inputs, outputs)


def write_model(model: onnx.ModelProto, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(model.SerializeToString(deterministic=True))
    loaded = onnx.load(destination)
    onnx.checker.check_model(loaded, check_custom_domain=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    write_model(encoder_model(), args.output / "encoder_context.onnx")
    write_model(decoder_model(), args.output / "decoder_context.onnx")


if __name__ == "__main__":
    main()
