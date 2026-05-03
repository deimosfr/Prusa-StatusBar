import Foundation

/// Single accessor for the running app's marketing version and build
/// number. Reads from `Bundle.main` so the underlying value comes from
/// the `MARKETING_VERSION` build setting (defined in `project.yml`),
/// substituted into `Info.plist` at build time. Centralised here so call
/// sites do not duplicate the `Bundle.main.infoDictionary` lookup.
public enum AppVersion {
    /// Raw `CFBundleShortVersionString` (e.g. `"0.9.0"`). `nil` only when
    /// the running bundle is unusual (e.g. during a unit test that does
    /// not embed an Info.plist).
    public static var shortString: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Raw `CFBundleVersion` (the build number, e.g. `"1"`).
    public static var buildNumber: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    /// Parsed semantic representation of `shortString`, or `nil` when the
    /// value is missing or not parseable.
    public static var semantic: SemanticVersion? {
        shortString.flatMap(SemanticVersion.init)
    }
}
