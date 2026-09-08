/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * QAI-OPTEE Trusted Application
 *
 * Sensitive model parameters and inference live here (Phases 7–8).
 */
#include <tee_internal_api.h>
#include <tee_internal_api_extensions.h>

#include <string.h>

#include <qai_ta.h>
#include "inference.h"
#include "model_params.h"

TEE_Result TA_CreateEntryPoint(void)
{
	DMSG("QAI TA create");
	return TEE_SUCCESS;
}

void TA_DestroyEntryPoint(void)
{
	DMSG("QAI TA destroy");
}

TEE_Result TA_OpenSessionEntryPoint(uint32_t param_types,
				    TEE_Param params[4],
				    void **sess_ctx)
{
	uint32_t exp = TEE_PARAM_TYPES(TEE_PARAM_TYPE_NONE,
				       TEE_PARAM_TYPE_NONE,
				       TEE_PARAM_TYPE_NONE,
				       TEE_PARAM_TYPE_NONE);

	(void)params;
	(void)sess_ctx;

	if (param_types != exp)
		return TEE_ERROR_BAD_PARAMETERS;

	IMSG("[TEE] QAI TA session opened");
	return TEE_SUCCESS;
}

void TA_CloseSessionEntryPoint(void *sess_ctx)
{
	(void)sess_ctx;
	IMSG("[TEE] QAI TA session closed");
}

static TEE_Result copy_input(TEE_Param *p, struct qai_input *in)
{
	if (p->memref.size < sizeof(struct qai_input))
		return TEE_ERROR_BAD_PARAMETERS;

	TEE_MemMove(in, p->memref.buffer, sizeof(*in));
	if (in->num_features == 0 || in->num_features > QAI_MAX_FEATURES)
		return TEE_ERROR_BAD_PARAMETERS;

	return TEE_SUCCESS;
}

static TEE_Result write_output(TEE_Param *p, const struct qai_output *out)
{
	if (p->memref.size < sizeof(*out))
		return TEE_ERROR_SHORT_BUFFER;

	TEE_MemMove(p->memref.buffer, out, sizeof(*out));
	p->memref.size = sizeof(*out);
	return TEE_SUCCESS;
}

static TEE_Result cmd_infer_plain(uint32_t param_types, TEE_Param params[4],
				  uint32_t model_id)
{
	uint32_t exp = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,
				       TEE_PARAM_TYPE_MEMREF_OUTPUT,
				       TEE_PARAM_TYPE_NONE,
				       TEE_PARAM_TYPE_NONE);
	struct qai_input in;
	struct qai_output out;
	TEE_Result res;

	if (param_types != exp)
		return TEE_ERROR_BAD_PARAMETERS;

	IMSG("[TEE] QAI inference started");
	res = copy_input(&params[0], &in);
	if (res != TEE_SUCCESS)
		return res;

	IMSG("[TEE] Input validated (%u features)", in.num_features);
	TEE_MemFill(&out, 0, sizeof(out));

	switch (model_id) {
	case QAI_MODEL_BASELINE:
		qai_infer_baseline(in.features, in.num_features, &out);
		break;
	case QAI_MODEL_TINYML:
		qai_infer_tinyml(in.features, in.num_features, &out);
		break;
	case QAI_MODEL_QAI:
		qai_infer_qai(in.features, in.num_features, &out);
		break;
	default:
		return TEE_ERROR_BAD_PARAMETERS;
	}

	IMSG("[TEE] Inference completed pred=%d conf=%d",
	     out.prediction, out.confidence);
	return write_output(&params[1], &out);
}

static TEE_Result cmd_infer_protected(uint32_t param_types, TEE_Param params[4])
{
	uint32_t exp = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,
				       TEE_PARAM_TYPE_MEMREF_OUTPUT,
				       TEE_PARAM_TYPE_NONE,
				       TEE_PARAM_TYPE_NONE);
	struct qai_protected_input pin;
	struct qai_input in;
	struct qai_output out;
	uint32_t feat_bytes;

	if (param_types != exp)
		return TEE_ERROR_BAD_PARAMETERS;

	if (params[0].memref.size < sizeof(pin))
		return TEE_ERROR_BAD_PARAMETERS;

	TEE_MemMove(&pin, params[0].memref.buffer, sizeof(pin));
	if (pin.num_features == 0 || pin.num_features > QAI_MAX_FEATURES)
		return TEE_ERROR_BAD_PARAMETERS;

	IMSG("[TEE] Protected path: decrypt + inference");
	feat_bytes = pin.num_features * sizeof(int32_t);
	qai_xor_crypt(pin.cipher, feat_bytes);

	TEE_MemFill(&in, 0, sizeof(in));
	in.num_features = pin.num_features;
	TEE_MemMove(in.features, pin.cipher, feat_bytes);

	TEE_MemFill(&out, 0, sizeof(out));
	switch (pin.model_id) {
	case QAI_MODEL_BASELINE:
		qai_infer_baseline(in.features, in.num_features, &out);
		break;
	case QAI_MODEL_TINYML:
		qai_infer_tinyml(in.features, in.num_features, &out);
		break;
	case QAI_MODEL_QAI:
		qai_infer_qai(in.features, in.num_features, &out);
		break;
	default:
		return TEE_ERROR_BAD_PARAMETERS;
	}

	/* Wipe plaintext features from stack buffer before return. */
	TEE_MemFill(&in, 0, sizeof(in));
	TEE_MemFill(&pin, 0, sizeof(pin));

	IMSG("[TEE] Protected inference completed");
	return write_output(&params[1], &out);
}

static TEE_Result cmd_get_info(uint32_t param_types, TEE_Param params[4])
{
	uint32_t exp = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_OUTPUT,
				       TEE_PARAM_TYPE_NONE,
				       TEE_PARAM_TYPE_NONE,
				       TEE_PARAM_TYPE_NONE);
	struct qai_info info;

	if (param_types != exp)
		return TEE_ERROR_BAD_PARAMETERS;
	if (params[0].memref.size < sizeof(info))
		return TEE_ERROR_SHORT_BUFFER;

	TEE_MemFill(&info, 0, sizeof(info));
	info.ta_version = 1;
	info.feature_count = QAI_FEATURE_COUNT;
	info.baseline_param_bytes =
		sizeof(qai_baseline_w) + sizeof(qai_baseline_bias);
	info.tinyml_param_bytes =
		sizeof(qai_tinyml_w) + sizeof(qai_tinyml_bias);
	info.qai_param_bytes = sizeof(qai_theta) + sizeof(qai_gamma) +
			       sizeof(qai_qai_bias);
	info.stack_hint_bytes = 4 * 1024;
	info.heap_hint_bytes = 32 * 1024;

	TEE_MemMove(params[0].memref.buffer, &info, sizeof(info));
	params[0].memref.size = sizeof(info);
	return TEE_SUCCESS;
}

TEE_Result TA_InvokeCommandEntryPoint(void *sess_ctx, uint32_t cmd_id,
				      uint32_t param_types, TEE_Param params[4])
{
	(void)sess_ctx;

	switch (cmd_id) {
	case TA_QAI_CMD_INFER_BASELINE:
		return cmd_infer_plain(param_types, params, QAI_MODEL_BASELINE);
	case TA_QAI_CMD_INFER_TINYML:
		return cmd_infer_plain(param_types, params, QAI_MODEL_TINYML);
	case TA_QAI_CMD_INFER_QAI:
		return cmd_infer_plain(param_types, params, QAI_MODEL_QAI);
	case TA_QAI_CMD_INFER_PROTECTED:
		return cmd_infer_protected(param_types, params);
	case TA_QAI_CMD_GET_INFO:
		return cmd_get_info(param_types, params);
	default:
		return TEE_ERROR_BAD_PARAMETERS;
	}
}
