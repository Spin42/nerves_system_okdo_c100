################################################################################
#
# mesa3d-nvk
#
################################################################################

# Adds NVK to Buildroot's mesa3d package. External makefiles are included
# after Buildroot's, so this appends to the mesa3d variables, which are
# expanded when the steps run. mesa3d's dependencies have already become
# make rules by then; the extra ones are added to its configure step.

ifeq ($(BR2_PACKAGE_MESA3D_VULKAN_DRIVER_NOUVEAU),y)

MESA3D_VULKAN_DRIVERS-y += nouveau

# NVK is partly written in Rust, and generates its C headers with cbindgen
MESA3D_NVK_DEPENDENCIES = \
	host-cbindgen \
	host-rust-bindgen \
	host-rustc

# NVK's shaders need mesa_clc on the build host, but no LLVM on the target
ifneq ($(BR2_PACKAGE_MESA3D_NEEDS_PRECOMP_COMPILER),y)
MESA3D_NVK_DEPENDENCIES += host-mesa3d
MESA3D_CONF_OPTS += -Dmesa-clc=system
endif

MESA3D_DEPENDENCIES += $(MESA3D_NVK_DEPENDENCIES)
$(MESA3D_TARGET_CONFIGURE): | $(MESA3D_NVK_DEPENDENCIES)

# mesa3d sets up Rust itself for rusticl
ifneq ($(BR2_PACKAGE_MESA3D_RUSTICL),y)
# https://docs.mesa3d.org/rusticl.html#known-issues
MESA3D_CONF_OPTS += -Drust_std=2021

# meson does not allow ccache
MESA3D_CONF_ENV += \
	CC_FOR_BUILD="$(HOSTCC_NOCCACHE)" \
	CXX_FOR_BUILD="$(HOSTCXX_NOCCACHE)"

MESA3D_MESON_EXTRA_BINARIES += \
	rust=['$(HOST_DIR)/bin/rustc','--target=$(RUSTC_TARGET_NAME)'] \
	rust_ld='$(TARGET_CROSS)gcc'
endif

# Rust crates that the meson wraps in subprojects/ would download. meson
# takes them from subprojects/packagecache instead, even with
# --wrap-mode=nodownload. Their hashes are in patches/mesa3d/mesa3d.hash.
MESA3D_NVK_CRATES = \
	paste/paste-1.0.14 \
	proc-macro2/proc-macro2-1.0.86 \
	quote/quote-1.0.35 \
	rustc-hash/rustc-hash-2.1.1 \
	syn/syn-2.0.87 \
	unicode-ident/unicode-ident-1.0.12
MESA3D_EXTRA_DOWNLOADS += \
	$(patsubst %,https://static.crates.io/crates/%.crate,$(MESA3D_NVK_CRATES))

define MESA3D_NVK_COPY_CRATES
	mkdir -p $(@D)/subprojects/packagecache
	$(foreach c,$(notdir $(MESA3D_NVK_CRATES)),\
		cp $(MESA3D_DL_DIR)/$(c).crate \
			$(@D)/subprojects/packagecache/$(c).tar.gz$(sep))
endef
MESA3D_POST_EXTRACT_HOOKS += MESA3D_NVK_COPY_CRATES

# meson rejects a host LLVM built without RTTI unless the RTTI settings match
HOST_MESA3D_CONF_OPTS += -Dcpp_rtti=$(if $(BR2_PACKAGE_LLVM_RTTI),true,false)

endif
