import SwiftUI

/// Me isn't a tab any more (the Academy took its place, owner 2026-11-17):
/// it opens from this round button at the top left of every main tab.
struct OpenMeAction {
    let run: () -> Void
    func callAsFunction() { run() }
}

private struct OpenMeKey: EnvironmentKey {
    static var defaultValue: OpenMeAction? { nil }
}

extension EnvironmentValues {
    var openMe: OpenMeAction? {
        get { self[OpenMeKey.self] }
        set { self[OpenMeKey.self] = newValue }
    }
}

/// The athlete's initial in a glass circle; opens Me.
struct ProfileButton: View {
    let name: String?
    @Environment(\.openMe) private var openMe

    private var initial: String? {
        guard let first = name?.trimmingCharacters(in: .whitespaces).first else { return nil }
        return String(first).uppercased()
    }

    var body: some View {
        if let openMe {
            Button { openMe() } label: {
                Group {
                    if let initial {
                        Text(initial).font(.headline.weight(.bold))
                    } else {
                        Image(systemName: "person.fill").font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(AppTheme.ink)
                .frame(width: 40, height: 40)
                .glassCapsule()
                .overlay { Circle().strokeBorder(AppTheme.brightRed.opacity(0.35), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Me: profile and settings")
        }
    }
}

/// A row holding just the profile button, for tabs without a top bar of their own.
struct ProfileButtonBar: View {
    let name: String?

    var body: some View {
        HStack {
            ProfileButton(name: name)
            Spacer()
        }
    }
}
