#!/usr/bin/env python3
"""Deterministically regenerate the committed Xcode project; no external generator needed."""
import pathlib,hashlib,json
R=pathlib.Path(__file__).resolve().parents[1]
def ident(s):return hashlib.sha256(s.encode()).hexdigest()[:24].upper()
objects={}
def add(key,body):objects[ident(key)]=body;return ident(key)
def ref(k):return ident(k)
def quote(s):return json.dumps(str(s),ensure_ascii=False)
files=sorted((R/'ChaiTrade').rglob('*.swift'))
ui=sorted((R/'ChaiTradeUITests').rglob('*.swift'))
for f in files+ui:
 p=str(f.relative_to(R));add(p,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(p)}; sourceTree = SOURCE_ROOT;')
 add('build:'+p,f'isa = PBXBuildFile; fileRef = {ref(p)};')
add('resources','isa = PBXFileReference; lastKnownFileType = folder; path = ChaiTrade/Resources/ChartWeb; sourceTree = SOURCE_ROOT;')
add('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = ChaiTrade/Assets.xcassets; sourceTree = SOURCE_ROOT;')
add('assets-build',f'isa = PBXBuildFile; fileRef = {ref("assets")};')
add('licenses','isa = PBXFileReference; lastKnownFileType = folder; path = ChaiTrade/Resources/Licenses; sourceTree = SOURCE_ROOT;')
add('licenses-build',f'isa = PBXBuildFile; fileRef = {ref("licenses")};')
add('resources-build',f'isa = PBXBuildFile; fileRef = {ref("resources")};')
add('app-product','isa = PBXFileReference; explicitFileType = wrapper.application; path = ChaiTrade.app; sourceTree = BUILT_PRODUCTS_DIR;')
add('ui-product','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = ChaiTradeUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
add('package','isa = XCLocalSwiftPackageReference; relativePath = Packages/ChaiTradeCore;')
add('core',f'isa = XCSwiftPackageProductDependency; package = {ref("package")}; productName = ChaiTradeCore;')
add('core-build',f'isa = PBXBuildFile; productRef = {ref("core")};')
add('products',f'isa = PBXGroup; children = ({ref("app-product")},{ref("ui-product")}); name = Products; sourceTree = "<group>";')
add('main',f'isa = PBXGroup; children = ({",".join(ref(str(f.relative_to(R))) for f in files+ui)},{ref("resources")},{ref("licenses")},{ref("assets")},{ref("products")}); sourceTree = "<group>";')
for name,items in [('sources',[ref('build:'+str(f.relative_to(R))) for f in files]),('ui-sources',[ref('build:'+str(f.relative_to(R))) for f in ui])]:
 add(name,f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(items)}); runOnlyForDeploymentPostprocessing = 0;')
add('resource-phase',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({ref("resources-build")},{ref("licenses-build")},{ref("assets-build")}); runOnlyForDeploymentPostprocessing = 0;')
add('frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({ref("core-build")}); runOnlyForDeploymentPostprocessing = 0;')
add('ui-frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
common={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'18.0','SWIFT_VERSION':'6.0','SWIFT_STRICT_CONCURRENCY':'complete','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','TARGETED_DEVICE_FAMILY':'1','DEVELOPMENT_TEAM':'','CODE_SIGN_STYLE':'Automatic','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @loader_path/Frameworks','ENABLE_DEBUG_DYLIB':'NO'}
for scope in ['project','app','ui']:
 for config in ['Debug','Release']:
  s=dict(common)
  s.update({'DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym' if config=='Release' else 'dwarf','SWIFT_OPTIMIZATION_LEVEL':'-O' if config=='Release' else '-Onone','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if config=='Debug' else ''})
  if scope=='app':s.update({'PRODUCT_BUNDLE_IDENTIFIER':'org.chaitrade.app','PRODUCT_NAME':'$(TARGET_NAME)','INFOPLIST_FILE':'ChaiTrade/Info.plist','GENERATE_INFOPLIST_FILE':'NO','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'1.0.0','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor'})
  if scope=='ui':s.update({'PRODUCT_BUNDLE_IDENTIFIER':'org.chaitrade.app.uitests','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES','TEST_TARGET_NAME':'ChaiTrade'})
  add(scope+config,'isa = XCBuildConfiguration; buildSettings = {'+' '.join(f'{k} = {quote(v)};' for k,v in s.items())+'}; name = '+config+';')
 add(scope+'configs',f'isa = XCConfigurationList; buildConfigurations = ({ref(scope+"Debug")},{ref(scope+"Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('app',f'isa = PBXNativeTarget; buildConfigurationList = {ref("appconfigs")}; buildPhases = ({ref("sources")},{ref("frameworks")},{ref("resource-phase")}); buildRules = (); dependencies = (); name = ChaiTrade; packageProductDependencies = ({ref("core")}); productName = ChaiTrade; productReference = {ref("app-product")}; productType = "com.apple.product-type.application";')
add('proxy',f'isa = PBXContainerItemProxy; containerPortal = {ref("project")}; proxyType = 1; remoteGlobalIDString = {ref("app")}; remoteInfo = ChaiTrade;')
add('depends',f'isa = PBXTargetDependency; target = {ref("app")}; targetProxy = {ref("proxy")};')
add('ui',f'isa = PBXNativeTarget; buildConfigurationList = {ref("uiconfigs")}; buildPhases = ({ref("ui-sources")},{ref("ui-frameworks")}); buildRules = (); dependencies = ({ref("depends")}); name = ChaiTradeUITests; productName = ChaiTradeUITests; productReference = {ref("ui-product")}; productType = "com.apple.product-type.bundle.ui-testing";')
add('project',f'isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 1640; LastUpgradeCheck = 1640; TargetAttributes = {{{ref("app")} = {{CreatedOnToolsVersion = 16.4;}};{ref("ui")} = {{CreatedOnToolsVersion = 16.4; TestTargetID = {ref("app")};}};}};}}; buildConfigurationList = {ref("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hant"; hasScannedForEncodings = 0; knownRegions = (en,"zh-Hant",Base); mainGroup = {ref("main")}; productRefGroup = {ref("products")}; projectDirPath = ""; projectRoot = ""; packageReferences = ({ref("package")}); targets = ({ref("app")},{ref("ui")});')
p=R/'ChaiTrade.xcodeproj';p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = {'+v+'};' for k,v in objects.items())+'\n}; rootObject = '+ref('project')+';}\n')
scheme=p/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
def buildref(name,key,product):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(key)}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:ChaiTrade.xcodeproj"/>'
app=buildref('ChaiTrade','app','ChaiTrade.app');test=buildref('ChaiTradeUITests','ui','ChaiTradeUITests.xctest')
(scheme/'ChaiTrade.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1640" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated',len(files),'app source references')
