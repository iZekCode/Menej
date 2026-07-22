//
//  Account.swift
//  Menej
//

import Foundation
import SwiftData

@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var issuer: Issuer
    var type: AssetType
    var currency: String
    /// The balance *anchor*, not necessarily the current balance: the figure
    /// known to be true as of `lastSyncedAt`. Transactions dated after that
    /// roll it forward — see LiquidBalanceService.
    var balance: Decimal
    /// The anchor's as-of date. `nil` means no anchor has ever been
    /// established, so the balance is unknown rather than zero.
    var lastSyncedAt: Date?
    /// True when the anchor was typed by the user rather than read off a
    /// statement's closing balance. Only myBCA prints one, so GoPay/Grab
    /// balances can only ever come from the user.
    var isBalanceManual: Bool = false
    /// User-chosen label; falls back to the issuer's name.
    var nickname: String?

    init(
        id: UUID = UUID(),
        issuer: Issuer,
        type: AssetType,
        currency: String = "IDR",
        balance: Decimal = 0,
        lastSyncedAt: Date? = nil,
        isBalanceManual: Bool = false,
        nickname: String? = nil
    ) {
        self.id = id
        self.issuer = issuer
        self.type = type
        self.currency = currency
        self.balance = balance
        self.lastSyncedAt = lastSyncedAt
        self.isBalanceManual = isBalanceManual
        self.nickname = nickname
    }

    var displayName: String {
        guard let nickname, !nickname.trimmingCharacters(in: .whitespaces).isEmpty else {
            return issuer.displayName
        }
        return nickname
    }

    /// Whether this account's balance is known at all. Without an anchor the
    /// account contributes nothing and the UI says so, rather than showing a
    /// roll-forward from an imaginary zero.
    var hasBalanceAnchor: Bool { lastSyncedAt != nil }
}
