ifeq ($(strip $(THEOS)),)
THEOS := $(firstword $(wildcard \
	$(HOME)/theos \
	/var/mobile/theos \
	/var/jb/var/mobile/theos \
	/opt/theos \
	/var/jb/opt/theos))
endif

ifeq ($(strip $(THEOS)),)
$(error Theos was not found. Set THEOS to the directory containing makefiles/common.mk)
endif

TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := Harbor

# Phase 1 compiles the runtime-gated dock core. The remaining iOS 10
# implementation stays excluded while its private APIs are migrated.
Harbor_FILES := Tweak.xm HBIconColor.m HBDockPosition.m HBCircularDock.m
Harbor_CFLAGS := -fobjc-arc -Wall -Wextra
Harbor_FRAMEWORKS := Foundation UIKit QuartzCore CoreGraphics
Harbor_INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "sbreload"

SUBPROJECTS += harborprefs
include $(THEOS_MAKE_PATH)/aggregate.mk

.PHONY: test-selection-color
test-selection-color:
	/var/jb/usr/bin/clang -fobjc-arc -O1 -target arm64-apple-ios15.0 -isysroot $(THEOS)/sdks/iPhoneOS16.5.sdk -I. tests/SelectionColorTests.m HBIconColor.m -framework UIKit -framework Foundation -framework CoreGraphics -o .selection-color-tests
	/var/jb/usr/bin/ldid -S .selection-color-tests
	./.selection-color-tests > selection-color-results.json

.PHONY: test-preferences-load
test-preferences-load:
	/var/jb/usr/bin/clang -fobjc-arc -O1 -target arm64-apple-ios15.0 -isysroot $(THEOS)/sdks/iPhoneOS16.5.sdk -I. tests/PreferencesLoadTests.m -framework UIKit -framework Foundation -o .preferences-load-tests
	/var/jb/usr/bin/ldid -S .preferences-load-tests
	./.preferences-load-tests > preferences-load-results.json

.PHONY: test-dock-capacity
test-dock-capacity:
	/var/jb/usr/bin/clang -fobjc-arc -O1 -target arm64-apple-ios15.0 -isysroot $(THEOS)/sdks/iPhoneOS16.5.sdk -I. tests/DockCapacityTests.m -framework Foundation -o .dock-capacity-tests
	/var/jb/usr/bin/ldid -S .dock-capacity-tests
	./.dock-capacity-tests > dock-capacity-results.json

.PHONY: test-dock-position
test-dock-position:
	/var/jb/usr/bin/clang -fobjc-arc -O1 -target arm64-apple-ios15.0 -isysroot $(THEOS)/sdks/iPhoneOS16.5.sdk -I. -DHB_POSITION_TEST=1 tests/DockPositionTests.m $(POSITION_IMPL) -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -o .dock-position-tests
	/var/jb/usr/bin/ldid -S .dock-position-tests
	./.dock-position-tests > dock-position-results.json

POSITION_IMPL ?= HBDockPosition.m

.PHONY: test-compatibility
test-compatibility:
	/var/jb/usr/bin/clang -fobjc-arc -O1 -target arm64-apple-ios15.0 -isysroot $(THEOS)/sdks/iPhoneOS16.5.sdk -I. tests/CompatibilityTests.m -framework Foundation -o .compatibility-tests
	/var/jb/usr/bin/ldid -S .compatibility-tests
	./.compatibility-tests > compatibility-results.json

.PHONY: test-circular-dock
test-circular-dock:
	/var/jb/usr/bin/clang -fobjc-arc -O1 -target arm64-apple-ios15.0 -isysroot $(THEOS)/sdks/iPhoneOS16.5.sdk -I. -DHB_CIRCULAR_TEST=1 tests/CircularDockTests.m HBCircularDock.m HBIconColor.m -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -o .circular-dock-tests
	/var/jb/usr/bin/ldid -S .circular-dock-tests
	./.circular-dock-tests > circular-dock-results.json


.PHONY: test-circular-handoff
test-circular-handoff:
	/var/jb/usr/bin/clang -fobjc-arc -O1 -target arm64-apple-ios15.0 -isysroot $(THEOS)/sdks/iPhoneOS16.5.sdk -I. -DHB_CIRCULAR_TEST=1 tests/CircularHandoffTests.m HBCircularDock.m HBIconColor.m -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -o .circular-handoff-tests
	/var/jb/usr/bin/ldid -S .circular-handoff-tests
	./.circular-handoff-tests > circular-handoff-results.json
