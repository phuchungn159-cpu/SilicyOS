# ==============================================================================
# silicy-ctl Makefile — Apple Silicon M1/M2/M3 Pure C Hardware Controller
# Target Compiler Command: clang -O3 -mcpu=apple-m1 -flto=thin -s
# ==============================================================================

ifeq ($(origin CC),default)
CC       := clang
endif
UNAME_S  := $(shell uname -s)
PREFIX   ?= /usr/local
BINDIR   ?= $(PREFIX)/bin

CFLAGS   := -std=c11 -O3 -mcpu=apple-m1 -flto=thin -Wall -Wextra -Werror -fno-plt -pipe
ifeq ($(UNAME_S),Linux)
LDFLAGS  := -s -fuse-ld=lld
else
LDFLAGS  :=
endif

TARGET   := silicy-ctl
SRC      := silicy-ctl.c

.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(TARGET) $(SRC)

install: $(TARGET)
	install -Dm755 $(TARGET) $(DESTDIR)$(BINDIR)/$(TARGET)

clean:
	rm -f $(TARGET)
