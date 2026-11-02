include $(THEOS)/makefiles/common.mk
BUNDLE_NAME := harborprefs
harborprefs_FILES := HPRootListController.m
harborprefs_FRAMEWORKS := UIKit
harborprefs_PRIVATE_FRAMEWORKS := Preferences
harborprefs_INSTALL_PATH := /Library/PreferenceBundles
harborprefs_CFLAGS := -fobjc-arc
harborprefs_RESOURCE_DIRS := Resources
include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/harborprefs.plist$(ECHO_END)
	$(ECHO_NOTHING)cp Resources/Root.plist $(THEOS_STAGING_DIR)/Library/PreferenceBundles/harborprefs.bundle/Root.plist$(ECHO_END)
