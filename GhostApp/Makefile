export TARGET = iphone:clang:latest:15.0
export THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = GhostApp
GhostApp_FILES = main.m AppDelegate.m RootViewController.m
GhostApp_FRAMEWORKS = UIKit Foundation
GhostApp_POSTINST = $(THEOS_PROJECT_DIR)/postinst

TOOL_NAME = ghosthelper
ghosthelper_FILES = helper.c

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tool.mk
