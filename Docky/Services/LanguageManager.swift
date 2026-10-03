//
//  LanguageManager.swift
//  Docky
//
//  Lets the user pick Docky's language inside the app instead of following the
//  system-wide macOS language.
//
//  How it works
//  ------------
//  SwiftUI resolves `Text("some literal")` through
//  `Bundle.main.localizedString(forKey:value:table:)`, as do `NSAlert`,
//  `NSMenuItem`, `.help()`, `.navigationTitle()` and friends. Overriding that
//  single method therefore covers every surface at once — including the ones
//  that take a plain `String` and would otherwise never be translated.
//
//  The override resolves keys against `Contents/Resources/<region>.lproj/*.strings`,
//  which is where Xcode compiles `Localizable.xcstrings` and `MainMenu.strings`.
//  Anything the override can't find falls through to Foundation's real
//  implementation, so the behaviour is unchanged whenever no override is active
//  (the "Follow System" case) or a key has no translation yet.
//
//  Menu-bar titles coming from `MainMenu.xib` are frozen when the nib loads,
//  which happens before this app's delegate runs. Changing language therefore
//  restarts Docky; see `relaunchAfterChange()`.

import AppKit
import Foundation
import ObjectiveC

// MARK: - AppLanguage

/// Every language Docky can render in.
///
/// `.system` hands control back to the macOS language preference; every other
/// case is selected inside the app and outlives a language change of the OS.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case zhHans
    case zhHant
    case zhHK
    case fr
    case es

    var id: String { rawValue }

    /// Bundle region whose `.lproj` directory holds the strings for this language.
    var region: String {
        switch self {
        case .system: "Base"
        case .en: "en"
        case .zhHans: "zh-Hans"
        case .zhHant: "zh-Hant"
        case .zhHK: "zh-HK"
        case .fr: "fr"
        case .es: "es"
        }
    }

    /// The language's own name, so the picker stays readable in every locale.
    ///
    /// Passed through `L10n.text(_:)` — the endonyms live in the string catalog
    /// so they can be shown in Japanese or any other language Docky learns later.
    var endonym: String {
        switch self {
        case .system: ""
        case .en: "English"
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文（台灣）"
        case .zhHK: "繁體中文（香港）"
        case .fr: "Français"
        case .es: "Español"
        }
    }
}

// MARK: - LanguageManager

/// Owns the in-app language choice and installs the `Bundle.main` override.
final class LanguageManager {
    static let shared = LanguageManager()

    private static let storageKey = "preferredAppLanguage"

    private let defaults: UserDefaults

    private var tableCache: [String: [String: String]] = [:]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.storageKey) == nil {
            defaults.set(AppLanguage.system.rawValue, forKey: Self.storageKey)
        }
    }

    // MARK: Selection

    var selected: AppLanguage {
        get {
            AppLanguage(rawValue: defaults.string(forKey: Self.storageKey) ?? "") ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.storageKey)
        }
    }

    /// `nil` means "let macOS decide" — the override then stays out of the way.
    var overrideRegion: String? {
        selected == .system ? nil : selected.region
    }

    // MARK: Override

    private var overrideInstalled = false

    /// Replaces `Bundle.main.localizedString(forKey:value:table:)` with one that
    /// consults the selected language first. Safe to call more than once.
    ///
    /// Must run on the main thread. Call it at the top of
    /// `applicationDidFinishLaunching` so no string is resolved before it.
    func installOverride() {
        guard !overrideInstalled else { return }
        guard let method = class_getInstanceMethod(
            Bundle.self,
            #selector(Bundle.localizedString(forKey:value:table:))
        ) else { return }

        typealias OriginalIMP = @convention(c) (Bundle, Selector, String, String?, String?) -> String
        let original = unsafeBitCast(method_getImplementation(method), to: OriginalIMP.self)

        let selector = #selector(Bundle.localizedString(forKey:value:table:))
        let block: @convention(block) (Bundle, String, String?, String?) -> String = { bundle, key, value, table in
            if let hit = LanguageManager.shared.localized(key: key, value: value, table: table) {
                return hit
            }
            return original(bundle, selector, key, value, table)
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
        overrideInstalled = true
    }

    /// Resolves `key` against the selected language's `.strings` tables.
    /// Returns `nil` when the language follows the system or the key is absent,
    /// which hands the decision back to Foundation's own lookup.
    func localized(key: String, value: String?, table: String?) -> String? {
        guard let region = overrideRegion else { return nil }
        let name = table ?? "Localizable"

        guard let table = stringsTable(named: name, region: region) else { return nil }
        if let hit = table[key], !hit.isEmpty { return hit }

        // `Localizable.strings` lives in every region; for nib-driven tables such
        // as MainMenu fall back to the region's directory only.
        return nil
    }

    private func stringsTable(named name: String, region: String) -> [String: String]? {
        let cacheKey = "\(region)/\(name)"
        if let cached = tableCache[cacheKey] { return cached }

        let url = resourcesURL
            .appendingPathComponent("\(region).lproj")
            .appendingPathComponent("\(name).strings")

        // Two on-disk formats come out of the toolchain. `Localizable.strings`
        // is a property list — UTF-16 XML, which Foundation decodes but
        // `String(contentsOf:encoding:)` cannot read. `MainMenu.strings` stays
        // the plain `"key" = "value";` text format. Try the plist first and
        // fall back to the text parser so both survive.
        let table: [String: String]
        if let plist = NSDictionary(contentsOf: url) as? [String: String] {
            table = plist
        } else if let raw = try? String(contentsOf: url, encoding: .utf8) {
            table = Self.parseStrings(raw)
        } else {
            table = [:]
        }

        tableCache[cacheKey] = table
        return table
    }

    private var resourcesURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents").appendingPathComponent("Resources")
    }

    // MARK: Restart

    /// The main menu is built from a nib that is already loaded by the time this
    /// app runs, so a language change only lands cleanly on a fresh launch.
    func relaunchAfterChange() {
        let bundlePath = Bundle.main.bundlePath
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            try? NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: bundlePath),
                configuration: configuration
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: Parsing

    /// Reads `"key" = "value";` pairs out of a `.strings` file.
    ///
    /// Comments are ignored; only the `key = value` lines matter, and escapes
    /// such as `\"` and `\n` are resolved the way `genstrings` writes them.
    private static func parseStrings(_ raw: String) -> [String: String] {
        var table: [String: String] = [:]
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            // An entry line is `"key" = "value";`. Splitting on the single `=`
            // avoids a regex whose escape layer is impossible to keep honest,
            // and the quotes around both halves reject comment lines.
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasSuffix(";"), let equals = line.firstIndex(of: "=") else { continue }

            let lhs = line[..<equals].trimmingCharacters(in: .whitespaces)
            var rhs = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if rhs.hasSuffix(";") { rhs = String(rhs.dropLast()) }

            guard lhs.hasPrefix("\""), lhs.hasSuffix("\""),
                  rhs.hasPrefix("\""), rhs.hasSuffix("\"")
            else { continue }

            let key = unescape(String(lhs.dropFirst().dropLast()))
            let value = unescape(String(rhs.dropFirst().dropLast()))
            if !key.isEmpty { table[key] = value }
        }
        return table
    }

    private static func unescape(_ token: String) -> String {
        // Drops the surrounding quotes and resolves the escapes inside.
        var body = token
        if body.hasPrefix("\""), body.hasSuffix("\"") {
            body = String(body.dropFirst().dropLast())
        }

        var out = ""
        var chars = Array(body)
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if character == "\\", index + 1 < chars.count {
                let escape = chars[index + 1]
                switch escape {
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                case "0": out.append("\0")
                case "U": out.append("\\U")
                case "u": out.append("\\u")
                default: out.append(escape)
                }
                index += 2
            } else {
                out.append(character)
                index += 1
            }
        }
        return out
    }
}
