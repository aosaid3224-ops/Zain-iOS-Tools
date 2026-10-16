export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e

THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = DeltaGuard

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = DeltaGuard

DeltaGuard_FILES = main.m AppDelegate.m RootViewController.m
DeltaGuard_FRAMEWORKS = UIKit
DeltaGuard_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
DeltaGuard_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "uicache -p /var/jb/Applications/DeltaGuard.app || uicache -p /Applications/DeltaGuard.app || true"

export THEOS_PLATFORM_DEB_COMPRESSION_TYPE = xz

TOOL_NAME = deltaguard_helper
deltaguard_helper_FILES = Helper/deltaguard_helper.c
deltaguard_helper_INSTALL_PATH = /usr/libexec
deltaguard_helper_CFLAGS = -O2
deltaguard_helper_LDFLAGS =

include $(THEOS_MAKE_PATH)/tool.mk
