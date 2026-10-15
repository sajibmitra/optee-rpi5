/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * Ask the QAI TA to evaluate exp(fidelity) between HAI feature rows.
 *
 *   qai_hai_kernel ref.bin n_ref query.bin n_query out.bin
 *
 * Each *.bin is raw float32, row-major, 16 features per row.
 * out.bin is raw float32, shape (n_query, n_ref), query-major.
 * TEE milliseconds are printed on stderr.
 */
#include <err.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <tee_client_api.h>

#include <qai_ta.h>

#define FEAT QAI_KERNEL_FEAT
#define CHUNK 32

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

static int read_matrix(const char *path, uint32_t rows, float *dst)
{
	FILE *f = fopen(path, "rb");
	size_t n;

	if (!f)
		return -1;
	n = fread(dst, sizeof(float), (size_t)rows * FEAT, f);
	fclose(f);
	return n == (size_t)rows * FEAT ? 0 : -1;
}

int main(int argc, char **argv)
{
	TEEC_Context ctx;
	TEEC_Session sess;
	uint32_t n_ref;
	uint32_t n_query;
	uint32_t q;
	uint32_t r0;
	uint64_t tee_ms = 0;
	uint64_t calls = 0;
	float *ref;
	float *query;
	float *out;
	uint8_t *inbuf;
	uint8_t *outbuf;
	size_t in_cap;
	size_t out_cap;

	if (argc != 6) {
		fprintf(stderr,
			"Usage: %s ref.bin n_ref query.bin n_query out.bin\n",
			argv[0]);
		return 2;
	}
	n_ref = (uint32_t)strtoul(argv[2], NULL, 10);
	n_query = (uint32_t)strtoul(argv[4], NULL, 10);
	if (n_ref == 0 || n_query == 0 || n_ref > 100000 || n_query > 100000)
		errx(1, "bad dimensions");

	ref = calloc((size_t)n_ref * FEAT, sizeof(float));
	query = calloc((size_t)n_query * FEAT, sizeof(float));
	out = calloc((size_t)n_query * n_ref, sizeof(float));
	in_cap = sizeof(struct qai_kernel_block_in) +
		 (size_t)(CHUNK + 1) * FEAT * sizeof(float);
	out_cap = sizeof(struct qai_kernel_block_out) +
		  (size_t)CHUNK * sizeof(float);
	inbuf = malloc(in_cap);
	outbuf = malloc(out_cap);
	if (!ref || !query || !out || !inbuf || !outbuf)
		err(1, "alloc");
	if (read_matrix(argv[1], n_ref, ref) != 0)
		err(1, "read ref");
	if (read_matrix(argv[3], n_query, query) != 0)
		err(1, "read query");
	if (tee_open(&ctx, &sess) != 0)
		errx(1, "TEE open failed");

	for (q = 0; q < n_query; q++) {
		for (r0 = 0; r0 < n_ref; r0 += CHUNK) {
			uint32_t n = n_ref - r0;
			struct qai_kernel_block_in *hdr;
			struct qai_kernel_block_out *oh;
			TEEC_Operation op;
			TEEC_Result res;
			uint32_t err_origin;
			float *dst;

			if (n > CHUNK)
				n = CHUNK;
			hdr = (struct qai_kernel_block_in *)inbuf;
			hdr->n_ref = n;
			hdr->n_query = 1;
			memcpy(inbuf + sizeof(*hdr), ref + r0 * FEAT,
			       (size_t)n * FEAT * sizeof(float));
			memcpy(inbuf + sizeof(*hdr) + n * FEAT * sizeof(float),
			       query + q * FEAT, FEAT * sizeof(float));

			memset(&op, 0, sizeof(op));
			op.paramTypes = TEEC_PARAM_TYPES(
				TEEC_MEMREF_TEMP_INPUT, TEEC_MEMREF_TEMP_OUTPUT,
				TEEC_NONE, TEEC_NONE);
			op.params[0].tmpref.buffer = inbuf;
			op.params[0].tmpref.size =
				sizeof(*hdr) + (n + 1) * FEAT * sizeof(float);
			op.params[1].tmpref.buffer = outbuf;
			op.params[1].tmpref.size =
				sizeof(*oh) + n * sizeof(float);

			res = TEEC_InvokeCommand(&sess, TA_QAI_CMD_KERNEL_BLOCK,
						 &op, &err_origin);
			if (res != TEEC_SUCCESS)
				errx(1, "invoke 0x%x origin 0x%x at q=%u r=%u",
				     res, err_origin, q, r0);
			oh = (struct qai_kernel_block_out *)outbuf;
			tee_ms += oh->tee_elapsed_ms;
			calls++;
			dst = (float *)(outbuf + sizeof(*oh));
			memcpy(out + (size_t)q * n_ref + r0, dst,
			       n * sizeof(float));
		}
		if ((q + 1) % 50 == 0 || q + 1 == n_query)
			fprintf(stderr, "query %u/%u tee_ms=%llu calls=%llu\n",
				q + 1, n_query, (unsigned long long)tee_ms,
				(unsigned long long)calls);
	}

	{
		FILE *f = fopen(argv[5], "wb");

		if (!f)
			err(1, "open out");
		if (fwrite(out, sizeof(float), (size_t)n_query * n_ref, f) !=
		    (size_t)n_query * n_ref)
			err(1, "write out");
		fclose(f);
	}
	fprintf(stderr, "TEE_KERNEL_MS %llu\nTEE_CALLS %llu\n",
		(unsigned long long)tee_ms, (unsigned long long)calls);

	TEEC_CloseSession(&sess);
	TEEC_FinalizeContext(&ctx);
	free(ref);
	free(query);
	free(out);
	free(inbuf);
	free(outbuf);
	return 0;
}
