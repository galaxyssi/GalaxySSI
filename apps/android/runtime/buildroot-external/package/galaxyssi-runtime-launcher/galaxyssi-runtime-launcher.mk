################################################################################
#
# galaxyssi-runtime-launcher
#
################################################################################

GALAXYSSI_RUNTIME_LAUNCHER_VERSION = 1.0.0
GALAXYSSI_RUNTIME_LAUNCHER_SITE = $(BR2_EXTERNAL_GALAXYSSI_PATH)/package/galaxyssi-runtime-launcher/src
GALAXYSSI_RUNTIME_LAUNCHER_SITE_METHOD = local
GALAXYSSI_RUNTIME_LAUNCHER_LICENSE = Apache-2.0

define GALAXYSSI_RUNTIME_LAUNCHER_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		-Wall -Wextra -Werror -fstack-protector-strong \
		-o $(@D)/galaxyssi-runtime-launcher $(@D)/galaxyssi-runtime-launcher.c
endef

define GALAXYSSI_RUNTIME_LAUNCHER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/galaxyssi-runtime-launcher \
		$(TARGET_DIR)/usr/libexec/galaxyssi-runtime-launcher
endef

$(eval $(generic-package))
