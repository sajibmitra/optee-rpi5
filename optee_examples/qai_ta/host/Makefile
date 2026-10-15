CC      ?= $(CROSS_COMPILE)gcc
LD      ?= $(CROSS_COMPILE)ld
AR      ?= $(CROSS_COMPILE)ar
NM      ?= $(CROSS_COMPILE)nm
OBJCOPY ?= $(CROSS_COMPILE)objcopy
OBJDUMP ?= $(CROSS_COMPILE)objdump
READELF ?= $(CROSS_COMPILE)readelf

CFLAGS += -Wall -Wextra -I../include -I$(TEEC_EXPORT)/include
LDADD += -lteec -L$(TEEC_EXPORT)/lib

.PHONY: all
all: qai_host qai_hai_kernel qai_hai_infer

qai_host: main.o
	$(CC) $(LDFLAGS) -o $@ main.o $(LDADD)

qai_hai_kernel: hai_kernel.o
	$(CC) $(LDFLAGS) -o $@ hai_kernel.o $(LDADD)

qai_hai_infer: hai_infer_client.o
	$(CC) $(LDFLAGS) -o $@ hai_infer_client.o $(LDADD)

.PHONY: clean
clean:
	rm -f main.o hai_kernel.o hai_infer_client.o qai_host qai_hai_kernel qai_hai_infer

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@
