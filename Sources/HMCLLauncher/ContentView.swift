import LauncherKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: LauncherViewModel

    var body: some View {
        LauncherShell(model: model)
            .task { await model.refreshLatest() }
    }
}

/// The window without the startup version check, so the screenshot renderer can
/// draw the real views without touching the network.
struct LauncherShell: View {
    @Bindable var model: LauncherViewModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(mode: $model.mode)
            Divider().overlay(Palette.hairline)

            switch model.mode {
            case .simple:
                SimpleModeView(model: model)
            case .advanced:
                AdvancedModeView(model: model)
            }
        }
        .frame(width: model.mode == .simple ? 340 : 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct HeaderBar: View {
    @Binding var mode: UIMode

    var body: some View {
        HStack(spacing: 8) {
            Text("HMCL")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Picker("View", selection: $mode) {
                Text("Simple").tag(UIMode.simple)
                Text("Advanced").tag(UIMode.advanced)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Shared pieces

struct VersionHeadline: View {
    let latestVersion: String?
    let note: String?

    var body: some View {
        VStack(spacing: 2) {
            Text("Latest release")
                .font(TypeScale.eyebrow)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(latestVersion ?? "—")
                    .font(TypeScale.version)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ReadinessStrip: View {
    let hasLauncher: Bool
    let hasRuntime: Bool

    var body: some View {
        HStack(spacing: 14) {
            ReadinessDot(label: "HMCL", isReady: hasLauncher)
            ReadinessDot(label: "Java", isReady: hasRuntime)
        }
    }
}

struct StartButton: View {
    @Bindable var model: LauncherViewModel

    var body: some View {
        Button {
            Task { await model.start() }
        } label: {
            Text(model.startButtonTitle)
        }
        .buttonStyle(StartButtonStyle(enabled: !model.activity.isBusy))
        .disabled(model.activity.isBusy)
        .keyboardShortcut(.defaultAction)
    }
}

/// HMCL hides offline login outside mainland China. This adds the one system
/// property that turns it back on. It does not make an offline account work on
/// an online-mode server, so the label says accounts, not "offline mode".
struct OfflineAccountsToggle: View {
    @Binding var isOn: Bool
    /// Advanced mode fills the width so the switch lines up with the controls in
    /// the rows above it. Simple mode keeps the label and switch as one centred
    /// pair.
    var fillsWidth = false

    var body: some View {
        Toggle("Allow offline accounts", isOn: $isOn)
            .toggleStyle(MossSwitchStyle(fillsWidth: fillsWidth))
            .font(.callout)
            .help("Shows HMCL's offline login option, which it hides by default outside mainland China")
    }
}

struct JavaOptionsField: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Java options")
                .font(TypeScale.eyebrow)
                .foregroundStyle(.secondary)
            TextField("-Xmx4G", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(TypeScale.data)
                .help("Passed to the JVM unchanged, before -jar")
        }
    }
}

struct ProblemNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Simple

struct SimpleModeView: View {
    @Bindable var model: LauncherViewModel

    var body: some View {
        VStack(spacing: 18) {
            VersionHeadline(latestVersion: model.latestVersion, note: model.latestNote)
                .padding(.top, 26)

            ReadinessStrip(hasLauncher: model.hasLauncher, hasRuntime: model.hasRuntime)

            OfflineAccountsToggle(isOn: $model.offlineAccountsEnabled)

            StartButton(model: model)

            if let notice = model.problem ?? model.downloadNotice {
                ProblemNote(text: notice)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
    }
}

// MARK: - Advanced

struct AdvancedModeView: View {
    @Bindable var model: LauncherViewModel

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                VersionHeadline(latestVersion: model.latestVersion, note: model.latestNote)
                Spacer()
                ReadinessStrip(hasLauncher: model.hasLauncher, hasRuntime: model.hasRuntime)
            }
            .padding(.top, 18)

            VStack(spacing: 8) {
                InstalledRow(
                    title: "HMCL",
                    empty: "Nothing downloaded",
                    options: model.installedLaunchers.map { ($0.id, $0.displayName) },
                    selection: Binding(
                        get: { model.selectedLauncher?.id },
                        set: { id in
                            model.selectedLauncher = model.installedLaunchers.first { $0.id == id }
                        }
                    ),
                    busy: model.activity.isBusy,
                    onRedownload: { Task { await model.reinstallSelectedLauncher() } },
                    onDelete: { model.deleteSelectedLauncher() }
                )

                InstalledRow(
                    title: "Java",
                    empty: "Nothing downloaded",
                    options: model.installedRuntimes.map { ($0.id, $0.displayName) },
                    selection: Binding(
                        get: { model.selectedRuntime?.id },
                        set: { id in
                            model.selectedRuntime = model.installedRuntimes.first { $0.id == id }
                        }
                    ),
                    busy: model.activity.isBusy,
                    onRedownload: { Task { await model.reinstallSelectedRuntime() } },
                    onDelete: { model.deleteSelectedRuntime() }
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                OfflineAccountsToggle(isOn: $model.offlineAccountsEnabled, fillsWidth: true)
                JavaOptionsField(text: $model.customJavaOptions)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StartButton(model: model)

            if let notice = model.problem ?? model.downloadNotice {
                ProblemNote(text: notice)
            }

            LogPane(events: model.events, onReveal: { model.revealWorkspace() })
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }
}

struct InstalledRow: View {
    let title: String
    let empty: String
    let options: [(id: String, label: String)]
    @Binding var selection: String?
    let busy: Bool
    let onRedownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 44, alignment: .leading)

            if options.isEmpty {
                Text(empty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker(title, selection: $selection) {
                    ForEach(options, id: \.id) { option in
                        Text(option.label).tag(Optional(option.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            Button(action: onRedownload) {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .disabled(busy)
            .help("Download the latest \(title) again")

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(busy || options.isEmpty)
            .help("Remove the selected \(title)")
        }
    }
}

struct LogPane: View {
    let events: [LogEvent]
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Launcher log")
                    .font(TypeScale.eyebrow)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show files", action: onReveal)
                    .buttonStyle(.link)
                    .font(.caption)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    // Plain VStack, not lazy: the list is capped at 500 rows, and
                    // a lazy container draws nothing when the view is rendered
                    // offscreen for screenshots.
                    VStack(alignment: .leading, spacing: 2) {
                        if events.isEmpty {
                            Text("Nothing yet. Press Start.")
                                .font(TypeScale.data)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: 8) {
                                Text(event.time)
                                    .foregroundStyle(.secondary)
                                Text(event.message)
                                    .textSelection(.enabled)
                            }
                            .font(TypeScale.data)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(event.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: events.count) {
                    if let last = events.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .frame(height: 150)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Palette.hairline)
            )
        }
    }
}
