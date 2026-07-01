import ProjectDescription

let tuist = Tuist(
  // CI's cache-warming step (`tuist auth login` / `make warm-cache`) needs this to resolve to a
  // real, registered Tuist Cloud project or it fails with "No projects linked to the repository."
  // The rename briefly pointed this at "prjct-app/p-term" (matching the renamed GitHub repo) as a
  // placeholder, which broke CI since no such Tuist Cloud project exists yet. Reverted to the
  // known-working handle this fork has always used for its build cache.
  // TODO(p-term): once a Tuist Cloud project is registered for prjct-app/p-term, switch to it.
  fullHandle: "supabitapp/supacode",
  project: .tuist(
    compatibleXcodeVersions: .upToNextMajor("26.0"),
    swiftVersion: "6.0",
    generationOptions: .options(
      optionalAuthentication: true
    ),
    cacheOptions: .options(
      profiles: .profiles(
        [
          "development": .profile(
            .allPossible,
            except: [
              .named("GhosttyKit"),
            ]
          ),
        ],
        default: .custom("development")
      )
    )
  )
)
