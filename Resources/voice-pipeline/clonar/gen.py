#!/usr/bin/env python3
"""Genera una muestra con un checkpoint XTTS usando la receta Máxima."""
import os, re, sys, warnings
warnings.filterwarnings("ignore")
os.environ["COQUI_TOS_AGREED"] = "1"; os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")
import torch, torchaudio
from TTS.tts.configs.xtts_config import XttsConfig
from TTS.tts.models.xtts import Xtts

def chunks(text, max_chars=200):
    parts = re.split(r"(?<=[\.\?\!])\s+", text.strip()); out = []; buf = ""
    for part in parts:
        if len(buf) + len(part) <= max_chars: buf = (buf + " " + part).strip()
        else:
            if buf: out.append(buf)
            buf = part
    if buf: out.append(buf)
    return out or [text]

project, checkpoint, text, output = sys.argv[1:5]
base = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "xtts_base")
config_path = os.path.join(os.path.dirname(checkpoint), "config.json")
if not os.path.exists(config_path): config_path = os.path.join(base, "config.json")
config = XttsConfig(); config.load_json(config_path)
model = Xtts.init_from_config(config)
model.load_checkpoint(config, checkpoint_path=checkpoint,
                      vocab_path=os.path.join(base, "vocab.json"), use_deepspeed=False)
model.cpu(); model.train(False)
refs = [line.strip() for line in open(os.path.join(project, "ref_list.txt")) if line.strip()]
gpt, speaker = model.get_conditioning_latents(audio_path=refs); pieces = []
for chunk in chunks(text):
    result = model.inference(chunk, "es", gpt, speaker, temperature=0.55,
        length_penalty=1.0, repetition_penalty=5.0, top_k=30, top_p=0.80,
        enable_text_splitting=False)
    pieces.append(torch.tensor(result["wav"]))
torchaudio.save(output, torch.cat(pieces).unsqueeze(0), 24000)
print("OK", output, flush=True)
