#!/usr/bin/env python3
"""Prepare an HAI 20.07 subset for the in-TA fidelity kernel.

Paper steps used here (arXiv:2409.04935, Section IV-A):
  moving average of 60 samples, within each CSV (files are separate runs);
  low-cardinality columns replaced by their training-set frequency;
  z-score from the training files;
  16 features kept by a decision-tree Gini ranking;
  those 16 scaled to [-pi, pi] with the training min/max.

The tree is fit on a labeled slice that is not part of the scored test set.
The one-class SVM training rows are normal samples from the train CSVs only.

Writes raw float32 matrices and an int8 label file.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from sklearn.tree import DecisionTreeClassifier

WINDOW = 60
N_FEAT = 16
PI = np.pi


def load_csv(path: Path) -> tuple[np.ndarray, np.ndarray, list[str]]:
    raw = np.genfromtxt(path, delimiter=";", names=True, dtype=None, encoding="utf-8")
    names = list(raw.dtype.names)
    feat_names = [n for n in names if n not in ("time", "attack", "attack_P1", "attack_P2", "attack_P3")]
    x = np.column_stack([raw[n].astype(np.float64) for n in feat_names])
    y = raw["attack"].astype(np.int8)
    return x, y, feat_names


def moving_average(x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    c = np.cumsum(x, axis=0)
    ma = (c[WINDOW - 1 :] - np.vstack([np.zeros((1, x.shape[1])), c[: -WINDOW]])) / WINDOW
    return ma, y[WINDOW - 1 :]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hai-dir", type=Path, required=True)
    ap.add_argument("--out-dir", type=Path, required=True)
    ap.add_argument("--n-train", type=int, default=200)
    ap.add_argument("--n-test-normal", type=int, default=400)
    ap.add_argument("--n-test-attack", type=int, default=200)
    ap.add_argument("--seed", type=int, default=2409)
    args = ap.parse_args()
    rng = np.random.default_rng(args.seed)
    args.out_dir.mkdir(parents=True, exist_ok=True)

    train_x = []
    train_y = []
    test_x = []
    test_y = []
    feat_names = None
    for name in ("train1.csv.gz", "train2.csv.gz"):
        x, y, feat_names = load_csv(args.hai_dir / name)
        x, y = moving_average(x, y)
        train_x.append(x)
        train_y.append(y)
    for name in ("test1.csv.gz", "test2.csv.gz"):
        x, y, feat_names = load_csv(args.hai_dir / name)
        x, y = moving_average(x, y)
        test_x.append(x)
        test_y.append(y)
    train_x = np.vstack(train_x)
    train_y = np.concatenate(train_y)
    test_x = np.vstack(test_x)
    test_y = np.concatenate(test_y)
    assert feat_names is not None
    print(f"after_ma train={len(train_y)} test={len(test_y)} features={len(feat_names)}")
    print(f"train_attack={int(train_y.sum())} test_attack={int(test_y.sum())} test_rate={test_y.mean():.4f}")

    # Histogram encoding for low-cardinality columns, frequencies from train.
    for j in range(train_x.shape[1]):
        vals = np.unique(train_x[:, j])
        if len(vals) > 8:
            continue
        freq = {v: np.mean(train_x[:, j] == v) for v in vals}
        train_x[:, j] = np.vectorize(lambda v, f=freq: f.get(v, 0.0))(train_x[:, j])
        test_x[:, j] = np.vectorize(lambda v, f=freq: f.get(v, 0.0))(test_x[:, j])

    mu = train_x.mean(axis=0)
    sd = train_x.std(axis=0)
    sd[sd < 1e-8] = 1.0
    train_z = (train_x - mu) / sd
    test_z = (test_x - mu) / sd

    # Gini ranking on a labeled slice that will not be scored.
    atk = np.flatnonzero(test_y == 1)
    nor = np.flatnonzero(test_y == 0)
    rng.shuffle(atk)
    rng.shuffle(nor)
    n_rank = min(2000, len(atk) // 2, len(nor) // 2)
    rank_idx = np.concatenate([atk[:n_rank], nor[:n_rank]])
    held_atk = atk[n_rank:]
    held_nor = nor[n_rank:]
    tree = DecisionTreeClassifier(max_depth=8, random_state=args.seed)
    tree.fit(test_z[rank_idx], test_y[rank_idx])
    order = np.argsort(tree.feature_importances_)[::-1]
    keep = order[:N_FEAT]
    kept_names = [feat_names[i] for i in keep]
    print("kept", ",".join(kept_names))

    tr_n = np.flatnonzero(train_y == 0)
    rng.shuffle(tr_n)
    rng.shuffle(held_atk)
    rng.shuffle(held_nor)
    if args.n_train > len(tr_n) or args.n_test_attack > len(held_atk) or args.n_test_normal > len(held_nor):
        raise SystemExit("requested sample larger than remaining rows")
    tr_idx = tr_n[: args.n_train]
    te_idx = np.concatenate([held_nor[: args.n_test_normal], held_atk[: args.n_test_attack]])
    sup_nor = held_nor[args.n_test_normal : args.n_test_normal + 2000]
    sup_atk = held_atk[args.n_test_attack : args.n_test_attack + 2000]

    sel_train = train_z[tr_idx][:, keep]
    sel_test = test_z[te_idx][:, keep]
    lo = sel_train.min(axis=0)
    hi = sel_train.max(axis=0)
    span = np.maximum(hi - lo, 1e-8)
    ref = ((sel_train - lo) / span) * (2 * PI) - PI
    query = ((sel_test - lo) / span) * (2 * PI) - PI
    labels = test_y[te_idx]

    # Classical features stay z-scored (same 16 columns, same rows).
    classical_ref = sel_train.astype(np.float32)
    classical_query = sel_test.astype(np.float32)

    args.out_dir.joinpath("ref.bin").write_bytes(np.ascontiguousarray(ref, np.float32).tobytes())
    args.out_dir.joinpath("query.bin").write_bytes(np.ascontiguousarray(query, np.float32).tobytes())
    args.out_dir.joinpath("labels.bin").write_bytes(np.ascontiguousarray(labels, np.int8).tobytes())
    args.out_dir.joinpath("classical_ref.bin").write_bytes(np.ascontiguousarray(classical_ref).tobytes())
    args.out_dir.joinpath("classical_query.bin").write_bytes(np.ascontiguousarray(classical_query).tobytes())
    sup_x = np.vstack([test_z[sup_nor][:, keep], test_z[sup_atk][:, keep]])
    sup_y = np.concatenate([np.zeros(len(sup_nor), np.int8), np.ones(len(sup_atk), np.int8)])
    args.out_dir.joinpath("sup_x.bin").write_bytes(np.ascontiguousarray(sup_x, np.float32).tobytes())
    args.out_dir.joinpath("sup_y.bin").write_bytes(np.ascontiguousarray(sup_y).tobytes())
    n_qmoc = 1000
    n_cal = 400
    if n_qmoc + n_cal > len(tr_n):
        raise SystemExit("not enough normal training rows for QMOC-SVM")
    qmoc_z = train_z[tr_n[:n_qmoc]][:, keep]
    cal_z = train_z[tr_n[n_qmoc : n_qmoc + n_cal]][:, keep]
    qmoc_ref = ((qmoc_z - lo) / span) * (2 * PI) - PI
    qmoc_cal = ((cal_z - lo) / span) * (2 * PI) - PI
    if not np.allclose(qmoc_ref[: args.n_train], ref, atol=1e-5):
        raise SystemExit("QMOC landmarks do not match the fidelity reference rows")
    args.out_dir.joinpath("qmoc_ref.bin").write_bytes(np.ascontiguousarray(qmoc_ref, np.float32).tobytes())
    args.out_dir.joinpath("qmoc_cal.bin").write_bytes(np.ascontiguousarray(qmoc_cal, np.float32).tobytes())
    keep32 = order[:32]
    kept32 = [feat_names[i] for i in keep32]
    sel32_train = train_z[tr_idx][:, keep32]
    lo32 = sel32_train.min(axis=0)
    hi32 = sel32_train.max(axis=0)
    span32 = np.maximum(hi32 - lo32, 1e-8)

    def ang32(z: np.ndarray) -> np.ndarray:
        return ((z - lo32) / span32) * (2 * PI) - PI

    ref32 = ang32(sel32_train)
    query32 = ang32(test_z[te_idx][:, keep32])
    qmoc32 = ang32(train_z[tr_n[:n_qmoc]][:, keep32])
    cal32 = ang32(train_z[tr_n[n_qmoc : n_qmoc + n_cal]][:, keep32])
    if not np.allclose(ref32[:, :N_FEAT], ref, atol=1e-5):
        raise SystemExit("32-feature angles do not match the 16-feature reference")
    args.out_dir.joinpath("ref32.bin").write_bytes(np.ascontiguousarray(ref32, np.float32).tobytes())
    args.out_dir.joinpath("query32.bin").write_bytes(np.ascontiguousarray(query32, np.float32).tobytes())
    args.out_dir.joinpath("qmoc_ref32.bin").write_bytes(np.ascontiguousarray(qmoc32, np.float32).tobytes())
    args.out_dir.joinpath("qmoc_cal32.bin").write_bytes(np.ascontiguousarray(cal32, np.float32).tobytes())
    args.out_dir.joinpath("features32.txt").write_text(",".join(kept32) + "\n")
    meta = args.out_dir / "meta.txt"
    meta.write_text(
        "\n".join(
            [
                f"n_train={args.n_train}",
                f"n_test_normal={args.n_test_normal}",
                f"n_test_attack={args.n_test_attack}",
                f"n_test={len(labels)}",
                f"seed={args.seed}",
                f"features={len(feat_names)}",
                f"test_attack_rate_full={test_y.mean():.6f}",
                f"train_rows_after_ma={len(train_y)}",
                f"test_rows_after_ma={len(test_y)}",
                f"n_sup_normal={len(sup_nor)}",
                f"n_sup_attack={len(sup_atk)}",
                f"n_qmoc={n_qmoc}",
                f"n_qmoc_cal={n_cal}",
                "n_feat_16q=32",
                "kept32=" + ",".join(kept32),
                "kept=" + ",".join(kept_names),
            ]
        )
        + "\n"
    )
    print(meta.read_text())


if __name__ == "__main__":
    main()
