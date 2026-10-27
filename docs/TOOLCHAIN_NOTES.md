# Current toolchain: Xcode 26.2 / iOS 26.2

CI now pins the installed stable Xcode 26.2 and iPhone 17 Pro / iOS 26.2 simulator. The previous iOS 18.5 two-round run retained repeated XCTest animation-notification stalls, runner restarts and termination errors; it is not declared passed. All cases, repetitions, animations and numerical acceptance gates remain enabled. A newer runtime result does not validate the older runtime. iPhoneOS and Simulator builds retain the project minimum iOS 18.0.

The official runner software snapshot is [macos-15-arm64/20260907.0337](https://github.com/actions/runner-images/blob/macos-15-arm64/20260907.0337/images/macos/macos-15-arm64-Readme.md). It lists Xcode 26.2, iOS 26.2 and iPhone 17 Pro. Run 40517887202 passed focused order x2 and all nine UI cases x2. Full results are in TEST_REPORT.md.

The earlier simulator-only deployment override is removed for the new SDK/runtime. The original workaround and its evidence are retained below as historical context.

# Xcode 16.4 / iOS 18.5 simulator workaround

The captured launch crash was DYLD / Library missing for `/usr/lib/swift/libswiftWebKit.dylib`, before onboarding code executed. This matches [WebKit bug 293831](https://bugs.webkit.org/show_bug.cgi?id=293831) and the [Apple Frameworks Engineer's accepted answer](https://developer.apple.com/forums/thread/785964).

Apple documents raising the deployment target for simulator builds to 18.4, or adding the simulator Cryptex library directory as a launch fallback. The historical CI UI command used the former **only for the iOS 18.5 Simulator build**. The committed project and iPhoneOS Release IPA retain minimum iOS 18.0. No remote chart, copied system library or disabled test replaces the UI check.

Earlier failures from the crash are retained in Actions evidence. Device execution on older iOS versions is still a separate, unexecuted validation item. The intended primary iPhone 17 Pro must be tested after user signing.
