include core/arch/arm/cpu/cortex-armv8-0.mk

$(call force,CFG_TEE_CORE_NB_CORE,4)
$(call force,CFG_ARM64_core,y)
$(call force,CFG_WITH_LPAE,y)
$(call force,CFG_AUTO_MAX_PA_BITS,y)
$(call force,CFG_LPAE_ADDR_SPACE_BITS,40)

CFG_SHMEM_START     ?= 0x08000000
CFG_SHMEM_SIZE      ?= 0x00400000
CFG_TZDRAM_START    ?= 0x1D000000
CFG_TZDRAM_SIZE     ?= 0x02000000
CFG_TEE_RAM_VA_SIZE ?= 0x00700000
CFG_DT              ?= y
# Extra headroom for optee_core / optee_shm / optee_sw_log reserved-memory nodes
CFG_DTB_MAX_SIZE    ?= 0x40000

$(call force,CFG_PL011,y)
$(call force,CFG_SECURE_TIME_SOURCE_CNTPCT,y)
$(call force,CFG_WITH_ARM_TRUSTED_FW,y)

CFG_NUM_THREADS ?= 4

# Secure-world log ring in NS RAM for SSH monitoring (optee-sw-log).
# Mapped as MEM_AREA_IO_NSEC so io_pa_or_va works after MMU is on.
CFG_RPI5_SW_LOG ?= y
