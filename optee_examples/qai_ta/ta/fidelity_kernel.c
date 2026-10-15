/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * 8-qubit fidelity kernel timed inside the Trusted Application.
 *
 * Same schedule as the Normal World NumPy measurement of arXiv:2409.04935:
 * 16 features, dense-angle RY/RZ, nearest-neighbour CNOT ring, repeated
 * rotation, three repetitions, then U(y)^dagger, then exp(|amp[0]|^2).
 *
 * The statevector lives in the TA data section (not on the 4 KiB stack).
 * sin/cos are local polynomials so the TA does not link glibc libm.
 * Forward and inverse use the same functions, so K(x,x) stays near 1
 * even when the polynomial is not a perfect libm match.
 */
#include <tee_internal_api.h>

#include <qai_ta.h>

#define QAI_NQ		8
#define QAI_DIM		256
#define QAI_NFEAT	16
#define QAI_REPS	3
#define QAI_PI		3.14159265358979323846

static double psi_re[QAI_DIM];
static double psi_im[QAI_DIM];
static double tmp_re[QAI_DIM / 2];
static double tmp_im[QAI_DIM / 2];

static double k_sin(double x)
{
	int neg = 0;
	double x2;
	double s;

	if (x < 0.0) {
		neg = 1;
		x = -x;
	}
	if (x > QAI_PI)
		x = (2.0 * QAI_PI) - x;
	if (x > (QAI_PI * 0.5))
		x = QAI_PI - x;

	x2 = x * x;
	s = x * (1.0
		+ x2 * (-1.0 / 6.0
		+ x2 * (1.0 / 120.0
		+ x2 * (-1.0 / 5040.0
		+ x2 * (1.0 / 362880.0
		+ x2 * (-1.0 / 39916800.0
		+ x2 * (1.0 / 6227020800.0
		+ x2 * (-1.0 / 1307674368000.0))))))));
	return neg ? -s : s;
}

static double k_cos(double x)
{
	double x2;
	double ax = x;

	if (ax < 0.0)
		ax = -ax;
	if (ax > (QAI_PI * 0.5))
		return -k_sin(ax - (QAI_PI * 0.5));

	x2 = ax * ax;
	return 1.0
		+ x2 * (-0.5
		+ x2 * (1.0 / 24.0
		+ x2 * (-1.0 / 720.0
		+ x2 * (1.0 / 40320.0
		+ x2 * (-1.0 / 3628800.0
		+ x2 * (1.0 / 479001600.0
		+ x2 * (-1.0 / 87178291200.0)))))));
}

static double k_exp_unit(double p)
{
	double term = 1.0;
	double sum = 1.0;
	int k;

	for (k = 1; k <= 16; k++) {
		term *= p / (double)k;
		sum += term;
	}
	return sum;
}

static void apply_1q(int q, double g00r, double g00i, double g01r, double g01i,
		     double g10r, double g10i, double g11r, double g11i)
{
	int i;
	int n0 = 0;
	int bit = 1 << q;

	for (i = 0; i < QAI_DIM; i++) {
		int j;

		if (i & bit)
			continue;
		j = i | bit;
		tmp_re[n0] = psi_re[i];
		tmp_im[n0] = psi_im[i];
		/* stash partner in the upper half by overwriting after copy */
		psi_re[i] = psi_re[j];
		psi_im[i] = psi_im[j];
		n0++;
	}

	n0 = 0;
	for (i = 0; i < QAI_DIM; i++) {
		double ar, ai, br, bi;
		int j;

		if (i & bit)
			continue;
		j = i | bit;
		ar = tmp_re[n0];
		ai = tmp_im[n0];
		br = psi_re[i];
		bi = psi_im[i];
		/* i <- g00 * a + g01 * b */
		psi_re[i] = g00r * ar - g00i * ai + g01r * br - g01i * bi;
		psi_im[i] = g00r * ai + g00i * ar + g01r * bi + g01i * br;
		/* j <- g10 * a + g11 * b */
		psi_re[j] = g10r * ar - g10i * ai + g11r * br - g11i * bi;
		psi_im[j] = g10r * ai + g10i * ar + g11r * bi + g11i * br;
		n0++;
	}
}

static void apply_ry(int q, double theta)
{
	double c = k_cos(theta * 0.5);
	double s = k_sin(theta * 0.5);

	apply_1q(q, c, 0.0, -s, 0.0, s, 0.0, c, 0.0);
}

static void apply_rz(int q, double phi)
{
	double a = phi * 0.5;
	double c = k_cos(a);
	double s = k_sin(a);

	/* diag(exp(-i a), exp(+i a)) */
	apply_1q(q, c, -s, 0.0, 0.0, 0.0, 0.0, c, s);
}

static void cnot_pair(int ctrl, int tgt)
{
	int i;
	int cbit = 1 << ctrl;
	int tbit = 1 << tgt;

	for (i = 0; i < QAI_DIM; i++) {
		double tr, ti;
		int j;

		if ((i & cbit) == 0 || (i & tbit) != 0)
			continue;
		j = i | tbit;
		tr = psi_re[i];
		ti = psi_im[i];
		psi_re[i] = psi_re[j];
		psi_im[i] = psi_im[j];
		psi_re[j] = tr;
		psi_im[j] = ti;
	}
}

static void cnot_ring(int reverse)
{
	int q;

	if (!reverse) {
		for (q = 0; q < QAI_NQ; q++)
			cnot_pair(q, (q + 1) % QAI_NQ);
	} else {
		for (q = QAI_NQ - 1; q >= 0; q--)
			cnot_pair(q, (q + 1) % QAI_NQ);
	}
}

static void layer_fwd(const double *x)
{
	int q;

	for (q = 0; q < QAI_NQ; q++) {
		apply_ry(q, x[2 * q]);
		apply_rz(q, x[2 * q + 1]);
	}
	cnot_ring(0);
	for (q = 0; q < QAI_NQ; q++) {
		apply_ry(q, x[2 * q]);
		apply_rz(q, x[2 * q + 1]);
	}
}

static void layer_inv(const double *y)
{
	int q;

	for (q = QAI_NQ - 1; q >= 0; q--) {
		apply_rz(q, -y[2 * q + 1]);
		apply_ry(q, -y[2 * q]);
	}
	cnot_ring(1);
	for (q = QAI_NQ - 1; q >= 0; q--) {
		apply_rz(q, -y[2 * q + 1]);
		apply_ry(q, -y[2 * q]);
	}
}

static void reset_psi(void)
{
	int i;

	for (i = 0; i < QAI_DIM; i++) {
		psi_re[i] = 0.0;
		psi_im[i] = 0.0;
	}
	psi_re[0] = 1.0;
}

static double fidelity_exp(const double *x, const double *y)
{
	int r;
	double p;

	reset_psi();
	for (r = 0; r < QAI_REPS; r++)
		layer_fwd(x);
	for (r = 0; r < QAI_REPS; r++)
		layer_inv(y);
	p = psi_re[0] * psi_re[0] + psi_im[0] * psi_im[0];
	if (p < 0.0)
		p = 0.0;
	if (p > 1.0)
		p = 1.0;
	return k_exp_unit(p);
}

static uint32_t rng_state = 240904935u;

static double next_angle(void)
{
	rng_state = rng_state * 1664525u + 1013904223u;
	return ((rng_state >> 8) * (1.0 / 16777216.0)) * (2.0 * QAI_PI) - QAI_PI;
}

static void fill_vec(double *v)
{
	int i;

	for (i = 0; i < QAI_NFEAT; i++)
		v[i] = next_angle();
}

static uint32_t delta_ms(const TEE_Time *t0, const TEE_Time *t1)
{
	uint32_t sec = t1->seconds - t0->seconds;
	int32_t ms = (int32_t)t1->millis - (int32_t)t0->millis;

	if (ms < 0) {
		sec -= 1;
		ms += 1000;
	}
	return sec * 1000u + (uint32_t)ms;
}

TEE_Result qai_fidelity_bench(uint32_t evals, struct qai_fidelity_bench *out)
{
	double x[QAI_NFEAT];
	double y[QAI_NFEAT];
	double self_x[QAI_NFEAT];
	double acc = 0.0;
	uint32_t i;
	TEE_Time t0;
	TEE_Time t1;

	if (evals > 20000)
		return TEE_ERROR_BAD_PARAMETERS;

	TEE_MemFill(out, 0, sizeof(*out));
	fill_vec(self_x);
	out->self_exp_micro = (int64_t)(fidelity_exp(self_x, self_x) * 1000000.0);

	TEE_GetSystemTime(&t0);
	for (i = 0; i < evals; i++) {
		fill_vec(x);
		fill_vec(y);
		acc += fidelity_exp(x, y);
	}
	TEE_GetSystemTime(&t1);

	out->evals = evals;
	out->tee_elapsed_ms = delta_ms(&t0, &t1);
	out->batch_sum_micro = (int64_t)(acc * 1000000.0);
	return TEE_SUCCESS;
}
