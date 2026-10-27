# Xcode 16.4 / iOS 18.5 simulator workaround

The captured launch crash was DYLD / Library missing for `/usr/lib/swift/libswiftWebKit.dylib`, before onboarding code executed. This matches [WebKit bug 293831](https://bugs.webkit.org/show_bug.cgi?id=293831) and the [Apple Frameworks Engineer's accepted answer](https://developer.apple.com/forums/thread/785964).

Apple documents raising the deployment target for simulator builds to 18.4, or adding the simulator Cryptex library directory as a launch fallback. The CI UI command uses the former **only for the iOS 18.5 Simulator build**. The committed project and iPhoneOS Release IPA retain minimum iOS 18.0. No remote chart, copied system library or disabled test replaces the UI check.

Earlier failures from the crash are retained in Actions evidence. Device execution on older iOS versions is still a separate, unexecuted validation item. The intended primary iPhone 17 Pro must be tested after user signing.
