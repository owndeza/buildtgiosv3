load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "PeerInfoCoverComponent",
    module_name = "PeerInfoCoverComponent",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/AccountContext",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/MultiAnimationRenderer",
        "//submodules/TelegramUI/Components/AnimationCache",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/Components/HierarchyTrackingLayer",
        "//submodules/TelegramUI/Components/EmojiTextAttachmentView",
        "//submodules/Utils/LokiRng",
        "//submodules/TextFormat",
        "//submodules/AvatarNode",
        "//submodules/Components/BundleIconComponent",
        "//submodules/TelegramUI/Components/PeerInfo/PeerInfoPaneNode",
        "//submodules/TelegramStringFormatting",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "PeerInfoCoverComponentTestsLib",
    testonly = True,
    srcs = glob(["Tests/**/*.swift"]),
    deps = [":PeerInfoCoverComponent"],
)

ios_test_runner(
    name = "PeerInfoCoverComponentTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "PeerInfoCoverComponentTests",
    minimum_os_version = "15.0",
    runner = ":PeerInfoCoverComponentTestRunner",
    deps = [":PeerInfoCoverComponentTestsLib"],
    visibility = ["//visibility:public"],
)
