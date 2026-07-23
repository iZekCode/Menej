# Menej

**Know what you're worth — without logging a single transaction, and without your financial data ever leaving your iPhone.**

Menej is an iOS personal finance app for Indonesia. You hand it the e-statements you already receive; it reads them, categorises them, reconciles them against each other, and turns them into one number: your net worth.

---

## The problem

Every expense tracker asks you to type. Every bank-sync app asks you to hand over your credentials to a third party.

Indonesians hold money across a bank plus two or three e-wallets. Reconciling them by hand takes an evening. Typing every transaction lasts about a week before you stop. And the apps that automate it do so by shipping your financial life to someone else's server.

Menej takes the third path: **your statements already contain everything.** They just aren't readable by anything except you.

## How it works

```
Share a PDF  →  Detect issuer  →  Extract  →  Categorise  →  Deduplicate  →  Review  →  Net worth
                                                                              ↑
                                                                    you confirm, always
```

Share a statement from Mail, Files or WhatsApp. Menej identifies which provider it came from, extracts the rows, assigns categories, spots the transfers you made between your own accounts, shows you what it found, and only writes to your ledger once you approve.

No account. No sign-up. No server. **Zero network calls carry your data** — the only things fetched are parser rules, asset prices and FX rates.

---

## Why it's hard

Parsing bank statements sounds like a solved problem. It isn't, and the failures are instructive.

**One provider's PDF loses every digit** on normal text extraction — font subsetting with no `ToUnicode` mapping for digit glyphs. **Another scrambles row and column order** whenever a page has many same-day transactions. Both had to be rendered to images and run through Vision OCR, with rows reconstructed from bounding-box geometry rather than text order.

OCR baselines wander across a wide row, and the wander differs between OS versions of the engine. So records anchor on their date and claim fields from a **Y band** around that anchor — nothing may assume a value sits in the same text cluster as its own date.

**The bug that shaped the architecture:** a credit once vanished from a real import while the app reported 100% confidence. The scorer is `extracted / totalRows` — silently dropping an unparseable row shrinks numerator and denominator together, so a lost transaction reads as a perfect parse. Now every extractor emits unusable rows with an empty amount, so normalisation rejects them and the loss becomes visible.

**Deduplication is the highest-risk feature in the product.** Topping up a wallet from your bank appears in both statements. Paying for a ride with a wallet appears twice. Count either one twice and net worth is wrong — and trust, once lost on a number, doesn't come back. Matches score on amount, a ±3-day window, and account identity; anything ambiguous goes to you rather than being decided silently.

Every parser is validated against each statement's own printed summary — balance roll-forwards, transaction counts, order totals. **Counts matter as much as sums:** one page in the test corpus holds six identical same-day credits in a row, and a parser can lose one while still looking correct on any check that only compares totals.

---

## What's built

| | |
|---|---|
| **Statement parsing** | Three issuers, deterministic, fully on-device. Versioned JSON rules, refreshable without an App Store release. |
| **Import** | Share sheet + in-app picker. Idempotent on file hash — re-importing replaces rather than duplicates, and carries your edits forward. Persistent history with re-import and delete. |
| **Categorisation** | Layered: your corrections → merchant dictionary → Indonesian merchant-word heuristics → direction sanity. One correction becomes a permanent rule, applied retroactively. |
| **Dedup & transfers** | Cross-account matching, with grey-zone pairs escalated to you. |
| **Net worth** | Liquid accounts, portfolio, physical inventory, liabilities. Frozen monthly snapshots so history doesn't shift under you. |
| **Portfolio** | Crypto, stocks, gold, funds. Live pricing from public sources, unrealised P/L, allocation, IDR/USD toggle. |
| **Inventory** | Photo-first grid. Per-category value curves — watches and gold *appreciate*, so curves run both ways. Warranty reminders. |
| **Insights** | Spending analytics, runway, anomaly detection — each withheld until the data genuinely supports it. |
| **Ask** | Natural-language questions over your own ledger, answered by an on-device model that routes queries; every figure is computed by the app, never by the model. |
| **Backup** | Export and restore the whole ledger as a readable file, plus automatic backup to a folder you nominate. |

### Not done yet

Honest status: the **Home Screen widget** has views but no extension target. **Subscription detection** has a model and a screen but nothing that detects recurring charges yet. **E2EE sync** is deferred — switching phones today means restoring from an iCloud device backup.

---

## Principles

**Zero manual entry by default.** Every time the app asks you to type something, that's a design failure. Manual input is an escape hatch, never the main path.

**On-device, always.** Not a feature — the architecture. It's also the market position.

**Be honest about uncertainty.** When a parse fails or numbers don't reconcile, the gap is shown, never quietly absorbed. Insights stay hidden until there's enough data to justify them. A wrong insight in week one does more damage than no insight at all.

**Net worth is the hero.** Everything else exists to support that one number.

---

## Design

Minimalist, native iOS, lilac accent, dark mode from day one.

Standard SwiftUI components throughout — no custom tab bars, no reinvented controls. A deliberate constraint: native components inherit accessibility, localisation and every OS update for free, and in a finance app "trustworthy" beats "novel".

| Token | Light | Dark |
|---|---|---|
| `accent` | `#7C6BC4` | `#A99BE0` |
| `accentSoft` | `#EDE9F9` | `#2A2340` |
| `accentPressed` | `#6455AB` | `#BFB3EA` |

True lilac fails WCAG AA on white at about 1.8:1, so the palette splits: **deeper lilac carries meaning, light lilac is fills only.** Gains and losses stay green and red — financial direction is the one place convention beats brand, always paired with a sign so it survives colour blindness. Numerals are monospaced everywhere a value can change, or columns jitter and misalign.

---

## Privacy

| Aspect | Decision |
|---|---|
| Storage | Local only (SwiftData), encrypted at rest |
| Cloud sync | None. E2EE sync deferred. |
| Authentication | Face ID / Touch ID, optional, on by default |
| Network | Parser rules, asset prices, FX rates. None carry user data. |
| AI | Apple Foundation Models, on-device. No cloud LLM. |

---

## Tech

iOS 26.5+ · SwiftUI · SwiftData · Swift 5 language mode. No third-party dependencies — PDFKit, Vision, Charts, LocalAuthentication, FoundationModels, UserNotifications.

MVVM with a service layer. Services own all logic and are protocol-backed so tests inject fakes; view models only shape data for display. The statistical and parsing cores deliberately import neither SwiftUI nor SwiftData, so they compile and unit-test without a simulator.

```
Menej/
├── App/          AppState, DesignSystem
├── Model/        SwiftData models + enums
├── ViewModel/    NetWorth · Import · Ledger · Portfolio · Insights · Chat
├── View/         one folder per feature
├── Component/    reusable views + charts
└── Service/      Parsing/ (detector, OCR, rule engine, normaliser, scorer)
                  + categorisation, dedup, net worth, insights, pricing, backup
```

### Build

Open `Menej.xcodeproj` and run the `Menej` scheme. Three targets, all using Xcode 16 synchronized folder groups, so adding a file needs no project-file edit.

### Tests

⌘U, or:

```bash
xcodebuild test -scheme Menej -destination 'platform=iOS Simulator,name=iPhone 16'
```

Parser quality is entirely a function of corpus diversity. The reconciliation suites run real statements against each issuer's printed ground truth, resolving the corpus from `SampleStatements/` at the repo root.

**That folder is intentionally absent from this repository.** It holds real personal financial documents, so it's gitignored and kept outside the app target — nothing sensitive can be committed or shipped inside the binary. Supply your own statements in `SampleStatements/<Issuer>/` to run those suites; every other test runs without them.

---

## Roadmap

- Home Screen widget (extension target)
- Recurring-charge detection for subscriptions
- Screenshot + OCR pipeline, unlocking several more e-wallets at once
- E2EE sync
- Cashflow forecasting, once there's enough history to do it honestly
