import ProjectDescription

let ghosttyXCFrameworkPath: Path = ".build/ghostty/GhosttyKit.xcframework"
let ghosttyResourcesPath: Path = ".build/ghostty/share/ghostty"
let ghosttyTerminfoPath: Path = ".build/ghostty/share/terminfo"
let ghosttyBuildScriptPath: Path = "scripts/build-ghostty.sh"
let verifyGitWtScriptPath: Path = "scripts/verify-git-wt.sh"
let zmxBuildScriptPath: Path = "scripts/build-zmx.sh"
let zmxBinaryPath: Path = ".build/zmx/bin/zmx"
let embedGhosttyResourcesScriptPath: Path = "scripts/embed-ghostty-resources.sh"
let embedRuntimeAssetsScriptPath: Path = "scripts/embed-runtime-assets.sh"

func shellScript(_ path: Path) -> String {
  "\"${SRCROOT}/\(path.pathString)\""
}

let ghosttyFingerprintInputScript = """
"${SRCROOT}/\(ghosttyBuildScriptPath.pathString)" --print-fingerprint
"""

let appResources: ResourceFileElements = [
  "p-term/AppIcon.icon",
  "p-term/Assets.xcassets",
  "p-term/notification.wav",
]

let appBuildableFolders: [BuildableFolder] = [
  "p-term/App",
  "p-term/Clients",
  "p-term/Commands",
  "p-term/Domain",
  "p-term/Features",
  "p-term/Infrastructure",
  "p-term/Support",
]

let appDependencies: [TargetDependency] = [
  .target(name: "PTermSettingsShared"),
  .target(name: "PTermSettingsFeature"),
  .target(name: "GhosttyKit"),
  .target(name: "p-term-cli"),
  .external(name: "ComposableArchitecture"),
  .external(name: "CustomDump"),
  .external(name: "Dependencies"),
  .external(name: "IdentifiedCollections"),
  .external(name: "Kingfisher"),
  .external(name: "OrderedCollections"),
  .external(name: "PostHog"),
  .external(name: "Sharing"),
  .external(name: "Sparkle"),
]

let testDependencies: [TargetDependency] = [
  .target(name: "GhosttyKit"),
  .target(name: "PTermSettingsShared"),
  .target(name: "PTermSettingsFeature"),
  .target(name: "p-term"),
  .external(name: "Clocks"),
  .external(name: "ComposableArchitecture"),
  .external(name: "ConcurrencyExtras"),
  .external(name: "CustomDump"),
  .external(name: "Dependencies"),
  .external(name: "DependenciesTestSupport"),
  .external(name: "IdentifiedCollections"),
  .external(name: "OrderedCollections"),
  .external(name: "Sharing"),
]

let embedGhosttyResourcesInputPaths: [FileListGlob] = [
  "$(SRCROOT)/\(ghosttyResourcesPath.pathString)",
  "$(SRCROOT)/\(ghosttyTerminfoPath.pathString)",
]

let embedGhosttyResourcesOutputPaths: [Path] = [
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/ghostty",
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/terminfo",
]

let embedRuntimeAssetsInputPaths: [FileListGlob] = [
  "$(SRCROOT)/Resources/git-wt/wt",
  "$(SRCROOT)/\(zmxBinaryPath.pathString)",
  "$(SRCROOT)/p-term/Resources/Themes/p-term Light",
  "$(SRCROOT)/p-term/Resources/Themes/p-term Dark",
  "$(BUILT_PRODUCTS_DIR)/p-term",
  "$(UNINSTALLED_PRODUCTS_DIR)/$(PLATFORM_NAME)/p-term",
]

let embedRuntimeAssetsOutputPaths: [Path] = [
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/git-wt/wt",
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/zmx/zmx",
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/p-term Light",
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/p-term Dark",
  "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/bin/p-term",
]

let project = Project(
  name: "p-term",
  settings: .settings(
    base: [
      "CLANG_ENABLE_MODULES": "YES",
      "CODE_SIGN_STYLE": "Automatic",
      "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
      "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
      "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
      "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
      "SWIFT_VERSION": "6.0",
    ],
    configurations: [
      .debug(name: .debug, xcconfig: "Configurations/Project.xcconfig"),
      .release(name: .release, xcconfig: "Configurations/Project.xcconfig"),
    ],
    defaultSettings: .essential
  ),
  targets: [
    .target(
      name: "p-term-cli",
      destinations: .macOS,
      product: .commandLineTool,
      bundleId: "app.prjct.p-term.cli",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .default,
      buildableFolders: [
        "p-term-cli",
      ],
      dependencies: [
        .external(name: "ArgumentParser"),
      ],
      settings: .settings(
        base: [
          "CODE_SIGNING_ALLOWED": "NO",
          "ENABLE_HARDENED_RUNTIME": "YES",
          "PRODUCT_MODULE_NAME": "p_term_cli",
          "PRODUCT_NAME": "p-term",
          "SKIP_INSTALL": "YES",
          "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
        ],
        defaultSettings: .essential
      )
    ),
    .foreignBuild(
      name: "GhosttyKit",
      destinations: .macOS,
      script: """
        "${SRCROOT}/\(ghosttyBuildScriptPath.pathString)"
        """,
      inputs: [
        .file("mise.toml"),
        .file(ghosttyBuildScriptPath),
        .script(ghosttyFingerprintInputScript),
      ],
      output: .xcframework(path: ghosttyXCFrameworkPath, linking: .static)
    ),
    .target(
      name: "PTermSettingsShared",
      destinations: .macOS,
      product: .staticFramework,
      bundleId: "app.prjct.p-term.settings-shared",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .default,
      buildableFolders: [
        "PTermSettingsShared",
      ],
      dependencies: [
        .external(name: "ComposableArchitecture"),
        .external(name: "Dependencies"),
        .external(name: "PostHog"),
        .external(name: "Sharing"),
      ],
      settings: .settings(
        base: [
          "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
        ],
        defaultSettings: .essential
      )
    ),
    .target(
      name: "PTermSettingsFeature",
      destinations: .macOS,
      product: .staticFramework,
      bundleId: "app.prjct.p-term.settings-feature",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .default,
      buildableFolders: [
        "PTermSettingsFeature",
      ],
      dependencies: [
        .target(name: "PTermSettingsShared"),
        .external(name: "ComposableArchitecture"),
        .external(name: "Dependencies"),
        .external(name: "Sharing"),
      ],
      settings: .settings(
        base: [
          "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
        ],
        defaultSettings: .essential
      )
    ),
    .target(
      name: "p-term",
      destinations: .macOS,
      product: .app,
      bundleId: "app.prjct.p-term",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .file(path: "p-term/Info.plist"),
      resources: appResources,
      buildableFolders: appBuildableFolders,
      scripts: [
        .pre(
          script: shellScript(verifyGitWtScriptPath),
          name: "Verify git-wt",
          basedOnDependencyAnalysis: false
        ),
        .pre(
          script: shellScript(zmxBuildScriptPath),
          name: "Build zmx",
          basedOnDependencyAnalysis: false
        ),
        .post(
          script: shellScript(embedGhosttyResourcesScriptPath),
          name: "Embed Ghostty Resources",
          inputPaths: embedGhosttyResourcesInputPaths,
          outputPaths: embedGhosttyResourcesOutputPaths,
          basedOnDependencyAnalysis: false
        ),
        .post(
          script: shellScript(embedRuntimeAssetsScriptPath),
          name: "Embed Runtime Assets",
          inputPaths: embedRuntimeAssetsInputPaths,
          outputPaths: embedRuntimeAssetsOutputPaths,
          basedOnDependencyAnalysis: false
        ),
      ],
      dependencies: appDependencies,
      settings: .settings(
        base: [
          "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
          "ENABLE_HARDENED_RUNTIME": "YES",
          "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
          "OTHER_LDFLAGS": "$(inherited) -lc++",
          "PRODUCT_NAME": "prjct",
          // Keep the Swift module name stable across the p-term -> prjct product
          // rename so `@testable import p_term` (123 test files + other targets)
          // keeps resolving. The bundle/app is still `prjct` via PRODUCT_NAME.
          "PRODUCT_MODULE_NAME": "p_term",
        ],
        debug: [
          "CODE_SIGN_ENTITLEMENTS": "p-term/p-termDebug.entitlements",
        ],
        release: [
          "CODE_SIGN_ENTITLEMENTS": "p-term/p-term.entitlements",
        ],
        defaultSettings: .essential
      )
    ),
    .target(
      name: "p-termTests",
      destinations: .macOS,
      product: .unitTests,
      bundleId: "app.prjct.p-termTests",
      deploymentTargets: .macOS("26.1"),
      infoPlist: .default,
      buildableFolders: [
        "p-termTests",
      ],
      dependencies: testDependencies,
      settings: .settings(
        base: [
          "BUNDLE_LOADER": "$(TEST_HOST)",
          "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/prjct.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/prjct",
        ],
        defaultSettings: .essential
      )
    ),
  ],
  additionalFiles: [
    "Configurations/**",
  ],
  resourceSynthesizers: []
)
