import ProjectDescription

let workspace = Workspace(
  name: "p-term",
  projects: [
    ".",
  ],
  schemes: [
    .scheme(
      name: "p-term",
      buildAction: .buildAction(
        targets: [
          .project(path: "p-term.xcodeproj", target: "p-term"),
        ],
        runPostActionsOnFailure: true
      ),
      testAction: .targets(
        [
          .testableTarget(
            target: .project(path: "p-term.xcodeproj", target: "p-termTests")
          ),
        ],
        configuration: .debug,
        expandVariableFromTarget: .project(path: "p-term.xcodeproj", target: "p-term")
      ),
      runAction: .runAction(
        configuration: .debug,
        executable: .executable(.project(path: "p-term.xcodeproj", target: "p-term")),
        expandVariableFromTarget: .project(path: "p-term.xcodeproj", target: "p-term")
      ),
      archiveAction: .archiveAction(configuration: .release),
      profileAction: .profileAction(
        configuration: .release,
        executable: .project(path: "p-term.xcodeproj", target: "p-term")
      ),
      analyzeAction: .analyzeAction(configuration: .debug)
    ),
  ]
)
