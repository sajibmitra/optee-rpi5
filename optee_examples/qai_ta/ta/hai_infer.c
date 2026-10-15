/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * Fixed-point HAI inference inside the TA.
 * Features are z-scores times QAI_FP_SCALE.
 * TinyML: score = w·x + b.
 * QAI:    score = bias + Σ θ_i x_i + Σ γ_i x_i x_{i+1}.
 */
#include <tee_internal_api.h>

#include <qai_ta.h>
#include "model_hai.h"

#define HAI_S ((int64_t)QAI_FP_SCALE)

static int8_t hai_tinyml_one(const int32_t *x)
{
	int64_t acc = (int64_t)hai_tinyml_bias * HAI_S;
	uint32_t i;

	for (i = 0; i < QAI_HAI_FEAT; i++)
		acc += (int64_t)hai_tinyml_w[i] * (int64_t)x[i];
	return acc > 0 ? 1 : 0;
}

static int8_t hai_qai_one(const int32_t *x)
{
	int64_t acc = (int64_t)hai_qai_bias * HAI_S;
	uint32_t i;

	for (i = 0; i < QAI_HAI_FEAT; i++)
		acc += (int64_t)hai_qai_theta[i] * (int64_t)x[i];
	for (i = 0; i < QAI_HAI_FEAT; i++) {
		uint32_t j = (i + 1) % QAI_HAI_FEAT;
		int64_t prod = (int64_t)x[i] * (int64_t)x[j];

		acc += ((int64_t)hai_qai_gamma[i] * prod) / HAI_S;
	}
	return acc > 0 ? 1 : 0;
}

TEE_Result qai_hai_infer(uint32_t model, const int32_t *rows, uint32_t n,
			 int8_t *pred, uint32_t *elapsed_ms)
{
	uint32_t i;
	TEE_Time t0;
	TEE_Time t1;

	if (n == 0 || n > QAI_HAI_MAX_ROWS)
		return TEE_ERROR_BAD_PARAMETERS;
	if (model != QAI_HAI_MODEL_TINYML && model != QAI_HAI_MODEL_QAI)
		return TEE_ERROR_BAD_PARAMETERS;

	TEE_GetSystemTime(&t0);
	for (i = 0; i < n; i++) {
		const int32_t *x = rows + i * QAI_HAI_FEAT;

		if (model == QAI_HAI_MODEL_TINYML)
			pred[i] = hai_tinyml_one(x);
		else
			pred[i] = hai_qai_one(x);
	}
	TEE_GetSystemTime(&t1);
	{
		uint32_t sec = t1.seconds - t0.seconds;
		int32_t ms = (int32_t)t1.millis - (int32_t)t0.millis;

		if (ms < 0) {
			sec -= 1;
			ms += 1000;
		}
		*elapsed_ms = sec * 1000u + (uint32_t)ms;
	}
	return TEE_SUCCESS;
}
