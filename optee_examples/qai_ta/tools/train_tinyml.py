#!/usr/bin/env python3
"""Train a tiny logistic regression and emit TA model_params snippets.

Pure Python (no numpy/sklearn) so it runs on any host / Mac / Pi.
"""
from __future__ import annotations

import argparse
import math
import random
from pathlib import Path


FEATURE_COUNT = 4
SCALE = 1000


def make_dataset(n: int, seed: int = 42):
    rng = random.Random(seed)
    xs, ys = [], []
    for _ in range(n):
        x = [rng.uniform(-20, 30) for _ in range(FEATURE_COUNT)]
        # Separable-ish rule used as ground truth
        score = 0.3 * x[0] + 0.5 * x[1] - 0.2 * x[2] + 0.15 * x[3] - 0.05
        y = 1 if score > 0 else 0
        xs.append(x)
        ys.append(y)
    return xs, ys


def sigmoid(z: float) -> float:
    if z >= 0:
        ez = math.exp(-z)
        return 1.0 / (1.0 + ez)
    ez = math.exp(z)
    return ez / (1.0 + ez)


def train(xs, ys, lr=0.01, epochs=800):
    w = [0.0] * FEATURE_COUNT
    b = 0.0
    n = len(xs)
    for _ in range(epochs):
        gw = [0.0] * FEATURE_COUNT
        gb = 0.0
        for x, y in zip(xs, ys):
            z = b + sum(wi * xi for wi, xi in zip(w, x))
            p = sigmoid(z)
            err = p - y
            for i in range(FEATURE_COUNT):
                gw[i] += err * x[i]
            gb += err
        for i in range(FEATURE_COUNT):
            w[i] -= lr * gw[i] / n
        b -= lr * gb / n
    return w, b


def accuracy(xs, ys, w, b) -> float:
    ok = 0
    for x, y in zip(xs, ys):
        z = b + sum(wi * xi for wi, xi in zip(w, x))
        pred = 1 if z > 0 else 0
        ok += int(pred == y)
    return ok / len(ys)


def to_milli(v: float) -> int:
    return int(round(v * SCALE))


def emit_c(w, b) -> str:
    ws = ", ".join(str(to_milli(v)) for v in w)
    return (
        f"static const int32_t qai_tinyml_w[QAI_FEATURE_COUNT] = {{\n"
        f"\t{ws}\n"
        f"}};\n"
        f"static const int32_t qai_tinyml_bias = {to_milli(b)};\n"
        f"static const int32_t qai_tinyml_threshold = 0;\n"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=400)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args()

    xs, ys = make_dataset(args.samples, args.seed)
    w, b = train(xs, ys)
    acc = accuracy(xs, ys, w, b)
    print(f"train accuracy: {acc:.3f}")
    print(f"weights: {w}")
    print(f"bias: {b}")

    demo = [10, 20, -5, 3]
    z = b + sum(wi * xi for wi, xi in zip(w, demo))
    print(f"demo {demo} -> score={z:.3f} pred={1 if z > 0 else 0}")

    snippet = emit_c(w, b)
    print("\n/* paste into ta/model_params.h */")
    print(snippet)
    if args.out:
        args.out.write_text(snippet)
        print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
