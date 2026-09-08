/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * Secure-side QAI / TinyML inference kernels (integer only).
 */
#include "inference.h"
#include "model_params.h"

static int32_t abs_i32(int32_t v)
{
	return (v < 0) ? -v : v;
}

static void fill_result(struct qai_output *out, int32_t score,
			int32_t threshold, uint32_t model_id)
{
	out->score = score;
	out->prediction = (score > threshold) ? 1 : 0;
	out->confidence = abs_i32(score);
	out->model_id = model_id;
}

void qai_infer_baseline(const int32_t *x, uint32_t n, struct qai_output *out)
{
	int32_t score = qai_baseline_bias;
	uint32_t i;
	uint32_t lim = (n < QAI_FEATURE_COUNT) ? n : QAI_FEATURE_COUNT;

	for (i = 0; i < lim; i++)
		score += qai_baseline_w[i] * x[i];

	fill_result(out, score, qai_baseline_threshold, QAI_MODEL_BASELINE);
}

void qai_infer_tinyml(const int32_t *x, uint32_t n, struct qai_output *out)
{
	int64_t acc = qai_tinyml_bias;
	uint32_t i;
	uint32_t lim = (n < QAI_FEATURE_COUNT) ? n : QAI_FEATURE_COUNT;
	int32_t score;

	for (i = 0; i < lim; i++)
		acc += (int64_t)qai_tinyml_w[i] * (int64_t)x[i];

	/* Convert milli-units to integer score comparable to baseline. */
	score = (int32_t)(acc / QAI_FP_SCALE);
	fill_result(out, score, qai_tinyml_threshold, QAI_MODEL_TINYML);
}

void qai_infer_qai(const int32_t *x, uint32_t n, struct qai_output *out)
{
	int64_t acc = qai_qai_bias;
	uint32_t i;
	uint32_t lim = (n < QAI_FEATURE_COUNT) ? n : QAI_FEATURE_COUNT;
	int32_t score;

	/* Linear (angle-encoding style) term */
	for (i = 0; i < lim; i++)
		acc += (int64_t)qai_theta[i] * (int64_t)x[i];

	/* Pairwise interference / ZZ-like interaction term */
	for (i = 0; i < lim; i++) {
		uint32_t j = (i + 1) % lim;
		acc += (int64_t)qai_gamma[i] * (int64_t)x[i] * (int64_t)x[j];
	}

	score = (int32_t)(acc / QAI_FP_SCALE);
	fill_result(out, score, qai_qai_threshold, QAI_MODEL_QAI);
}

void qai_xor_crypt(uint8_t *buf, uint32_t len)
{
	uint32_t i;

	for (i = 0; i < len; i++)
		buf[i] ^= qai_prot_key[i % QAI_PROT_KEY_LEN];
}
