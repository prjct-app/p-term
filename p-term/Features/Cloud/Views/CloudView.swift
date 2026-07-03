import ComposableArchitecture
import PTermSettingsShared
import SwiftUI

/// The native Cloud surface. p/term is a FREE client of the paid Cloud service — signing in and
/// viewing state is free; the "Sync this project" call-to-action is where the paid service begins.
/// Dumb MVVM view: renders `store.status.presentation`, sends actions, never touches the network.
struct CloudView: View {
  let store: StoreOf<CloudFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      Divider()
      content
      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(minWidth: 360, minHeight: 280)
    .navigationTitle("Cloud")
    .task { store.send(.onAppear) }
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(systemName: symbolName)
        .foregroundStyle(tint)
        .font(.title2)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("prjct Cloud")
          .font(AppTypography.headline)
        Text(headline)
          .font(AppTypography.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch store.status.presentation {
    case .signedOut:
      VStack(alignment: .leading, spacing: 10) {
        Text("Sign in to sync this project's memory across your machines and share it with your team.")
          .font(AppTypography.body)
          .foregroundStyle(.secondary)
        Button {
          store.send(.signInTapped)
        } label: {
          Label(store.isSigningIn ? "Waiting for browser…" : "Sign in", systemImage: "person.crop.circle")
        }
        .disabled(store.isSigningIn)
        .help("Sign in to prjct Cloud (free) in your browser")
      }

    case .signedInUnlinked:
      VStack(alignment: .leading, spacing: 10) {
        Text("This project isn't syncing yet. Turn on cloud sync to back up its memory and collaborate.")
          .font(AppTypography.body)
          .foregroundStyle(.secondary)
        // The paid service starts here — surfaced from the free client.
        Text("Run `prjct cloud link` in this project to start syncing.")
          .font(AppTypography.callout.monospaced())
          .foregroundStyle(.tertiary)
        signOutButton
      }

    case .paused:
      VStack(alignment: .leading, spacing: 10) {
        Text("Sync is paused for this project.")
          .font(AppTypography.body)
          .foregroundStyle(.secondary)
        signOutButton
      }

    case .syncing(let pending):
      VStack(alignment: .leading, spacing: 8) {
        statusRow("Pending events", pending == 0 ? "up to date" : "\(pending)")
        if let realtime = store.status.realtime { statusRow("Realtime", realtime) }
        if let lastSync = store.status.lastSync { statusRow("Last sync", lastSync) }
        signOutButton
      }
    }
  }

  private var signOutButton: some View {
    Button(role: .destructive) {
      store.send(.signOutTapped)
    } label: {
      Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
    }
    .help("Sign out of prjct Cloud on this machine")
  }

  private func statusRow(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label).foregroundStyle(.secondary)
      Spacer()
      Text(value).monospacedDigit()
    }
    .font(AppTypography.callout)
  }

  private var headline: String {
    switch store.status.presentation {
    case .signedOut: "Not signed in"
    case .signedInUnlinked: "Signed in · not syncing this project"
    case .paused: "Signed in · paused"
    case .syncing: "Signed in · syncing"
    }
  }

  private var symbolName: String {
    switch store.status.presentation {
    case .signedOut: "cloud"
    case .signedInUnlinked: "cloud.slash"
    case .paused: "pause.circle"
    case .syncing: "cloud.fill"
    }
  }

  private var tint: Color {
    switch store.status.presentation {
    case .signedOut: .secondary
    case .signedInUnlinked: .orange
    case .paused: .yellow
    case .syncing: .green
    }
  }
}

/// Menu command that opens the Cloud window. A dedicated view so it can read
/// `@Environment(\.openWindow)`, unavailable directly inside a `CommandGroup`.
struct OpenCloudButton: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Cloud") { openWindow(id: WindowID.cloud) }
      .help("Sign in and manage prjct Cloud")
  }
}
