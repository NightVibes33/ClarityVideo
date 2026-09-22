#!/usr/bin/env python3
"""Convert DLSSMac's recovered neural head into an iOS Core ML package.

The weight file is supplied separately. This conversion does not copy the
third-party model into the source repository or modify its recovered graph.
"""

import argparse
import hashlib
from pathlib import Path

EXPECTED_SHA256 = "5a2c60e7724ffb75f8a053479f0910182128509be7f040915ff25734c270ca93"


def verify_weights(path: Path) -> None:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    if digest.hexdigest() != EXPECTED_SHA256:
        raise ValueError("The model weights do not match the verified DLSSMac release")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("weights", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--size", type=int, default=128, help="Square tile width and height, a multiple of 64")
    args = parser.parse_args()
    if args.size < 128 or args.size % 64:
        parser.error("--size must be at least 128 and divisible by 64")
    verify_weights(args.weights)

    import coremltools as ct
    import numpy as np
    import torch
    from torch import nn
    from mlxdlss import model as recovered

    class NCHWHead(nn.Module):
        def __init__(self, network):
            super().__init__()
            self.network = network

        def forward(self, value):
            return self.network(value.permute(0, 2, 3, 1)).permute(0, 3, 1, 2)

    example = torch.zeros((1, 16, args.size, args.size), dtype=torch.float32)
    network = NCHWHead(recovered.load_model(args.weights)).eval()
    with torch.inference_mode():
        traced = torch.jit.trace(network, example, strict=True)
    converted = ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS26,
        compute_precision=ct.transform.FP16ComputePrecision(
            op_selector=lambda operation: operation.op_type not in {"reduce_mean", "reduce_sum", "softmax"}
        ),
        skip_model_load=True,
        inputs=[ct.TensorType(name="color", shape=example.shape, dtype=np.float32)],
        outputs=[ct.TensorType(name="restored", dtype=np.float32)],
    )
    converted.author = "MLX-DLSS contributors; iOS conversion by ClarityVideo"
    converted.user_defined_metadata["com.mlxdlss.architecture"] = "mlxdlss.neural-rendering-transformer.v1"
    converted.user_defined_metadata["com.mlxdlss.checkpoint_sha256"] = EXPECTED_SHA256
    converted.user_defined_metadata["com.clarityvideo.tile_size"] = str(args.size)
    converted.user_defined_metadata["com.clarityvideo.platform"] = "iOS26"
    if args.destination.exists():
        raise FileExistsError(args.destination)
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    converted.save(args.destination)
    print(f"Converted {args.destination} from verified recovered weights")


if __name__ == "__main__":
    main()
