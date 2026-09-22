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

    # TorchScript represents many fixed tensor extents as aten::Int nodes. Core
    # ML Tools 9 then tries to scalarize a constant ndarray while translating
    # those nodes (network/6666 in CI). torch.export keeps the same fixed input
    # contract without emitting that TorchScript scalarization path.
    with torch.inference_mode():
        exported = torch.export.export(network, (example,), strict=True).run_decompositions({})
    print(f"Captured fixed-shape graph with torch.export ({exported.graph_module.meta.get('dialect', 'ATEN')})", flush=True)

    converted = ct.convert(
        exported,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS26,
        compute_precision=ct.transform.FP16ComputePrecision(
            op_selector=lambda operation: operation.op_type not in {"reduce_mean", "reduce_sum", "softmax"}
        ),
        skip_model_load=True,
    )

    # ExportedProgram owns its I/O names, so normalize them after conversion to
    # the stable names consumed by IOSNeuralHeadService.
    spec = converted.get_spec()
    if len(spec.description.input) != 1 or len(spec.description.output) != 1:
        raise RuntimeError("Recovered neural head must expose exactly one input and one output")
    ct.utils.rename_feature(
        spec,
        spec.description.input[0].name,
        "color",
        rename_inputs=True,
        rename_outputs=False,
    )
    ct.utils.rename_feature(
        spec,
        spec.description.output[0].name,
        "restored",
        rename_inputs=False,
        rename_outputs=True,
    )
    converted = ct.models.MLModel(
        spec,
        weights_dir=converted.weights_dir,
        skip_model_load=True,
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
