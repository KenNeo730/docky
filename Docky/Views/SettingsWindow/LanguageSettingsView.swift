//
//  LanguageSettingsView.swift
//  Docky
//
//  Picks the language Docky renders in. `.system` hands control back to the
//  macOS language preference; anything else is a Docky-only choice.

import SwiftUI

struct LanguageSettingsView: View {
    @State private var selection: AppLanguage = LanguageManager.shared.selected
    @State private var isRestarting = false

    private var isPending: Bool { selection != LanguageManager.shared.selected }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Language")
                .font(.system(size: 22, weight: .semibold))

            Text(L10n.text(
                "Pick the language Docky runs in. Choosing anything other than Follow System keeps Docky in that language even after you change the macOS language. The menu bar is rebuilt by the system, so Docky restarts to apply the change."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Picker("Language", selection: $selection) {
                ForEach(AppLanguage.allCases) { language in
                    Text(label(for: language)).tag(language)
                }
            }
            .pickerStyle(.radioGroup)

            if isPending {
                HStack(spacing: 10) {
                    if isRestarting {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                        Text(L10n.text("Restarting Docky…"))
                    } else {
                        Text(L10n.text("Docky will restart to apply this change."))
                        Spacer(minLength: 8)
                        Button(L10n.text("Restart Now")) { restart() }
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: 620, alignment: .leading)
        .onChange(of: selection) { _ in
            guard isPending else { return }
            isRestarting = true
            restart()
        }
    }

    private func label(for language: AppLanguage) -> String {
        language == .system ? L10n.text("Follow System") : L10n.text(language.endonym)
    }

    private func restart() {
        guard isPending else { return }
        LanguageManager.shared.selected = selection
        isRestarting = true
        LanguageManager.shared.relaunchAfterChange()
    }
}
