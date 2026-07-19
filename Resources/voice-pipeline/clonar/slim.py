#!/usr/bin/env python3
"""Reduce un checkpoint de entrenamiento a un paquete solo de inferencia."""
import glob, os, sys, torch
source, outdir = sys.argv[1], sys.argv[2]; os.makedirs(outdir, exist_ok=True)
checkpoints = glob.glob(os.path.join(source, "**", "checkpoint_*.pth"), recursive=True) \
    if os.path.isdir(source) else [source]
for checkpoint in sorted(checkpoints):
    data = torch.load(checkpoint, map_location="cpu", weights_only=False)
    slim = {"model": data["model"]} if isinstance(data, dict) and "model" in data else data
    output = os.path.join(outdir, os.path.basename(checkpoint).replace(".pth", "_slim.pth"))
    torch.save(slim, output); print("OK", output, flush=True)
