/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef QAI_INFERENCE_H
#define QAI_INFERENCE_H

#include <stdint.h>
#include <qai_ta.h>

void qai_infer_baseline(const int32_t *x, uint32_t n,
			struct qai_output *out);
void qai_infer_tinyml(const int32_t *x, uint32_t n,
		      struct qai_output *out);
void qai_infer_qai(const int32_t *x, uint32_t n,
		   struct qai_output *out);
void qai_xor_crypt(uint8_t *buf, uint32_t len);

#endif /* QAI_INFERENCE_H */
