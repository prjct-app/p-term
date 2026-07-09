import ComposableArchitecture
import PTermSettingsShared
import SwiftUI

public struct WorktreeSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>

  public init(store: StoreOf<SettingsFeature>) {
    self.store = store
  }

  public var body: some View {
    let defaultPath = PTermPaths.reposDirectory.path(percentEncoded: false)
    let resolvedBase =
      PTermPaths.normalizedWorktreeBaseDirectoryPath(
        store.defaultWorktreeBaseDirectoryPath
      ) ?? defaultPath
    let examplePath = "\(resolvedBase)*/**/*"
    Form {
      Section {
        Toggle(isOn: $store.promptForWorktreeCreation) {
          Text("Prompt for branch name on creation")
          Text("Choose the branch name and base ref before creating the workspace.")
        }
        Toggle(isOn: $store.fetchOriginBeforeWorktreeCreation) {
          Text("Fetch remote branch before creating workspace")
          Text("Runs git fetch to ensure the base branch is up to date.")
        }
        TextField(
          text: $store.defaultWorktreeBaseDirectoryPath,
          prompt: Text(defaultPath)
        ) {
          Text("Default directory").monospaced(false)
          Text("Parent path for new workspaces.").monospaced(false)
        }.monospaced()
      } footer: {
        Text("e.g., `\(examplePath)`")
      }
      Section {
        Toggle(isOn: $store.copyIgnoredOnWorktreeCreate) {
          Text("Copy ignored files to new workspaces")
          Text("Copies gitignored files from the main workspace.")
        }
        Toggle(isOn: $store.copyUntrackedOnWorktreeCreate) {
          Text("Copy untracked files to new workspaces")
          Text("Copies untracked files from the main workspace.")
        }
      }
      Section("Clean-up") {
        Picker(
          "Auto-delete archived workspaces",
          selection: Binding(
            get: { store.autoDeleteArchivedWorktreesAfterDays },
            set: { store.send(.requestAutoDeleteDaysChange($0)) }
          )
        ) {
          Text("Never").tag(AutoDeletePeriod?.none)
          ForEach(AutoDeletePeriod.allCases, id: \.rawValue) { period in
            Text(period.label).tag(AutoDeletePeriod?.some(period))
          }
        }
      }
      Section {
        Toggle(isOn: $store.deleteBranchOnDeleteWorktree) {
          Text("Delete local branch with workspace")
          Text("Removes the local branch along with the workspace. Remote branches must be deleted on GitHub.")
          Text("Uncommitted changes will be lost.").foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
    .padding(.top, -20)
    .padding(.leading, -8)
    .padding(.trailing, -6)
    .navigationTitle("Workspaces")
  }
}
