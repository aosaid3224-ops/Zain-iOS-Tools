export TARGET = iphone:clang:latest:15.0
export THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CrackRecon
CrackRecon_FILES = Tweak.xm
CrackRecon_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
