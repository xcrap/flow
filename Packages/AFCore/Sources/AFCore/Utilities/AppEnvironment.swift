import Foundation

public enum AppEnvironment {
    public static var appSupportDirectoryName: String {
        #if DEBUG
        "Flow-Dev"
        #else
        "Flow"
        #endif
    }
}
