THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:15.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Spider

Spider_FILES = AppDelegate.m main.m UI/IPTheme.m UI/IPComponents.m UI/MainViewController.m UI/GlassIPACell.m UI/AppDetailsViewController.m UI/IPAExportProgressView.m UI/IPAFileBrowserViewController.m UI/IPAUnpackViewController.m UI/IPAFileCardCell.m UI/IPAArchiveBrowserViewController.m UI/IPAInstallViewController.m UI/InstallationProgressViewController.m UI/InstalledAppsViewController.m UI/SettingsViewController.m UI/SigningPlanReportViewController.m Core/IPAArchiveExtractor.m Core/IPAMultiInstancePreparer.m Core/DirectInstallationProvider.m Core/InstallationEngine.m Core/InstallationProvider.m Core/ApplicationManager.m Core/DependencyManager.m Core/IPAValidator.m Core/IPAExtractor.m Core/CommandResult.m Core/ExecutableCapability.m Core/ExecutableValidator.m Core/Capability.m Core/ProcessRunner.m Core/RuntimeEnvironment.m Core/CapabilityManager.m Core/RootlessManager.m Core/JailbreakEnvironment.m Core/VerificationEngine.m Core/Logger.m Core/OperationLog.m Core/OperationRecord.m Core/RuntimeDiagnostics.m Core/MachOAnalyzer.m Core/MachORPathRepair.m Core/IPAStructuralResult.m Core/IPAStructuralAnalyzer.m Core/SigningTarget.m Core/EntitlementSet.m Core/SigningPlan.m Core/SignatureAnalyzer.m Core/SigningPlanner.m Core/IPAExportManager.m Core/SpiderInstallationGraph.m Core/ForensicTypes.m Core/ForensicInstallationObserver.m Core/ForensicDifferentialAnalyzer.m Core/ForensicRegistrationProbe.m Core/ForensicInstallationPipeline.m Core/LiveOperationStream.m Core/InstallationTransactionCoordinator.m \
		UI/JBHideViewController.m Core/JBHide/SpiderJBHideStateStore.m Core/JBHide/SpiderInstalledAppsStore.m Core/JBHide/SpiderManagedAppsRegistry.m Core/JBHide/SpiderJBHideEngine.m

Spider_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore UniformTypeIdentifiers
Spider_PRIVATE_FRAMEWORKS = MobileCoreServices
Spider_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -I./Core -fno-autolink
Spider_CODESIGN_FLAGS = -Sentitlements.plist

LIBRARY_NAME = libspiderjbhide

libspiderjbhide_FILES = JBHideDylib/spider_jbhide.m
libspiderjbhide_INSTALL_PATH = /Applications/Spider.app
libspiderjbhide_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/library.mk

include $(THEOS_MAKE_PATH)/application.mk

TOOL_NAME = ipainstallerpro_helper

ipainstallerpro_helper_FILES = helper.c
ipainstallerpro_helper_CFLAGS = -fobjc-arc
ipainstallerpro_helper_CODESIGN_FLAGS = -Sentitlements.plist
ipainstallerpro_helper_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
