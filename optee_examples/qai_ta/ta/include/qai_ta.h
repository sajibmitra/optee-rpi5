/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * QAI-OPTEE Trusted Application public interface (REE + TEE).
 */
#ifndef QAI_TA_H
#define QAI_TA_H

#include <stdint.h>

/*
 * UUID: 24173bc2-5143-4d91-92c5-ffae31dc618d
 */
#define TA_QAI_UUID \
	{ 0x24173bc2, 0x5143, 0x4d91, \
		{ 0x92, 0xc5, 0xff, 0xae, 0x31, 0xdc, 0x61, 0x8d } }

/* Command IDs */
#define TA_QAI_CMD_INFER_BASELINE	0 /* Phase 2–4: weighted C model */
#define TA_QAI_CMD_INFER_TINYML		1 /* Phase 5/7: logistic TinyML */
#define TA_QAI_CMD_INFER_QAI		2 /* Phase 6/9: quantum-inspired */
#define TA_QAI_CMD_INFER_PROTECTED	3 /* Phase 8: decrypt + infer */
#define TA_QAI_CMD_GET_INFO		4 /* Model / TA metadata */
#define TA_QAI_CMD_BENCH_FIDELITY	5 /* 8-qubit fidelity kernel, timed in TA */
#define TA_QAI_CMD_KERNEL_BLOCK		6 /* fidelity rows on caller vectors */
#define TA_QAI_CMD_HAI_INFER		7 /* HAI TinyML or QAI, fixed-point */

#define QAI_MAX_FEATURES		16
#define QAI_FEATURE_COUNT		4
#define QAI_PROT_KEY_LEN		16

/* Fixed-point scale used by TinyML / QAI weights (milli-units). */
#define QAI_FP_SCALE			1000

enum qai_model_id {
	QAI_MODEL_BASELINE = 0,
	QAI_MODEL_TINYML = 1,
	QAI_MODEL_QAI = 2,
};

struct qai_input {
	uint32_t num_features;
	int32_t features[QAI_MAX_FEATURES];
};

/* Encrypted feature blob for protected inference (XOR with TA key). */
struct qai_protected_input {
	uint32_t num_features;
	uint32_t model_id; /* enum qai_model_id */
	uint8_t cipher[QAI_MAX_FEATURES * sizeof(int32_t)];
};

struct qai_output {
	int32_t prediction;
	int32_t confidence; /* absolute score (baseline demo: 28) */
	int32_t score;      /* raw model score before threshold */
	uint32_t model_id;
};

struct qai_info {
	uint32_t ta_version;
	uint32_t feature_count;
	uint32_t baseline_param_bytes;
	uint32_t tinyml_param_bytes;
	uint32_t qai_param_bytes;
	uint32_t stack_hint_bytes;
	uint32_t heap_hint_bytes;
};

/* Filled by TA_QAI_CMD_BENCH_FIDELITY. Clock is TEE_GetSystemTime. */
struct qai_fidelity_bench {
	uint32_t evals;
	uint32_t tee_elapsed_ms;
	int64_t self_exp_micro;  /* exp(|<0|U(x)^dag U(x)|0>|^2) * 1e6 */
	int64_t batch_sum_micro; /* sum of exp(K) over evals, * 1e6 */
};

/* TA_QAI_CMD_KERNEL_BLOCK input memref:
 *   struct qai_kernel_block_in, then float ref[n_ref * 16], then
 *   float query[n_query * 16], features already in [-pi, pi].
 * Output memref:
 *   struct qai_kernel_block_out, then float expK[n_query * n_ref]
 *   in query-major order.
 */
#define QAI_KERNEL_FEAT		16
#define QAI_KERNEL_MAX_PAIRS	32

struct qai_kernel_block_in {
	uint32_t n_ref;
	uint32_t n_query;
};

struct qai_kernel_block_out {
	uint32_t tee_elapsed_ms;
	uint32_t n_out;
};

/* TA_QAI_CMD_HAI_INFER.
 * model 0 = logistic TinyML, model 1 = quantum-inspired QAI.
 * Input: header, then int32 milli-z features[n * 16].
 * Output: header, then int8 predictions[n] (1 = attack).
 */
#define QAI_HAI_FEAT		16
#define QAI_HAI_MAX_ROWS	32
#define QAI_HAI_MODEL_TINYML	0
#define QAI_HAI_MODEL_QAI	1

struct qai_hai_infer_in {
	uint32_t model;
	uint32_t n;
	uint32_t reps;
};

struct qai_hai_infer_out {
	uint32_t tee_elapsed_ms;
	uint32_t n;
};

#endif /* QAI_TA_H */
