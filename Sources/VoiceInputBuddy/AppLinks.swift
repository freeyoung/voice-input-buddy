import Foundation

enum AppLinks {
    static let githubRepository = URL(
        string: "https://github.com/zfdang/voice-input-buddy"
    )!
    static let chineseWebsite = URL(string: "https://github.com/zfdang/voice-input-buddy")!
    static let englishWebsite = URL(string: "https://github.com/zfdang/voice-input-buddy")!
    static let chineseIOSAppStore = URL(
        string: "https://github.com/zfdang/voice-input-buddy"
    )!
    static let englishIOSAppStore = URL(
        string: "https://github.com/zfdang/voice-input-buddy"
    )!
    static let feedback = URL(
        string: "https://github.com/zfdang/voice-input-buddy"
    )!
    static let doubaoInputMethod = URL(
        string: "https://shurufa.doubao.com/"
    )!
    static let vokieWebsite = URL(string: "https://vokie.com/")!

    static func iOSAppStore(for locale: Locale) -> URL {
        locale.identifier.lowercased().hasPrefix("zh")
            ? chineseIOSAppStore
            : englishIOSAppStore
    }

    static func website(for locale: Locale) -> URL {
        locale.identifier.lowercased().hasPrefix("zh")
            ? chineseWebsite
            : englishWebsite
    }
}
