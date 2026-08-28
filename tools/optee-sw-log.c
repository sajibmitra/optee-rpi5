// SPDX-License-Identifier: BSD-2-Clause
/*
 * Read OP-TEE secure-world log ring buffer over SSH (maps /dev/mem).
 * Buffer layout must match optee_os/core/arch/arm/plat-rpi5/sw_log.c
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define RPI5_SW_LOG_MAGIC	0x4f504c47U
#define RPI5_SW_LOG_HDR_SIZE	16
#define RPI5_SW_LOG_PADDR_DEFAULT	0x08400000ULL
#define RPI5_SW_LOG_SIZE_DEFAULT	0x00010000ULL

struct sw_log_hdr {
	uint32_t magic;
	uint32_t write_pos;
	uint32_t generation;
	uint32_t reserved;
};

static volatile struct sw_log_hdr *hdr;
static volatile uint8_t *data;
static uint32_t data_size;
static uint32_t read_pos;
static uint32_t read_gen;

static void emit_byte(uint8_t ch)
{
	putchar(ch);
	fflush(stdout);
}

static void drain_new(void)
{
	for (;;) {
		uint32_t wp = hdr->write_pos;
		uint32_t gen = hdr->generation;

		if (read_pos == wp && read_gen == gen)
			break;

		emit_byte(data[read_pos]);
		read_pos++;
		if (read_pos >= data_size) {
			read_pos = 0;
			read_gen = gen;
		}
	}
}

static int map_log(uint64_t paddr, size_t size, bool wait_magic)
{
	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	void *map = NULL;
	int tries = 0;

	if (fd < 0) {
		perror("open /dev/mem");
		return -1;
	}

	map = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, paddr);
	close(fd);
	if (map == MAP_FAILED) {
		perror("mmap");
		return -1;
	}

	hdr = map;
	data = (volatile uint8_t *)map + RPI5_SW_LOG_HDR_SIZE;
	data_size = size - RPI5_SW_LOG_HDR_SIZE;

	while (hdr->magic != RPI5_SW_LOG_MAGIC) {
		if (!wait_magic || tries++ > 600) {
			fprintf(stderr,
				"No OP-TEE SW log at 0x%llx (magic %#x).\n"
				"Redeploy OP-TEE with sw_log support: ./deploy_rpi5_optee_kernel.sh\n",
				(unsigned long long)paddr, hdr->magic);
			munmap(map, size);
			return -1;
		}
		if (tries == 1) {
			fprintf(stderr,
				"Waiting for OP-TEE secure log buffer at 0x%llx...\n",
				(unsigned long long)paddr);
		}
		usleep(100000);
	}

	read_pos = hdr->write_pos;
	read_gen = hdr->generation;
	return 0;
}

static void usage(const char *prog)
{
	fprintf(stderr,
		"Usage: %s [-f] [-a ADDR] [-s SIZE]\n"
		"\n"
		"  -f, --follow   Stream new secure-world log lines (like tail -f)\n"
		"  -a ADDR        Physical base (default 0x%llx)\n"
		"  -s SIZE        Region size (default 0x%zx)\n"
		"\n"
		"Requires root. Run in a separate SSH session while tests/apps execute.\n",
		prog,
		(unsigned long long)RPI5_SW_LOG_PADDR_DEFAULT,
		(size_t)RPI5_SW_LOG_SIZE_DEFAULT);
}

int main(int argc, char **argv)
{
	uint64_t paddr = RPI5_SW_LOG_PADDR_DEFAULT;
	size_t size = RPI5_SW_LOG_SIZE_DEFAULT;
	bool follow = false;
	int opt = 0;

	static struct option opts[] = {
		{ "follow", no_argument, NULL, 'f' },
		{ "addr", required_argument, NULL, 'a' },
		{ "size", required_argument, NULL, 's' },
		{ "help", no_argument, NULL, 'h' },
		{ 0, 0, 0, 0 },
	};

	while ((opt = getopt_long(argc, argv, "fa:s:h", opts, NULL)) != -1) {
		switch (opt) {
		case 'f':
			follow = true;
			break;
		case 'a':
			paddr = strtoull(optarg, NULL, 0);
			break;
		case 's':
			size = strtoull(optarg, NULL, 0);
			break;
		default:
			usage(argv[0]);
			return opt == 'h' ? 0 : 1;
		}
	}

	if (map_log(paddr, size, follow) < 0)
		return 1;

	if (!follow) {
		drain_new();
		return 0;
	}

	fprintf(stderr, "optee-sw-log: following 0x%llx (%zu bytes)\n",
		(unsigned long long)paddr, size);

	while (1) {
		drain_new();
		usleep(10000);
	}

	return 0;
}
