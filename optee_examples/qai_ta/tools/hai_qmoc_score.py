#!/usr/bin/env python3
"""Fit QMOC-SVM on TA kernel matrices and print the test scores.

Bandwidth and nu are chosen before the test labels are read.
Calibration rows are normal training rows that are not landmarks.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, precision_score, recall_score
from sklearn.svm import OneClassSVM

TARGET_FAR = 0.05
NUS = (0.01, 0.02, 0.05, 0.10, 0.20)
SCALES = (1.0, 0.5, 0.25, 0.20, 0.18, 0.15, 0.1, 0.05, 0.02)
TARGET_FID = 0.30


def offdiag_fidelity(k: np.ndarray) -> np.ndarray:
    fid = np.log(np.clip(k, 1e-12, None))
    mask = ~np.eye(k.shape[0], dtype=bool)
    return fid[mask]


def choose_scale(medians: dict[float, float]) -> float:
    inside = {s: m for s, m in medians.items() if 0.10 <= m <= 0.50}
    pool = inside or medians
    return min(pool, key=lambda s: (abs(pool[s] - TARGET_FID), -s))


def sym_gram(k: np.ndarray) -> np.ndarray:
    g = 0.5 * (k + k.T)
    np.fill_diagonal(g, math.e)
    return g


def metrics(y: np.ndarray, pred_attack: np.ndarray) -> str:
    cm = confusion_matrix(y, pred_attack, labels=[0, 1])
    return (
        f"acc={accuracy_score(y, pred_attack):.4f} "
        f"prec={precision_score(y, pred_attack, zero_division=0):.4f} "
        f"rec={recall_score(y, pred_attack, zero_division=0):.4f} "
        f"f1={f1_score(y, pred_attack, zero_division=0):.4f} "
        f"cm={cm.tolist()}"
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", type=Path, default=Path("/tmp/hai-tee"))
    ap.add_argument("--choose-scale", action="store_true")
    ap.add_argument("--score", action="store_true")
    args = ap.parse_args()
    data = args.data

    if args.choose_scale:
        medians = {}
        for scale in SCALES:
            k = np.fromfile(data / f"bw_{scale:.2f}.bin", np.float32)
            n = int(math.sqrt(k.size))
            k = k.reshape(n, n)
            fid = offdiag_fidelity(k)
            diag = float(np.median(np.log(np.clip(np.diag(k), 1e-12, None))))
            medians[scale] = float(np.median(fid))
            print(
                f"scale={scale:.2f} median_fidelity={medians[scale]:.4f} "
                f"std={float(fid.std()):.4f} diag_fid={diag:.4f}"
            )
        scale = choose_scale(medians)
        print(f"CHOSEN_SCALE {scale:.2f}")
        ref = np.fromfile(data / "qmoc_ref.bin", np.float32).reshape(-1, 16) * np.float32(scale)
        cal = np.fromfile(data / "qmoc_cal.bin", np.float32).reshape(-1, 16) * np.float32(scale)
        qry = np.fromfile(data / "query.bin", np.float32).reshape(-1, 16) * np.float32(scale)
        (data / "qmoc_ref_s.bin").write_bytes(np.ascontiguousarray(ref).tobytes())
        (data / "qmoc_cal_s.bin").write_bytes(np.ascontiguousarray(cal).tobytes())
        (data / "qmoc_query_s.bin").write_bytes(np.ascontiguousarray(qry).tobytes())
        print(f"wrote scaled matrices ref={len(ref)} cal={len(cal)} query={len(qry)}")
        return

    if not args.score:
        raise SystemExit("pass --choose-scale or --score")

    gram = sym_gram(np.fromfile(data / "qmoc_gram.bin", np.float32).reshape(1000, 1000))
    kcal = np.fromfile(data / "qmoc_kcal.bin", np.float32).reshape(-1, 1000)
    ktest = np.fromfile(data / "qmoc_ktest.bin", np.float32).reshape(-1, 1000)
    y = np.fromfile(data / "labels.bin", np.int8)
    chosen = None
    best = None
    for nu in NUS:
        clf = OneClassSVM(kernel="precomputed", nu=nu)
        clf.fit(gram)
        cal_attack = clf.predict(kcal) == -1
        far = float(cal_attack.mean())
        n_sv = int(np.sum(np.abs(clf.dual_coef_) > 0))
        print(f"nu={nu:.2f} cal_far={far:.4f} support_vectors={n_sv}")
        gap = abs(far - TARGET_FAR)
        if best is None or gap < best[0] or (gap == best[0] and nu < best[1]):
            best = (gap, nu, clf)
            chosen = (nu, far, n_sv, clf)
    assert chosen is not None
    nu, far, n_sv, clf = chosen
    print(f"CHOSEN_NU {nu:.2f} CAL_FAR {far:.4f} SV {n_sv}")
    pred = (clf.predict(ktest) == -1).astype(np.int8)
    print("TEST", metrics(y, pred))
    pred.tofile(data / "qmoc_pred.bin")


if __name__ == "__main__":
    main()
