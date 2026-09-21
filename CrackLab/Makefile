ARCHS := arm64
TARGET := iphone:clang:latest:15.0

APPLICATION_NAME = CrackLab

CrackLab_FILES = main.m \
	CLAppDelegate.m \
	UI/CLTheme.m \
	UI/CLComponents.m \
	UI/CLRootViewController.m \
	UI/CLGamesViewController.m \
	UI/CLGameCell.m \
	UI/CLGameDetailViewController.m \
	UI/CLLogViewController.m \
	UI/CLSettingsViewController.m \
	Core/CLGame.m \
	Core/CLGameDiscovery.m \
	Core/CLDiscoveryRecord.m \
	Core/CLMetadataProbe.m \
	Core/CLEngineDetector.m \
	Core/CLGameStateInspector.m \
	Core/CLOperationLog.m

CrackLab_FRAMEWORKS = UIKit Foundation
CrackLab_INSTALL_PATH = /Applications
CrackLab_CFLAGS = -fobjc-arc -I. -IUI -ICore
CrackLab_CODESIGN_FLAGS = -SCrackLab.entitlements

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/application.mk
