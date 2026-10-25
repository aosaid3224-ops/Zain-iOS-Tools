ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GameForge
THEOS_PACKAGE_SCHEME = rootless
GameForge_CFLAGS = -Wno-deprecated-declarations -fobjc-arc
GameForge_FILES = Tweak.xm

include $(THEOS_MAKE_PATH)/tweak.mk
