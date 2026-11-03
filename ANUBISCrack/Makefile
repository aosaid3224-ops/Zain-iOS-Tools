ARCHS = arm64
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = TempMail

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ANUBISCrack
ANUBISCrack_FILES = Tweak.xm
ANUBISCrack_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
