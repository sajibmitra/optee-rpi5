#!/usr/bin/env python3
"""Train a compact quantum-inspired hybrid classifier and emit θ/γ params.

Simulates a hybrid quantum-classical workflow on the host (Mac/PC):
  classical features → angle-style linear terms + ZZ pairwise interactions
Then exports milli-unit integers for the OP-TEE TA inference kernel.
"""
from __future__ import annotations

import argparse
import math
import random
from pathlib import Path


FEATURE_COUNT = 4
SCALE = 1000


def make_dataset(n: int, seed: int = 7):
    rng = random.Random(seed)
    xs, ys = [], []
    # Target "quantum-like" decision boundary with pairwise terms
    true_theta = [0.28, 0.41, -0.19, 0.14]
    true_gamma = [0.012, -0.008, 0.005, -0.003]
    true_bias = -0.04
    for _ in range(n):
        x = [rng.uniform(-20, 30) for _ in range(FEATURE_COUNT)]
        score = true_bias
        score += sum(t * xi for t, xi in zip(true_theta, x))
        for i in range(FEATURE_COUNT):
            j = (i + 1) % FEATURE_COUNT
            score += true_gamma[i] * x[i] * x[j]
        y = 1 if score > 0 else 0
        xs.append(x)
        ys.append(y)
    return xs, ys, true_theta, true_gamma, true_bias


def predict_score(x, theta, gamma, bias):
    s = bias + sum(t * xi for t, xi in zip(theta, x))
    for i in range(FEATURE_COUNT):
        j = (i + 1) % FEATURE_COUNT
        s += gamma[i] * x[i] * x[j]
    return s


def train(xs, ys, lr=1e-4, epochs=1200):
    theta = [0.0] * FEATURE_COUNT
    gamma = [0.0] * FEATURE_COUNT
    bias = 0.0
    n = len(xs)
    for _ in range(epochs):
        gt = [0.0] * FEATURE_COUNT
        gg = [0.0] * FEATURE_COUNT
        gb = 0.0
        for x, y in zip(xs, ys):
            z = predict_score(x, theta, gamma, bias)
            # Softplus-ish logistic gradient
            p = 1.0 / (1.0 + math.exp(-z)) if z >= 0 else math.exp(z) / (1.0 + math.exp(z))
            err = p - y
            for i in range(FEATURE_COUNT):
                gt[i] += err * x[i]
                j = (i + 1) % FEATURE_COUNT
                gg[i] += err * x[i] * x[j]
            gb += err
        for i in range(FEATURE_COUNT):
            theta[i] -= lr * gt[i] / n
            gamma[i] -= lr * gg[i] / n
        bias -= lr * gb / n
    return theta, gamma, bias


def accuracy(xs, ys, theta, gamma, bias) -> float:
    ok = 0
    for x, y in zip(xs, ys):
        pred = 1 if predict_score(x, theta, gamma, bias) > 0 else 0
        ok += int(pred == y)
    return ok / len(ys)


def to_milli(v: float) -> int:
    return int(round(v * SCALE))


def emit_c(theta, gamma, bias) -> str:
    th = ", ".join(str(to_milli(v)) for v in theta)
    ga = ", ".join(str(to_milli(v)) for v in gamma)
    return (
        f"static const int32_t qai_theta[QAI_FEATURE_COUNT] = {{\n"
        f"\t{th}\n"
        f"}};\n"
        f"static const int32_t qai_gamma[QAI_FEATURE_COUNT] = {{\n"
        f"\t{ga}\n"
        f"}};\n"
        f"static const int32_t qai_qai_bias = {to_milli(bias)};\n"
        f"static const int32_t qai_qai_threshold = 0;\n"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=500)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args()

    xs, ys, true_theta, true_gamma, true_bias = make_dataset(args.samples, args.seed)
    theta, gamma, bias = train(xs, ys)
    acc = accuracy(xs, ys, theta, gamma, bias)
    print(f"train accuracy: {acc:.3f}")
    print(f"theta: {theta}")
    print(f"gamma: {gamma}")
    print(f"bias: {bias}")
    print(f"(oracle theta≈{true_theta}, gamma≈{true_gamma}, bias≈{true_bias})")

    demo = [10.0, 20.0, -5.0, 3.0]
    z = predict_score(demo, theta, gamma, bias)
    print(f"demo {demo} -> score={z:.3f} pred={1 if z > 0 else 0}")

    snippet = emit_c(theta, gamma, bias)
    print("\n/* paste into ta/model_params.h */")
    print(snippet)
    if args.out:
        args.out.write_text(snippet)
        print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
