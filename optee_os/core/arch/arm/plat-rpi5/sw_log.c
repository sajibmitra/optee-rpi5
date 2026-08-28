// SPDX-License-Identifier: BSD-2-Clause
/*
 * Secure-world log ring buffer in normal-world RAM for SSH monitoring.
 * Layout matches tools/optee-sw-log.c on the Linux side.
 *
 * Use MEM_AREA_RAM_NSEC + phys_to_virt(). Do NOT register this DRAM window as
 * MEM_AREA_IO_NSEC (that hung Pi 5 boot) and do NOT use io_pa_or_va() on
 * RAM_NSEC (phys_to_virt_io only finds IO_* maps → NULL assert hang).
 *
 * Init is deferred until service_init so early console_init does not touch NS
 * RAM. DT reservation soft-fails so a full DTB cannot panic boot.
 */

#include <compiler.h>
#include <initcall.h>
#include <io.h>
#include <kernel/boot.h>
#include <kernel/dt.h>
#include <kernel/spinlock.h>
#include <mm/core_memprot.h>
#include <platform_config.h>
#include <stddef.h>
#include <stdint.h>
#include <trace.h>
#include <types_ext.h>
#include <util.h>

#define RPI5_SW_LOG_MAGIC	0x4f504c47U /* 'OPLG' */
#define RPI5_SW_LOG_HDR_SIZE	16

struct rpi5_sw_log_hdr {
	uint32_t magic;
	uint32_t write_pos;
	uint32_t generation;
	uint32_t reserved;
};

static paddr_t sw_log_pa;
static vaddr_t sw_log_va_base;
static uint32_t sw_log_size;
static unsigned int sw_log_lock = SPINLOCK_UNLOCK;

register_phys_mem(MEM_AREA_RAM_NSEC, RPI5_SW_LOG_PADDR, RPI5_SW_LOG_SIZE);

static vaddr_t sw_log_va(void)
{
	return sw_log_va_base;
}

static void sw_log_putc(char ch)
{
	uint32_t pos = 0;
	uint32_t gen = 0;
	uint32_t data_off = 0;
	vaddr_t base = 0;
	uint32_t data_size = 0;

	if (!sw_log_size || !sw_log_va_base)
		return;

	base = sw_log_va();
	data_size = sw_log_size - RPI5_SW_LOG_HDR_SIZE;

	cpu_spin_lock(&sw_log_lock);
	pos = io_read32(base + offsetof(struct rpi5_sw_log_hdr, write_pos));
	gen = io_read32(base + offsetof(struct rpi5_sw_log_hdr, generation));

	if (pos >= data_size) {
		pos = 0;
		gen++;
	}

	data_off = RPI5_SW_LOG_HDR_SIZE + pos;
	io_write8(base + data_off, ch);
	pos++;

	if (pos >= data_size) {
		pos = 0;
		gen++;
	}

	io_write32(base + offsetof(struct rpi5_sw_log_hdr, generation), gen);
	io_write32(base + offsetof(struct rpi5_sw_log_hdr, write_pos), pos);
	cpu_spin_unlock(&sw_log_lock);
}

int plat_dt_add_reserved_mem(struct dt_descriptor *dt)
{
	int ret = 0;

	ret = add_res_mem_dt_node(dt, "optee_sw_log", RPI5_SW_LOG_PADDR,
				  RPI5_SW_LOG_SIZE);
	if (ret)
		EMSG("optee_sw_log DT reserve failed (%d); continuing", ret);
	return 0;
}

void plat_trace_init(void)
{
	/* PA only; map + enable after MMU in service_init. */
	sw_log_pa = RPI5_SW_LOG_PADDR;
}

static TEE_Result rpi5_sw_log_init(void)
{
	void *va = NULL;

	sw_log_pa = RPI5_SW_LOG_PADDR;
	va = phys_to_virt(sw_log_pa, MEM_AREA_RAM_NSEC, RPI5_SW_LOG_SIZE);
	if (!va) {
		EMSG("rpi5 sw_log: phys_to_virt failed for 0x%" PRIxPA,
		     sw_log_pa);
		return TEE_ERROR_GENERIC;
	}

	sw_log_va_base = (vaddr_t)va;

	if (io_read32(sw_log_va_base +
		      offsetof(struct rpi5_sw_log_hdr, magic)) !=
	    RPI5_SW_LOG_MAGIC) {
		io_write32(sw_log_va_base +
			   offsetof(struct rpi5_sw_log_hdr, magic),
			   RPI5_SW_LOG_MAGIC);
		io_write32(sw_log_va_base +
			   offsetof(struct rpi5_sw_log_hdr, write_pos), 0);
		io_write32(sw_log_va_base +
			   offsetof(struct rpi5_sw_log_hdr, generation), 0);
		io_write32(sw_log_va_base +
			   offsetof(struct rpi5_sw_log_hdr, reserved), 0);
	}

	/* Enable puts only after VA is valid. */
	sw_log_size = RPI5_SW_LOG_SIZE;
	IMSG("rpi5 sw_log ready at PA 0x%" PRIxPA " VA 0x%" PRIxVA " (%u bytes)",
	     sw_log_pa, sw_log_va_base, sw_log_size);
	return TEE_SUCCESS;
}

service_init(rpi5_sw_log_init);

void plat_trace_ext_puts(const char *str)
{
	const char *p = NULL;

	for (p = str; *p; p++)
		sw_log_putc(*p);
}
