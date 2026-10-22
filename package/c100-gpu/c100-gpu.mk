################################################################################
#
# c100-gpu
#
################################################################################

C100_GPU_VERSION = 1
C100_GPU_SOURCE =
C100_GPU_LICENSE = CC0-1.0
C100_GPU_DEPENDENCIES = vulkan-tools

define C100_GPU_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(C100_GPU_PKGDIR)/c100-limits \
		$(TARGET_DIR)/usr/sbin/c100-limits
endef

$(eval $(generic-package))
