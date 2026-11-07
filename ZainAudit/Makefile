export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
APPLICATION_NAME = ZAINAudit
include $(THEOS)/makefiles/common.mk
ZAINAudit_FILES = main.m AppDelegate.m
ZAINAudit_RESOURCE_DIRS = Resources
ZAINAudit_FRAMEWORKS = UIKit Foundation
ZAINAudit_CFLAGS = -fobjc-arc -Wall -Wextra
ZAINAudit_INSTALL_PATH = /Applications
ZAINAudit_BUNDLE_IDENTIFIER = com.zain.audit
include $(THEOS_MAKE_PATH)/application.mk

export THEOS_PLATFORM_DEB_COMPRESSION_TYPE = xz
after-install::
	install.exec "uicache -p /var/jb/Applications/ZAINAudit.app || uicache -p /Applications/ZAINAudit.app || true"
