ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = DELTA_LOADER
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LoaderRecon
LoaderRecon_FILES = Tweak.xm
include $(THEOS_MAKE_PATH)/tweak.mk
