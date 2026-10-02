# Internationalization

Docky ships English as its source language and uses Apple's standard string
catalog (`Docky/Localizable.xcstrings`) for everything the SwiftUI layer renders.
This document explains how to add a language, and which call sites need manual
attention because their APIs do not accept a `LocalizedStringKey`.

## How localization works here

| Surface | Mechanism | Needs manual work? |
|---|---|---|
| `Text`, `Button`, `Label`, `Toggle`, `Picker`, `Section`, `TextField`, `Menu`, `Link` | SwiftUI resolves the literal as a `LocalizedStringKey` against the catalog | No |
| `NSAlert` (`messageText`, `informativeText`, `addButton(withTitle:)`) | `String`-based API | Yes — wrap in `L10n.text(_:)` |
| `NSMenuItem(title:)`, `NSMenu(title:)` | `String`-based API | Yes |
| `View.help(_:)`, `View.navigationTitle(_:)` | Takes `StringProtocol`; the literal is **not** localized | Yes |
| `View.accessibilityLabel(_:)` | `String`-based API | Yes |
| Action / package titles from `MenuCatalog/*.json` | Runtime data, not part of the catalog | Yes — handled in `MenuCatalogService.resolvedTitle(for:context:)` |
| `MainMenu.xib` | Base Internationalization | Yes — add `<lang>.lproj/MainMenu.strings` |

`L10n` (`Docky/Services/L10n.swift`) is the thin helper for the `String` cases.
It falls back to the key itself when a translation is missing, so a partial
translation degrades to readable English rather than a blank label.

## Adding a language

1. **Open the catalog.** In Xcode, select `Localizable.xcstrings` → the
   `+` in the inspector → *Add Language*. Xcode registers the region in
   `knownRegions` for you.
2. **Translate the app strings.** Fill in the new language column. Keys are
   plain English sentences, and the `comment` on each key explains the context
   (what the arguments mean, where the string appears).
3. **Translate the main menu.** Duplicate an existing localization as a
   starting point — `es.lproj/MainMenu.strings` is the reference:

   ```
   cp Docky/es.lproj/MainMenu.strings Docky/<lang>.lproj/MainMenu.strings
   ```

   Each entry is keyed by the XIB ObjectID (for example
   `"5kV-Vb-QxS.title" = "About Docky";`). The ObjectIDs must not change; only
   the values do. The app-menu title (`1Xt-HY-uBw`) and any product name should
   stay untranslated.
4. **Add the region** if Xcode did not already: add the language code to
   `knownRegions` in `Docky.xcodeproj/project.pbxproj`.

No code changes are needed — the target uses
`PBXFileSystemSynchronizedRootGroup`, so new `.lproj` folders are picked up
automatically.

## Placeholders

Format specifiers must survive translation untouched, in the same **type**:

- `%@` — `String` (or any object)
- `%lld` — `Int` / `Int64`

Two rules matter:

1. **Never renumber blindly.** If the translated word order differs from the
   English, use explicit positional specifiers (`%1$@`, `%2$lld`) so each
   argument lands in the right place. Keep the specifier *type* attached to the
   same argument as the original — swapping `%1$@` and `%2$lld` produces
   garbage.
2. **Chinese reordering example.** `"Step %lld of %lld"` takes the current step
   first and the total second. The correct Chinese translation is
   `"第 %1$lld 步，共 %2$lld 步"` — same order as the source, explicitly
   numbered to make the binding unambiguous.

## Adding new user-facing strings

- **In a SwiftUI view**, just write the literal: `Text("Add Widget")`. Xcode
  extracts it into the catalog on build. Then add the new language's
  translation.
- **Anywhere that takes a `String`**, use `L10n.text(_:)`:

  ```swift
  alert.messageText = L10n.text("Could not import theme")
  alert.addButton(withTitle: L10n.text("OK"))
  .help(L10n.text("Reveal in Finder"))
  ```

  With arguments, pass them through:

  ```swift
  alert.informativeText = L10n.text("Show More (%lld)", overflowCount)
  ```

- **For a new catalog action**, add an `action.<id>` key so the title can be
  translated without touching `actions.json`, and route it through
  `L10n.catalogText(id:fallback:)`. If the action has an `alternateTitle`, use
  `action.<id>.option` for it.
