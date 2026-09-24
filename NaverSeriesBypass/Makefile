TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NaverSeriesBypass
NaverSeriesBypass_FILES = Tweak.x
NaverSeriesBypass_CFLAGS = -fobjc-arc -Wno-error
NaverSeriesBypass_FRAMEWORKS = UIKit Security Foundation WebKit AdSupport CoreTelephony
NaverSeriesBypass_PRIVATE_FRAMEWORKS = 

THEOS_PACKAGE_SCHEME = rootless

SUBPROJECTS += NaverSeriesBypassPrefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard; killall -9 NaverBooks; killall -9 Series"
