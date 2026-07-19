#!/usr/bin/env python3
"""Extrae corpus, patrones y una persona portable sin depender de Hermes ni de una IA."""
import collections, os, re, sys

meta, out = sys.argv[1], sys.argv[2]
name = sys.argv[3] if len(sys.argv) > 3 else "esta persona"
os.makedirs(out, exist_ok=True)
stop = set("de la que el en y a los las un una por con no se su al lo como mas pero sus le ya o este si porque esta entre cuando muy sin sobre tambien me hasta hay donde quien desde todo nos ni contra ese eso mi que te para es del unos unas tu mis".split())
affection = ["mijito", "mijo", "mija", "hijito", "hijo", "hija", "ñaño", "ñaña",
             "ñañito", "ñañita", "amor", "corazon", "corazón", "mi vida", "vida",
             "bendicion", "bendición", "diosito", "dios", "mi amor", "cariño",
             "reina", "rey", "gordito", "gordita", "viejito", "viejita", "nene", "nena"]
lines = []
for line in open(meta, encoding="utf-8"):
    if "|" not in line:
        continue
    text = re.sub(r"\s+", " ", line.split("|", 1)[1].strip())
    if len(text) >= 3:
        lines.append(text)
seen = set()
unique = [text for text in lines if not (text.lower() in seen or seen.add(text.lower()))]

def words(text):
    return re.findall(r"[a-záéíóúñü]+", text.lower())

def ngrams(size):
    counter = collections.Counter()
    for text in unique:
        tokens = words(text)
        for index in range(len(tokens) - size + 1):
            counter[" ".join(tokens[index:index + size])] += 1
    return counter

def top(counter, count=12, with_counts=False):
    if with_counts:
        return ", ".join(f"{key} ({value})" for key, value in counter.most_common(count))
    return ", ".join(key for key, _ in counter.most_common(count))

all_words = [word for text in unique for word in words(text)]
frequent = collections.Counter(w for w in all_words if w not in stop and len(w) > 2)
opens = collections.Counter(" ".join(words(text)[:2]) for text in unique if words(text))
closes = collections.Counter(" ".join(words(text)[-2:]) for text in unique if len(words(text)) >= 2)
bigrams, trigrams = ngrams(2), ngrams(3)
low = " \n".join(unique).lower()
caring = collections.Counter({term: low.count(term) for term in affection if low.count(term)})

open(os.path.join(out, "persona_corpus.txt"), "w", encoding="utf-8").write("\n".join(unique))
skill = f"""# Forma de hablar de {name}

Redacta en primera persona conservando la forma REAL de hablar de {name}. Sé natural,
breve y coherente. No inventes biografía, recuerdos, apodos ni muletillas ausentes.

- Palabras características: {top(frequent, 20) or 'sin datos suficientes'}.
- Inicios observados: {top(opens) or 'sin patrón claro'}.
- Cierres observados: {top(closes) or 'sin patrón claro'}.
- Expresiones frecuentes: {top(bigrams, 15) or 'sin patrón claro'}.
- Apodos y cariños: {top(caring) or 'ninguno detectado'}.

Ejemplos reales de ritmo y vocabulario:
""" + "\n".join(f"- {text}" for text in unique[:40])
open(os.path.join(out, "persona_SKILL.md"), "w", encoding="utf-8").write(skill)

# Se conserva también el análisis completo y el mismo encargo profesional que usaba el
# flujo histórico. El usuario puede revisarlo o pasarlo a cualquier IA configurada.
prompt = f"""# PROMPT — mejorar la forma de hablar de {name}

Analiza estas frases REALES y mejora el documento persona_SKILL.md para capturar cómo
habla {name}. Sé fiel a los datos y no inventes rasgos que no aparezcan.

Datos automáticos ({len(unique)} frases):
- Palabras: {top(frequent, 20, True)}
- Inicios: {top(opens, 12, True)}
- Cierres: {top(closes, 12, True)}
- Expresiones de 2 palabras: {top(bigrams, 15, True)}
- Expresiones de 3 palabras: {top(trigrams, 12, True)}
- Apodos y cariños: {top(caring, 15, True) or 'ninguno detectado'}

Entrega tono, registro, saludos, despedidas, muletillas, estructura de frases, un system
prompt listo para usar y cinco ejemplos nuevos. Usa SOLO rasgos presentes en estos datos:
""" + "\n".join(f"- {text}" for text in unique[:400])
open(os.path.join(out, "persona_PROMPT.md"), "w", encoding="utf-8").write(prompt)
print(f"OK {len(unique)} frases -> corpus + persona_SKILL.md + persona_PROMPT.md", flush=True)
