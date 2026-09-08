/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * QAI-OPTEE Normal World client (Phases 4–10).
 *
 * Usage:
 *   qai_host                 # baseline demo (roadmap milestone)
 *   qai_host --tinyml
 *   qai_host --qai
 *   qai_host --protected [--tinyml|--qai]
 *   qai_host --bench N
 *   qai_host --ree-compare
 *   qai_host --info
 */
#include <err.h>
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <tee_client_api.h>

#include <qai_ta.h>

/* Same key as TA model_params.h (host encrypts; TA decrypts). */
static const uint8_t g_prot_key[QAI_PROT_KEY_LEN] = {
	0x51, 0x41, 0x49, 0x2d, 0x4f, 0x50, 0x54, 0x45,
	0x45, 0x2d, 0x50, 0x49, 0x35, 0x2d, 0x4b, 0x31
};

/* Mirrored TinyML / QAI params for REE baseline timing only. */
static const int32_t ree_baseline_w[QAI_FEATURE_COUNT] = { 1, 1, 1, 1 };
static const int32_t ree_tinyml_w[QAI_FEATURE_COUNT] = { 441, 775, -300, 232 };
static const int32_t ree_tinyml_bias = 12;
static const int32_t ree_theta[QAI_FEATURE_COUNT] = { 99, 146, -64, 47 };
static const int32_t ree_gamma[QAI_FEATURE_COUNT] = { 5, -2, 2, 0 };
static const int32_t ree_qai_bias = -1;

static int64_t now_us(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
		return 0;
	return (int64_t)ts.tv_sec * 1000000LL + ts.tv_nsec / 1000LL;
}

static void xor_crypt(uint8_t *buf, uint32_t len)
{
	uint32_t i;

	for (i = 0; i < len; i++)
		buf[i] ^= g_prot_key[i % QAI_PROT_KEY_LEN];
}

static void ree_infer(uint32_t model, const int32_t *x, uint32_t n,
		      struct qai_output *out)
{
	int64_t acc = 0;
	uint32_t i;
	uint32_t lim = (n < QAI_FEATURE_COUNT) ? n : QAI_FEATURE_COUNT;
	int32_t score;

	if (model == QAI_MODEL_BASELINE) {
		for (i = 0; i < lim; i++)
			acc += (int64_t)ree_baseline_w[i] * x[i];
		score = (int32_t)acc;
	} else if (model == QAI_MODEL_TINYML) {
		acc = ree_tinyml_bias;
		for (i = 0; i < lim; i++)
			acc += (int64_t)ree_tinyml_w[i] * x[i];
		score = (int32_t)(acc / QAI_FP_SCALE);
	} else {
		acc = ree_qai_bias;
		for (i = 0; i < lim; i++)
			acc += (int64_t)ree_theta[i] * x[i];
		for (i = 0; i < lim; i++) {
			uint32_t j = (i + 1) % lim;
			acc += (int64_t)ree_gamma[i] * x[i] * x[j];
		}
		score = (int32_t)(acc / QAI_FP_SCALE);
	}

	out->score = score;
	out->prediction = (score > 0) ? 1 : 0;
	out->confidence = (score < 0) ? -score : score;
	out->model_id = model;
}

static void print_banner(void)
{
	printf("================================\n");
	printf(" QAI-OPTEE Raspberry Pi 5 Test\n");
	printf("================================\n\n");
}

static const char *model_name(uint32_t m)
{
	switch (m) {
	case QAI_MODEL_BASELINE:
		return "baseline";
	case QAI_MODEL_TINYML:
		return "tinyml";
	case QAI_MODEL_QAI:
		return "qai";
	default:
		return "unknown";
	}
}

static uint32_t cmd_for_model(uint32_t model)
{
	switch (model) {
	case QAI_MODEL_TINYML:
		return TA_QAI_CMD_INFER_TINYML;
	case QAI_MODEL_QAI:
		return TA_QAI_CMD_INFER_QAI;
	default:
		return TA_QAI_CMD_INFER_BASELINE;
	}
}

static int tee_open(TEEC_Context *ctx, TEEC_Session *sess)
{
	TEEC_Result res;
	TEEC_UUID uuid = TA_QAI_UUID;
	uint32_t err_origin;

	res = TEEC_InitializeContext(NULL, ctx);
	if (res != TEEC_SUCCESS) {
		fprintf(stderr, "TEEC_InitializeContext failed 0x%x\n", res);
		return -1;
	}

	res = TEEC_OpenSession(ctx, sess, &uuid, TEEC_LOGIN_PUBLIC, NULL, NULL,
			       &err_origin);
	if (res != TEEC_SUCCESS) {
		fprintf(stderr,
			"TEEC_OpenSession failed 0x%x origin 0x%x\n",
			res, err_origin);
		TEEC_FinalizeContext(ctx);
		return -1;
	}
	return 0;
}

static int tee_infer(TEEC_Session *sess, uint32_t model, int protected_mode,
		     const struct qai_input *in, struct qai_output *out,
		     int64_t *elapsed_us)
{
	TEEC_Operation op;
	TEEC_Result res;
	uint32_t err_origin;
	uint32_t cmd;
	struct qai_protected_input pin;
	int64_t t0, t1;

	memset(&op, 0, sizeof(op));
	memset(out, 0, sizeof(*out));

	op.paramTypes = TEEC_PARAM_TYPES(TEEC_MEMREF_TEMP_INPUT,
					 TEEC_MEMREF_TEMP_OUTPUT,
					 TEEC_NONE, TEEC_NONE);
	op.params[1].tmpref.buffer = out;
	op.params[1].tmpref.size = sizeof(*out);

	if (protected_mode) {
		memset(&pin, 0, sizeof(pin));
		pin.num_features = in->num_features;
		pin.model_id = model;
		memcpy(pin.cipher, in->features,
		       in->num_features * sizeof(int32_t));
		xor_crypt(pin.cipher, in->num_features * sizeof(int32_t));
		op.params[0].tmpref.buffer = &pin;
		op.params[0].tmpref.size = sizeof(pin);
		cmd = TA_QAI_CMD_INFER_PROTECTED;
	} else {
		op.params[0].tmpref.buffer = (void *)in;
		op.params[0].tmpref.size = sizeof(*in);
		cmd = cmd_for_model(model);
	}

	printf("Sending data to OP-TEE...\n\n");
	t0 = now_us();
	res = TEEC_InvokeCommand(sess, cmd, &op, &err_origin);
	t1 = now_us();
	if (elapsed_us)
		*elapsed_us = t1 - t0;

	if (res != TEEC_SUCCESS) {
		fprintf(stderr,
			"TEEC_InvokeCommand failed 0x%x origin 0x%x\n",
			res, err_origin);
		return -1;
	}
	return 0;
}

static int tee_info(TEEC_Session *sess, struct qai_info *info)
{
	TEEC_Operation op;
	TEEC_Result res;
	uint32_t err_origin;

	memset(&op, 0, sizeof(op));
	memset(info, 0, sizeof(*info));
	op.paramTypes = TEEC_PARAM_TYPES(TEEC_MEMREF_TEMP_OUTPUT, TEEC_NONE,
					 TEEC_NONE, TEEC_NONE);
	op.params[0].tmpref.buffer = info;
	op.params[0].tmpref.size = sizeof(*info);

	res = TEEC_InvokeCommand(sess, TA_QAI_CMD_GET_INFO, &op, &err_origin);
	if (res != TEEC_SUCCESS) {
		fprintf(stderr, "GET_INFO failed 0x%x origin 0x%x\n", res,
			err_origin);
		return -1;
	}
	return 0;
}

static void print_input(const struct qai_input *in)
{
	uint32_t i;

	printf("Input:\n  [");
	for (i = 0; i < in->num_features; i++) {
		printf("%d", in->features[i]);
		if (i + 1 < in->num_features)
			printf(", ");
	}
	printf("]\n\n");
}

static void print_result(const struct qai_output *out, int64_t us,
			 int protected_mode)
{
	printf("Prediction : %d\n", out->prediction);
	printf("Confidence : %d\n", out->confidence);
	printf("Score      : %d\n", out->score);
	printf("Model      : %s%s\n", model_name(out->model_id),
	       protected_mode ? " (protected)" : "");
	printf("\nTEE execution time : %" PRId64 " us\n", us);
}

static void usage(const char *argv0)
{
	fprintf(stderr,
		"Usage: %s [--baseline|--tinyml|--qai] [--protected]\n"
		"          [--bench N] [--ree-compare] [--info]\n",
		argv0);
}

int main(int argc, char **argv)
{
	TEEC_Context ctx;
	TEEC_Session sess;
	struct qai_input in;
	struct qai_output out;
	struct qai_info info;
	uint32_t model = QAI_MODEL_BASELINE;
	int protected_mode = 0;
	int do_bench = 0;
	int do_ree = 0;
	int do_info = 0;
	int bench_n = 100;
	int64_t elapsed = 0;
	int i;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--baseline"))
			model = QAI_MODEL_BASELINE;
		else if (!strcmp(argv[i], "--tinyml"))
			model = QAI_MODEL_TINYML;
		else if (!strcmp(argv[i], "--qai"))
			model = QAI_MODEL_QAI;
		else if (!strcmp(argv[i], "--protected"))
			protected_mode = 1;
		else if (!strcmp(argv[i], "--ree-compare"))
			do_ree = 1;
		else if (!strcmp(argv[i], "--info"))
			do_info = 1;
		else if (!strcmp(argv[i], "--bench")) {
			do_bench = 1;
			if (i + 1 < argc && argv[i + 1][0] != '-')
				bench_n = atoi(argv[++i]);
		} else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
			usage(argv[0]);
			return 0;
		} else {
			usage(argv[0]);
			return 1;
		}
	}

	memset(&in, 0, sizeof(in));
	in.num_features = QAI_FEATURE_COUNT;
	in.features[0] = 10;
	in.features[1] = 20;
	in.features[2] = -5;
	in.features[3] = 3;

	print_banner();
	print_input(&in);

	if (tee_open(&ctx, &sess) != 0)
		return 1;

	if (do_info) {
		if (tee_info(&sess, &info) == 0) {
			printf("TA version           : %u\n", info.ta_version);
			printf("Feature count        : %u\n", info.feature_count);
			printf("Baseline params      : %u bytes\n",
			       info.baseline_param_bytes);
			printf("TinyML params        : %u bytes\n",
			       info.tinyml_param_bytes);
			printf("QAI params           : %u bytes\n",
			       info.qai_param_bytes);
			printf("TA stack hint        : %u bytes\n",
			       info.stack_hint_bytes);
			printf("TA heap hint         : %u bytes\n",
			       info.heap_hint_bytes);
		}
		goto done;
	}

	if (do_bench) {
		int64_t sum = 0;
		int64_t ree_sum = 0;
		struct qai_output tmp;

		printf("Benchmark: model=%s iterations=%d\n\n",
		       model_name(model), bench_n);
		for (i = 0; i < bench_n; i++) {
			int64_t t0, t1, tus;

			if (tee_infer(&sess, model, protected_mode, &in, &tmp,
				      &tus) != 0)
				goto fail;
			sum += tus;

			t0 = now_us();
			ree_infer(model, in.features, in.num_features, &tmp);
			t1 = now_us();
			ree_sum += (t1 - t0);
		}
		printf("TEE avg inference : %" PRId64 " us\n", sum / bench_n);
		printf("REE avg inference : %" PRId64 " us\n",
		       ree_sum / bench_n);
		printf("Last prediction   : %d (conf %d)\n", tmp.prediction,
		       tmp.confidence);
		goto done;
	}

	if (do_ree) {
		int64_t t0, t1;
		struct qai_output ree_out;

		t0 = now_us();
		ree_infer(model, in.features, in.num_features, &ree_out);
		t1 = now_us();
		printf("[REE] Inference completed\n");
		printf("REE Prediction : %d\n", ree_out.prediction);
		printf("REE Confidence : %d\n", ree_out.confidence);
		printf("REE time       : %" PRId64 " us\n\n", t1 - t0);
	}

	if (tee_infer(&sess, model, protected_mode, &in, &out, &elapsed) != 0)
		goto fail;

	print_result(&out, elapsed, protected_mode);

done:
	TEEC_CloseSession(&sess);
	TEEC_FinalizeContext(&ctx);
	return 0;

fail:
	TEEC_CloseSession(&sess);
	TEEC_FinalizeContext(&ctx);
	return 1;
}
