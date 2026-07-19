#!/usr/bin/env python3
"""Compara cada checkpoint con voz real por d-vector y genera CSV + gráfica."""
import glob, os, sys, warnings
warnings.filterwarnings("ignore")
import numpy as np
from resemblyzer import VoiceEncoder, preprocess_wav
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
project = sys.argv[1]; encoder = VoiceEncoder(verbose=False)

def embedding(path):
    vector = encoder.embed_utterance(preprocess_wav(path))
    return vector / np.linalg.norm(vector)

clips = [line.split("|", 1) for line in open(os.path.join(project, "val_clips.txt")) if "|" in line]
real = [embedding(clip[0].strip()) for clip in clips]
checkpoints = sorted({os.path.basename(path).split("_")[1].split(".")[0]
    for path in glob.glob(os.path.join(project, "run", "**", "checkpoint_*.pth"), recursive=True)}, key=int)
rows = []
for checkpoint in checkpoints:
    values = []
    for index in range(len(clips)):
        generated = os.path.join(project, "val", f"{checkpoint}_{index}.wav")
        values.append(float(np.dot(embedding(generated), real[index])) if os.path.exists(generated) else np.nan)
    rows.append((checkpoint, values, float(np.nanmean(values))))
if not rows: raise SystemExit("sin checkpoints para comparar")
csv = os.path.join(project, "validacion.csv")
with open(csv, "w") as output:
    output.write("checkpoint," + ",".join(f"clip{i+1}" for i in range(len(clips))) + ",promedio\n")
    for checkpoint, values, average in rows:
        output.write(f"{checkpoint}," + ",".join(f"{v:.4f}" for v in values) + f",{average:.4f}\n")
winner = max(rows, key=lambda row: row[2]); xs = [int(row[0]) for row in rows]; ys = [row[2] for row in rows]
plt.figure(figsize=(9, 4.5)); plt.plot(xs, ys, "o-", lw=2, color="#5C479E")
for row in rows: plt.annotate(f"{row[2]:.3f}", (int(row[0]), row[2]), fontsize=8, ha="center", va="bottom")
plt.axvline(int(winner[0]), color="green", ls="--", label=f"Recomendado: {winner[0]} ({winner[2]:.4f})")
plt.xlabel("checkpoint (pasos)"); plt.ylabel("similitud promedio con voz real")
plt.title("Validación de identidad de voz"); plt.legend(); plt.grid(alpha=.3); plt.tight_layout()
plt.savefig(os.path.join(project, "validacion.png"), dpi=120)
print(f"OK ganador={winner[0]} score={winner[2]:.4f}", flush=True)
