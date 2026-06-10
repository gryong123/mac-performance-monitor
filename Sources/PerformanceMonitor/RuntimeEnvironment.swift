import Foundation

enum RuntimeEnvironment {
    static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app" &&
            Bundle.main.bundleIdentifier != nil
    }
}
