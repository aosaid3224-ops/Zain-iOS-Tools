TARGET := iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DeviceMask
DeviceMask_FILES = Tweak.xm
DeviceMask_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
