from pathlib import Path
root = Path(__file__).resolve().parent.parent
project = '''// !$*UTF8*$!
{
 archiveVersion = 1;
 classes = {};
 objectVersion = 77;
 objects = {
  A00000000000000000000001 = {isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700;}; buildConfigurationList = A00000000000000000000002; compatibilityVersion = "Xcode 16.0"; developmentRegion = ru; hasScannedForEncodings = 0; knownRegions = (ru, en, uk, Base); mainGroup = A00000000000000000000003; packageReferences = (A00000000000000000000020); preferredProjectObjectVersion = 77; productRefGroup = A00000000000000000000004; projectDirPath = ""; projectRoot = ""; targets = (A00000000000000000000005, B00000000000000000000001);};
  A00000000000000000000002 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000010, A00000000000000000000011); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
  A00000000000000000000003 = {isa = PBXGroup; children = (A00000000000000000000006, B00000000000000000000002, A00000000000000000000004); sourceTree = "<group>";};
  A00000000000000000000004 = {isa = PBXGroup; children = (A00000000000000000000007, B00000000000000000000003); name = Products; sourceTree = "<group>";};
  A00000000000000000000005 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000008; buildPhases = (A00000000000000000000030, A00000000000000000000031, A00000000000000000000032); buildRules = (); dependencies = (); fileSystemSynchronizedGroups = (A00000000000000000000006); name = Polka; packageProductDependencies = (A00000000000000000000021, A00000000000000000000022); productName = Polka; productReference = A00000000000000000000007; productType = "com.apple.product-type.application";};
  A00000000000000000000006 = {isa = PBXFileSystemSynchronizedRootGroup; path = App; sourceTree = "<group>";};
  A00000000000000000000007 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Polka.app; sourceTree = BUILT_PRODUCTS_DIR;};
  A00000000000000000000008 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000012, A00000000000000000000013); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
  A00000000000000000000010 = {isa = XCBuildConfiguration; buildSettings = {CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; ONLY_ACTIVE_ARCH = YES;}; name = Debug;};
  A00000000000000000000011 = {isa = XCBuildConfiguration; buildSettings = {CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0;}; name = Release;};
  A00000000000000000000012 = {isa = XCBuildConfiguration; buildSettings = {BASE_SETTINGS SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;}; name = Debug;};
  A00000000000000000000013 = {isa = XCBuildConfiguration; buildSettings = {BASE_SETTINGS SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";}; name = Release;};
  A00000000000000000000020 = {isa = XCLocalSwiftPackageReference; relativePath = .;};
  A00000000000000000000021 = {isa = XCSwiftPackageProductDependency; package = A00000000000000000000020; productName = LibraryCore;};
  A00000000000000000000022 = {isa = XCSwiftPackageProductDependency; package = A00000000000000000000020; productName = BookCatalog;};
  A00000000000000000000023 = {isa = PBXBuildFile; productRef = A00000000000000000000021;};
  A00000000000000000000024 = {isa = PBXBuildFile; productRef = A00000000000000000000022;};
  B00000000000000000000001 = {isa = PBXNativeTarget; buildConfigurationList = B00000000000000000000004; buildPhases = (B00000000000000000000005, B00000000000000000000006); buildRules = (); dependencies = (B00000000000000000000007); fileSystemSynchronizedGroups = (B00000000000000000000002); name = PolkaUITests; productName = PolkaUITests; productReference = B00000000000000000000003; productType = "com.apple.product-type.bundle.ui-testing";};
  B00000000000000000000002 = {isa = PBXFileSystemSynchronizedRootGroup; path = UITests; sourceTree = "<group>";};
  B00000000000000000000003 = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = PolkaUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;};
  B00000000000000000000004 = {isa = XCConfigurationList; buildConfigurations = (B00000000000000000000010, B00000000000000000000011); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
  B00000000000000000000005 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
  B00000000000000000000006 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
  B00000000000000000000007 = {isa = PBXTargetDependency; target = A00000000000000000000005; targetProxy = B00000000000000000000008;};
  B00000000000000000000008 = {isa = PBXContainerItemProxy; containerPortal = A00000000000000000000001; proxyType = 1; remoteGlobalIDString = A00000000000000000000005; remoteInfo = Polka;};
  B00000000000000000000010 = {isa = XCBuildConfiguration; buildSettings = {CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = com.bookslibrary.polka.uitests; PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = "1,2"; TEST_TARGET_NAME = Polka; SWIFT_OPTIMIZATION_LEVEL = "-Onone";}; name = Debug;};
  B00000000000000000000011 = {isa = XCBuildConfiguration; buildSettings = {CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = com.bookslibrary.polka.uitests; PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = "1,2"; TEST_TARGET_NAME = Polka;}; name = Release;};
  A00000000000000000000030 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
  A00000000000000000000031 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (A00000000000000000000023, A00000000000000000000024); runOnlyForDeploymentPostprocessing = 0;};
  A00000000000000000000032 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
 };
 rootObject = A00000000000000000000001;
}
'''
settings = '''ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor; CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = 97W729H996; CURRENT_PROJECT_VERSION = 12; ENABLE_PREVIEWS = YES; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = "Bookreign"; INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO; INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.books"; INFOPLIST_KEY_NSCameraUsageDescription = "Камера нужна для сканирования ISBN и фотографирования обложки книги."; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"; MARKETING_VERSION = 1.0.0; PRODUCT_BUNDLE_IDENTIFIER = com.bookslibrary.polka; PRODUCT_NAME = "$(TARGET_NAME)"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; TARGETED_DEVICE_FAMILY = "1,2"; SWIFT_EMIT_LOC_STRINGS = YES;'''
(root/'Polka.xcodeproj/project.pbxproj').write_text(project.replace('BASE_SETTINGS',settings))
(root/'Polka.xcodeproj/xcshareddata/xcschemes/Polka.xcscheme').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000005" BuildableName="Polka.app" BlueprintName="Polka" ReferencedContainer="container:Polka.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="B00000000000000000000001" BuildableName="PolkaUITests.xctest" BlueprintName="PolkaUITests" ReferencedContainer="container:Polka.xcodeproj"/></TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000005" BuildableName="Polka.app" BlueprintName="Polka" ReferencedContainer="container:Polka.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000005" BuildableName="Polka.app" BlueprintName="Polka" ReferencedContainer="container:Polka.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
