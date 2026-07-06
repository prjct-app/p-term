import PTermSettingsShared
import SwiftUI

struct PullRequestStatusModel: Equatable {
  let pullRequest: GithubPullRequest
  let number: Int
  let state: String?
  let title: String
  let statusChecks: [GithubPullRequestStatusCheck]
  let detailText: String?
  let isQueued: Bool

  init?(pullRequest: GithubPullRequest?) {
    guard
      let pullRequest,
      Self.shouldDisplay(state: pullRequest.state, number: pullRequest.number)
    else {
      return nil
    }
    self.pullRequest = pullRequest
    self.number = pullRequest.number
    let state = pullRequest.state.uppercased()
    self.state = state
    self.title = pullRequest.title
    self.isQueued = PullRequestMergeQueueStatus(pullRequest: pullRequest) != nil
    if state == "MERGED" {
      self.detailText = nil
      self.statusChecks = []
      return
    }
    let isDraft = pullRequest.isDraft
    let prefix = isDraft ? "(Drafted) " : ""
    let mergeReadiness = PullRequestMergeReadiness(pullRequest: pullRequest)
    let checks = pullRequest.statusCheckRollup?.checks ?? []
    self.statusChecks = checks
    let checksDetail: String?
    if checks.isEmpty {
      checksDetail = nil
    } else {
      let breakdown = PullRequestCheckBreakdown(checks: checks)
      let checksLabel = breakdown.total == 1 ? "check" : "checks"
      checksDetail = breakdown.summaryText + " \(checksLabel)"
    }
    if mergeReadiness.isBlocking {
      if let checksDetail {
        self.detailText = prefix + mergeReadiness.label + " - " + checksDetail
      } else {
        self.detailText = prefix + mergeReadiness.label
      }
      return
    }
    if let checksDetail {
      self.detailText = prefix + checksDetail
    } else {
      self.detailText = isDraft ? "(Drafted)" : nil
    }
  }

  var badgeText: String {
    PullRequestBadgeStyle.style(state: state, number: number)?.text ?? "#\(number)"
  }

  var badgeColor: Color {
    PullRequestBadgeStyle.style(state: state, number: number, isQueued: isQueued)?.color ?? .secondary
  }

  static func shouldDisplay(state: String?, number: Int?) -> Bool {
    guard number != nil else {
      return false
    }
    return state?.uppercased() != "CLOSED"
  }
}
