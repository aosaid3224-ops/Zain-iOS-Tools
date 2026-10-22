ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DeviceMask
THEOS_PACKAGE_SCHEME = rootless
DeviceMask_CFLAGS = -Wno-deprecated-declarations -fobjc-arc
DeviceMask_LDFLAGS = -Wl,-U,_MGCopyAnswer
DeviceMask_FILES = Tweak.xm

include $(THEOS_MAKE_PATH)/tweak.mk
