################################################################################
#
# tegra210-firmware
#
################################################################################

# Installs Tegra210 files from the linux-firmware source tree, which has no
# Buildroot option for them.
TEGRA210_FIRMWARE_DEPENDENCIES = linux-firmware
TEGRA210_FIRMWARE_LICENSE = NVIDIA firmware license (LICENCE.nvidia in linux-firmware)

TEGRA210_FIRMWARE_FILES = \
	nvidia/tegra210/xusb.bin \
	nvidia/tegra210/vic04_ucode.bin \
	nvidia/gm20b/acr/bl.bin \
	nvidia/gm20b/acr/ucode_load.bin \
	nvidia/gm20b/gr/fecs_bl.bin \
	nvidia/gm20b/gr/fecs_data.bin \
	nvidia/gm20b/gr/fecs_inst.bin \
	nvidia/gm20b/gr/fecs_sig.bin \
	nvidia/gm20b/gr/gpccs_data.bin \
	nvidia/gm20b/gr/gpccs_inst.bin \
	nvidia/gm20b/gr/sw_bundle_init.bin \
	nvidia/gm20b/gr/sw_ctx.bin \
	nvidia/gm20b/gr/sw_nonctx.bin \
	nvidia/gm20b/pmu/desc.bin \
	nvidia/gm20b/pmu/image.bin \
	nvidia/gm20b/pmu/sig.bin \
	nvidia/gm200/gr/sw_method_init.bin

# From the "Link:" entries in linux-firmware's WHENCE
TEGRA210_FIRMWARE_LINKS = \
	nvidia/tegra210/vic.bin:vic04_ucode.bin \
	nvidia/gm20b/gr/sw_method_init.bin:../../gm200/gr/sw_method_init.bin

define TEGRA210_FIRMWARE_INSTALL_TARGET_CMDS
	$(foreach f,$(TEGRA210_FIRMWARE_FILES), \
		$(INSTALL) -D -m 0644 $(LINUX_FIRMWARE_DIR)/$(f) \
			$(TARGET_DIR)/lib/firmware/$(f)$(sep))
	$(foreach l,$(TEGRA210_FIRMWARE_LINKS), \
		ln -sf $(lastword $(subst :, ,$(l))) \
			$(TARGET_DIR)/lib/firmware/$(firstword $(subst :, ,$(l)))$(sep))
endef

$(eval $(generic-package))
