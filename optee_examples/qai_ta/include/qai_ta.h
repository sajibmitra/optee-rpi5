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

#endif /* QAI_TA_H */
