TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = NaverSeriesBypassPrefs

NaverSeriesBypassPrefs_FILES = NaverSeriesBypassPrefs.m
NaverSeriesBypassPrefs_INSTALL_PATH = /Library/PreferenceBundles
NaverSeriesBypassPrefs_RESOURCE_DIRS = Resources
NaverSeriesBypassPrefs_FRAMEWORKS = UIKit
# Preferences.framework is private and supplied by the jailbreak runtime.
# Resolve its symbols dynamically so current Xcode SDKs can build the bundle.
NaverSeriesBypassPrefs_PRIVATE_FRAMEWORKS =
NaverSeriesBypassPrefs_LDFLAGS = -undefined dynamic_lookup
NaverSeriesBypassPrefs_CFLAGS = -fobjc-arc

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/NaverSeriesBypassPrefs.plist$(ECHO_END)
