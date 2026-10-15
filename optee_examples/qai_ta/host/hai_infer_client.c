/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * qai_hai_infer model features.bin n_rows out.bin
 * features.bin: raw int32, n_rows * 16 milli-z values.
 * out.bin: raw int8 predictions.
 * TEE milliseconds printed on stderr.
 */
#include <err.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <tee_client_api.h>

#include <qai_ta.h>

#define CHUNK QAI_HAI_MAX_ROWS

static int tee_open(TEEC_Context *ctx, TEEC_Session *sess)
{
	TEEC_Result res;
	TEEC_UUID uuid = TA_QAI_UUID;
	uint32_t err_origin;

	res = TEEC_InitializeContext(NULL, ctx);
	if (res != TEEC_SUCCESS)
		return -1;
	res = TEEC_OpenSession(ctx, sess, &uuid, TEEC_LOGIN_PUBLIC, NULL, NULL,
			       &err_origin);
	if (res != TEEC_SUCCESS) {
		TEEC_FinalizeContext(ctx);
		return -1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	TEEC_Context ctx;
	TEEC_Session sess;
	uint32_t model;
	uint32_t n;
	uint32_t done = 0;
	uint64_t tee_ms = 0;
	int32_t *rows;
	int8_t *pred;
	uint8_t *inbuf;
	uint8_t *outbuf;

	uint32_t reps = 1;

	if (argc != 5 && argc != 6)
		errx(2, "Usage: %s model features.bin n_rows out.bin [reps]",
		     argv[0]);
	model = (uint32_t)strtoul(argv[1], NULL, 10);
	n = (uint32_t)strtoul(argv[3], NULL, 10);
	if (argc == 6)
		reps = (uint32_t)strtoul(argv[5], NULL, 10);
	if (reps == 0)
		errx(2, "reps must be > 0");
	rows = calloc((size_t)n * QAI_HAI_FEAT, sizeof(int32_t));
	pred = calloc(n, 1);
	inbuf = malloc(sizeof(struct qai_hai_infer_in) +
		       (size_t)CHUNK * QAI_HAI_FEAT * sizeof(int32_t));
	outbuf = malloc(sizeof(struct qai_hai_infer_out) + CHUNK);
	if (!rows || !pred || !inbuf || !outbuf)
		err(1, "alloc");
	{
		FILE *f = fopen(argv[2], "rb");

		if (!f)
			err(1, "open features");
		if (fread(rows, sizeof(int32_t), (size_t)n * QAI_HAI_FEAT, f) !=
		    (size_t)n * QAI_HAI_FEAT)
			err(1, "short features");
		fclose(f);
	}
	if (tee_open(&ctx, &sess) != 0)
		errx(1, "TEE open failed");

	while (done < n) {
		uint32_t take = n - done;
		struct qai_hai_infer_in *hdr;
		struct qai_hai_infer_out *oh;
		TEEC_Operation op;
		TEEC_Result res;
		uint32_t err_origin;

		if (take > CHUNK)
			take = CHUNK;
		hdr = (struct qai_hai_infer_in *)inbuf;
		hdr->model = model;
		hdr->n = take;
		hdr->reps = reps;
		memcpy(inbuf + sizeof(*hdr), rows + done * QAI_HAI_FEAT,
		       (size_t)take * QAI_HAI_FEAT * sizeof(int32_t));
		memset(&op, 0, sizeof(op));
		op.paramTypes = TEEC_PARAM_TYPES(TEEC_MEMREF_TEMP_INPUT,
						 TEEC_MEMREF_TEMP_OUTPUT,
						 TEEC_NONE, TEEC_NONE);
		op.params[0].tmpref.buffer = inbuf;
		op.params[0].tmpref.size =
			sizeof(*hdr) + (size_t)take * QAI_HAI_FEAT * sizeof(int32_t);
		op.params[1].tmpref.buffer = outbuf;
		op.params[1].tmpref.size = sizeof(*oh) + take;
		res = TEEC_InvokeCommand(&sess, TA_QAI_CMD_HAI_INFER, &op,
					 &err_origin);
		if (res != TEEC_SUCCESS)
			errx(1, "invoke 0x%x origin 0x%x", res, err_origin);
		oh = (struct qai_hai_infer_out *)outbuf;
		tee_ms += oh->tee_elapsed_ms;
		memcpy(pred + done, outbuf + sizeof(*oh), take);
		done += take;
	}
	{
		FILE *f = fopen(argv[4], "wb");

		if (!f)
			err(1, "open out");
		if (fwrite(pred, 1, n, f) != n)
			err(1, "write");
		fclose(f);
	}
	fprintf(stderr, "MODEL_NAME %s\nTEE_INFER_MS %llu\nN %u\nMODEL %u\nREPS %u\n",
		model == QAI_HAI_MODEL_PAIRWISE_FAKE ? "QAI-pairwise(Fake)" :
		model == QAI_HAI_MODEL_TINYML ? "TinyML" : "unknown",
		(unsigned long long)tee_ms, n, model, reps);
	TEEC_CloseSession(&sess);
	TEEC_FinalizeContext(&ctx);
	free(rows);
	free(pred);
	free(inbuf);
	free(outbuf);
	return 0;
}
