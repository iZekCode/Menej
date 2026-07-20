//
//  DedupService.swift
//  Menej
//
//  Cross-source dedup & transfer detection — see PRD §6 F4.
//  "The most underrated and highest-risk feature in v1." Get it wrong and net
//  worth double-counts, and trust is gone permanently.
//
//  Approach: match on amount + time window (±3 days) + account identifiers,
//  with a similarity score. Only pairs across *different* accounts are
//  considered — within a single account's own transaction list, two
//  similarly-sized transactions close in time are far more likely a
//  coincidence than a real duplicate.
//
//  This deliberately does not restrict by direction: the real corpus shows
//  two distinct shapes that both need catching —
//   - opposite-direction (a debit in one account, a credit in another): a
//     transfer between the user's own accounts (GoPay top-up from BCA).
//   - same-direction (a debit in both): the same real-world expense
//     recorded twice (paying for a Grab ride via GoPay produces a debit in
//     both the Grab and GoPay statements).
//  Classifying which of those two shapes a candidate is only requires
//  comparing the two transactions' `direction`, which callers already have.
//
//  Validated against the real corpus: a BCA debit of 2,001,000 (which
//  includes a transfer fee) against a GoPay credit of 2,000,000 top-up on
//  the same day scores 0.99 (confident); an unrelated same-account pair or
//  a mismatched amount/date scores 0 (excluded entirely). Pairs landing in
//  the grey zone (below `confidentMatchThreshold`) are still returned —
//  surfaced to the user rather than decided by the app — but not treated
//  as pre-confirmed.
//
//  Resolved pairs never resurface: confirmed pairs are excluded because
//  both transactions now have a non-nil `dedupGroupId`; rejected pairs are
//  excluded via a persisted rejection list (UserDefaults, same pattern as
//  CategorizationService's learned corrections) — without this, every
//  re-scan (e.g. reopening the review screen) would re-propose the exact
//  same pairs, since the matching logic itself has no memory of past
//  decisions.
//

import Foundation

struct DedupCandidate {
    let transactionId: UUID
    let matchedTransactionId: UUID
    let similarityScore: Double
    let isConfidentMatch: Bool
}

protocol DedupServiceProtocol {
    func findCandidates(in transactions: [Transaction]) -> [DedupCandidate]
    func markRejected(_ candidate: DedupCandidate)
}

final class DedupService: DedupServiceProtocol {
    /// Grey-zone threshold: candidates below this score are surfaced to the
    /// user instead of being merged automatically.
    let confidentMatchThreshold: Double = 0.9

    /// ±3 days per PRD §6 F4.
    let matchWindow: TimeInterval = 3 * 24 * 60 * 60

    /// A relative amount difference at or beyond this ratio scores 0 —
    /// large enough to absorb a small transfer fee (e.g. a top-up of
    /// 2,000,000 landing as a 2,001,000 debit at the source), too large to
    /// treat two genuinely different amounts as the same transaction.
    private let amountToleranceRatio = 0.05

    private static let rejectedPairsKey = "Menej.rejectedDedupPairs"
    private let userDefaults: UserDefaults
    private var rejectedPairs: Set<String>

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.rejectedPairs = Set(userDefaults.stringArray(forKey: Self.rejectedPairsKey) ?? [])
    }

    func findCandidates(in transactions: [Transaction]) -> [DedupCandidate] {
        var candidates: [DedupCandidate] = []

        for i in 0..<transactions.count {
            for j in (i + 1)..<transactions.count {
                let a = transactions[i]
                let b = transactions[j]
                guard a.accountId != b.accountId else { continue }
                // Already linked as a confirmed match — don't re-propose it.
                guard a.dedupGroupId == nil, b.dedupGroupId == nil else { continue }
                guard !rejectedPairs.contains(Self.pairKey(a.id, b.id)) else { continue }

                let dateDelta = abs(a.date.timeIntervalSince(b.date))
                guard dateDelta <= matchWindow else { continue }

                let maxAmount = max(a.amount, b.amount)
                guard maxAmount > 0 else { continue }
                let amountDiffRatio = NSDecimalNumber(decimal: abs(a.amount - b.amount) / maxAmount).doubleValue
                guard amountDiffRatio <= amountToleranceRatio else { continue }

                let amountScore = 1 - (amountDiffRatio / amountToleranceRatio)
                let dateScore = 1 - (dateDelta / matchWindow)
                let score = amountScore * dateScore

                candidates.append(DedupCandidate(
                    transactionId: a.id,
                    matchedTransactionId: b.id,
                    similarityScore: score,
                    isConfidentMatch: score >= confidentMatchThreshold
                ))
            }
        }

        return candidates.sorted { $0.similarityScore > $1.similarityScore }
    }

    func markRejected(_ candidate: DedupCandidate) {
        rejectedPairs.insert(Self.pairKey(candidate.transactionId, candidate.matchedTransactionId))
        userDefaults.set(Array(rejectedPairs), forKey: Self.rejectedPairsKey)
    }

    private static func pairKey(_ a: UUID, _ b: UUID) -> String {
        [a.uuidString, b.uuidString].sorted().joined(separator: "|")
    }
}
