# Sega Dreamcast Toolchains Maker (dc-chain)
# This file is part of KallistiOS.
#
# Created by Jim Ursetto (2004)
# Initially adapted from Stalin's build script version 0.3.
#

gdb_name = gdb-$(gdb_ver)
gdb_file = $(gdb_name).tar.$(gdb_tarball_type)
gdb_url  = $(download_protocol)://ftp.gnu.org/gnu/gdb/$(gdb_file)

stamp_gdb_unpack = gdb_unpack.stamp
stamp_gdb_patch = gdb_patch.stamp
stamp_gdb_build = gdb_build.stamp
stamp_gdb_install = gdb_install.stamp

gdb_patches := $(wildcard $(patches)/$(gdb_name)*.diff)
gdb_patches += $(wildcard $(patches)/$(host_triplet)/$(gdb_name)*.diff)

$(gdb_file):
	@echo "+++ Downloading GDB..."
	$(web_downloader) $(gdb_url)

unpack_gdb: $(stamp_gdb_unpack)

$(stamp_gdb_unpack): $(gdb_file)
	@echo "+++ Unpacking GDB..."
	rm -f $@ $(stamp_gdb_patch)
	rm -rf $(gdb_name)
	tar xf $(gdb_file)
	touch $@

patch_gdb: $(stamp_gdb_patch)

$(stamp_gdb_patch): unpack_gdb
	@patches=$$(echo "$(gdb_patches)" | xargs); \
	if ! test -f "$(stamp_gdb_patch)"; then \
		if ! test -z "$${patches}"; then \
			echo "+++ Patching GDB..."; \
			patch -N -d $(gdb_name) -p1 < $${patches}; \
		fi; \
		touch "$(stamp_gdb_patch)"; \
	fi;

build_gdb: log = $(logdir)/build-$(gdb_name).log
build_gdb: logdir
build_gdb: $(stamp_gdb_build)

ifeq ($(MACOS), 1)
  ifeq ($(uname_m),arm64)
    $(info Fixing up MacOS arm64 environment variables)
    $(stamp_gdb_build): export CPATH := /opt/homebrew/include
    $(stamp_gdb_build): export LIBRARY_PATH := /opt/homebrew/lib
  endif
  ifeq ($(uname_m),x86_64)
    $(info Fixing up MacOS x86_64 environment variables)
    $(stamp_gdb_build): export CPATH := /usr/local/include
    $(stamp_gdb_build): export LIBRARY_PATH := /usr/local/lib
  endif
endif

$(stamp_gdb_build): unpack_gdb
	@echo "+++ Building GDB..."
	rm -f $@
	> $(log)
	-rm -rf build-$(gdb_name)
	mkdir build-$(gdb_name)
	cd build-$(gdb_name); \
        ../$(gdb_name)/configure \
          --disable-werror \
          --prefix=$(sh_prefix) \
          --target=$(sh_target) \
          CC="$(CC)" \
          CXX="$(CXX)" \
          $(macos_gdb_configure_args) \
          $(static_flag) \
          $(to_log)
	$(MAKE) $(makejobs) -C build-$(gdb_name) $(to_log)
	touch $@

# This step runs post install to sign the sh-elf-gdb binary on MacOS
macos_codesign_gdb: $(stamp_gdb_install)
	@echo "+++ Codesigning GDB..."
	codesign --sign "-" $(sh_prefix)/bin/sh-elf-gdb

# If Host is MacOS then place Codesign step into dependency chain
ifeq ($(MACOS), 1)
GDB_INSTALL_TARGET = macos_codesign_gdb
else
GDB_INSTALL_TARGET = $(stamp_gdb_install)
endif

install_gdb: log = $(logdir)/build-$(gdb_name).log
install_gdb: logdir
install_gdb: $(GDB_INSTALL_TARGET)

# The 'install-strip' mode support is partial in GDB so there is a little hack
# below to remove useless debug symbols
# See: https://sourceware.org/legacy-ml/gdb-patches/2012-01/msg00335.html
$(stamp_gdb_install): build_gdb
	@echo "+++ Installing GDB..."
	rm -f $@
	$(MAKE) -C build-$(gdb_name) install DESTDIR=$(DESTDIR) $(to_log)
	@if test "$(install_mode)" = "install-strip"; then \
		$(MAKE) -C build-$(gdb_name)/gdb $(install_mode) DESTDIR=$(DESTDIR) $(to_log); \
		gdb_run=$(sh_prefix)/bin/$(sh_target)-run$(executable_extension); \
		if test -f $${gdb_run}; then \
			strip $${gdb_run}; \
		fi; \
	fi;
	touch $@

gdb: install_gdb
