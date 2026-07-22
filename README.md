# Menej

An iOS app for managing your **entire net worth** in one place — not another expense tracker.

The differentiator: **you never manually log transactions.** You upload e-statements from the apps you already use, and Menej extracts income and expenses automatically, entirely on-device.

> Menej shows you what you're actually worth — without logging a single transaction, and without your financial data ever leaving your iPhone.

**Platform:** iOS 26.5+ · SwiftUI · SwiftData · Swift 5 language mode
**Bundle ID:** `Filbert.Menej` · **App Group:** `group.Filbert.Menej`

> **Note on section numbers.** Source comments throughout the codebase cite `PRD §6 F1`, `PRD §7`, `Appendix C`, and so on. The PRD has been folded into this file and the numbering preserved — `§6 F1` below is what those comments point at.

---

## Build & run

Open `Menej.xcodeproj` and run the `Menej` scheme. There are no package dependencies; everything is first-party frameworks (PDFKit, Vision, SwiftData, Charts, LocalAuthentication).

Three targets, all using Xcode 16 **synchronized folder groups** — files are picked up from the folder automatically, so adding a `.swift` file needs no project-file edit:

| Target | Folder |
|---|---|
| `Menej` | `Menej/` |
| `MenejShareExtension` | `MenejShareExtension/` |
| `MenejTests` | `MenejTests/` |

### Sample data

`SeedDataService` imports 15 real bundled statements through the normal parse → categorize → persist pipeline, so the app has real data instead of being empty.

- On launch, `seedIfNeeded` runs only when no `Statement` exists.
- **Settings → Reset & Reseed** wipes Statements, Transactions and Snapshots and re-imports. It deliberately does *not* delete `Account` rows — for GoPay and Grab, the balance you typed is the only balance that exists, and deleting the row took it with you. Only statement-derived anchors are cleared.

`SeedDataService` is `#if DEBUG`-only on purpose: the bundled PDFs are real personal financial documents with a real account number and real transactions. **Never remove that guard without replacing the corpus with redacted files first.**

### Tests

⌘U, or:

```bash
xcodebuild test -scheme Menej -destination 'platform=iOS Simulator,name=iPhone 16'
```

The corpus reconciliation suites locate statements and parser rules via `#filePath` (see `MenejTests/ParsingTests/CorpusFixtures.swift`), which resolves to a compile-time absolute path — fine locally, but they won't find the corpus on a different machine or on CI.

---

## Architecture

MVVM with a service layer, grouped by feature within each layer.

```
Menej/
├── App/            MenejApp, AppState, DesignSystem/ (Colors, Typography, Spacing, palettes)
├── Model/          SwiftData @Model types + Enums/ (Issuer, Category, Direction, AssetType)
├── ViewModel/      NetWorth/ Import/ Ledger/ Portfolio/ Subscriptions/ Insights/
├── View/           NetWorth/ Import/ Ledger/ Liquid/ Portfolio/ Assets/ Subscriptions/ Insights/ Settings/
├── Component/      Feature-agnostic reusable views + Charts/
├── Service/
│   ├── Parsing/    ParsingService, IssuerDetector, PDFTextExtractor, RuleEngine,
│   │               OCRRowExtractor, TransactionNormalizer, ConfidenceScorer, Rules/*.json
│   └── …           Categorization, Dedup, Transfer, NetWorth, Snapshot, LiquidBalance,
│                   Insight, SpendingAnalytics, Pricing, Depreciation, Logo, Persistence,
│                   RemoteConfig, Analytics, Biometric, WarrantyReminder, AIEnhancement, SeedData
└── Widget/         NetWorthTimelineProvider, NetWorthWidgetView
```

**Rules that keep it navigable:**

- **Services own all logic; ViewModels only shape it for display.** Arithmetic about money in a ViewModel belongs in a Service. This is what makes parsing testable without instantiating UI.
- **Services are protocol-backed** (`ParsingServiceProtocol`, `DedupServiceProtocol`, …) so tests inject fakes. Parsing and dedup are where bugs cost most.
- **`Component/` holds only reusable, feature-agnostic views.** Anything used by one screen lives in that feature's `View/` folder, or `Component/` slowly absorbs the app.
- **`ParsingService` imports no SwiftUI and no SwiftData**, so the corpus can be run against it from a command-line harness and rules iterated in seconds rather than through the simulator.
- **MVVM with SwiftData:** `@Query` is designed to be used inside views. Simple list screens query directly; ViewModels are reserved for screens with real logic (import review, insights, net worth, portfolio). Forcing every screen through a ViewModel is ceremony without benefit.

---

## 4. Product principles

1. **Zero manual entry by default.** Every time the app asks the user to type something, that's a design failure. Manual input is an escape hatch, never the primary flow.
2. **On-device, always.** No financial data leaves the device. Architecture decision and market position at once.
3. **Be honest about uncertainty.** When parsing fails or numbers don't reconcile, surface the gap. Never silently guess. Trust evaporates the moment a number is wrong and the user notices.
4. **Net worth is the hero.** Every other feature supports that one number.

---

## 5. Scope

| # | Feature | Why it's in |
|---|---|---|
| F1 | Statement parsing (3 issuers, deterministic, on-device) | The core feature and the differentiator |
| F2 | Share sheet + in-app import | The data entry point |
| F3 | Auto-categorization with learned corrections | Without it, parsed data isn't usable |
| F4 | Cross-source dedup & transfer detection | Without it the numbers are wrong — fatal |
| F5 | Net worth: assets, monthly snapshots | The product itself |
| F6 | Portfolio & physical assets | Net worth components |
| F7 | Subscriptions (from recurring detection) | Nearly free once F1 exists |
| F8 | Insights: runway + anomaly detection | The "aha" moment, workable with thin data |
| F9 | Home Screen widget | Retention without requiring app opens |

### Deferred, with reasoning

| Feature | To | Why |
|---|---|---|
| Cashflow forecast | v1.1 | Needs 3+ months of history. Bad forecasts destroy trust. |
| Asset allocation drift | v1.1 | Requires target allocations first — heavy setup burden. |
| Goals / sinking funds | v1.1 | High value, but doesn't de-risk the main question (can parsing be trusted). |
| Screenshot + Vision OCR pipeline | v1.1 | A second parsing path. Unlocks ShopeePay, OVO, DANA, LinkAja in one go. |
| ShopeePay & OVO | v1.1 | Blocked on the OCR pipeline above. |
| Liabilities (paylater, cards, loans) | v1.1 | See the note in F5. |
| E2EE cloud sync | v1.1 | Removes device-switch data loss without compromising on-device parsing. |
| Shortcuts / App Intents | v1.1 | Moderate effort, smaller retention impact than the widget. |
| Live Activity | **Cut** | Designed for ongoing, time-bounded events. Net worth is neither. Likely rejected at review, and nobody wants it parked in the Dynamic Island all day. |
| Server-side parsing | v2+ | Conflicts with the privacy position. |
| Bank sync via API | Not planned | Expensive, needs a legal entity, works against the positioning. |

---

## 6. Feature specifications

### F1 — Statement parsing (deterministic, on-device)

**Issuers:** myBCA, GoPay, Grab.

```
File arrives
  → Issuer detection (fingerprint: header text)
  → Text extraction (PDFKit text layer, or Vision OCR — see below)
  → Apply issuer rules (versioned JSON)
  → Normalize into ParsedTransaction
  → Confidence scoring + reconciliation
  → User review screen
```

**Text layer vs OCR.** Only GoPay parses from the PDF text layer. The other two can't:

- **Grab's** export loses every digit on text-layer extraction — font subsetting with no `ToUnicode` mapping for digit glyphs.
- **myBCA's** digits extract fine, but `PDFPage.string` scrambles row/column order on pages with many same-day transactions.

Both render to an image and run Vision OCR, reconstructing rows from bounding-box positions. Records anchor on their date and claim their fields from a **Y band** around that anchor rather than from a text cluster — OCR baselines wander across a wide row, and the wander differs between OS versions of the engine, so nothing may assume a field clustered with its own date.

**Parser rules as remote config.** Versioned JSON, bundled *and* refreshable from a CDN, cached locally, checked at most once a day. Issuers change layouts without warning; if rules live in the binary a fix waits days for review. The app stays fully functional offline on cached rules. This carries no user data.

**Confidence & review.** Every statement gets a confidence score. Low scores trigger a review screen flagging problem rows. **Users always confirm before data enters the ledger.**

> **A record that fails extraction must still be emitted.** `ConfidenceScorer.score` is `transactions.count / rawRowCount` — silently dropping a bad row shrinks numerator and denominator together and reports a lost transaction as a perfect 1.0 parse. All three extractors emit unusable rows with an empty amount so normalization rejects them and the loss shows up. This is not theoretical: a 271,000 credit went missing from a real April myBCA import while the app reported 100% confidence.

**Reconciliation gap.** If the parsed closing balance doesn't match the printed one, show the difference as *Unaccounted*. Never hide it. Note this only works for myBCA — GoPay and Grab print no balance, so `unaccountedAmount` is structurally 0 there and confidence is the only signal.

**Acceptance criteria:** ≥95% of rows extracted correctly per issuer · a 12-month statement parses in <5s on an iPhone 12 · zero network calls carrying statement contents.

### F2 — Import & share sheet

Share Extension (share a PDF from Mail, Files or WhatsApp straight in), in-app document picker with multi-file support, and a `SharedImportInbox` in the app group that hands files from the extension to the app.

**Idempotent on file hash:** re-importing the same file *replaces* that statement's transactions with freshly parsed ones rather than duplicating or no-oping — after a parser upgrade, re-importing is the only way better rows reach the ledger. User edits (corrected category/merchant) and dedup links carry over onto the matching re-parsed transaction.

### F3 — Auto-categorization

Layered matching, calibrated against the real corpus: user corrections → bundled merchant dictionary (`MerchantDictionary.json`) → generic Indonesian merchant-word heuristics (`kantin`, `ayam`, `apotek`, …) → issuer/boilerplate fallbacks → direction sanity.

**Direction sanity matters.** Money in can only be income, transfer or investment, so a spending keyword inside a credit (an incoming reimbursement whose note says "airbnb") is coerced to income. A dictionary rule may declare a `direction` when its meaning flips: `switching` outbound is the user moving money out, inbound it's someone else's money arriving. Wallet keywords (`gopay topup`, `ovo`, `shopeepay`) stay direction-agnostic — a credit in a wallet really is an own-account transfer, and coercing it to income would double-count net worth.

**Learns from corrections:** one correction creates a permanent merchant rule applied retroactively — but only for dictionary/learned keywords, never a heuristically guessed name, since a wrong guess there could mass-recategorize unrelated transactions.

### F4 — Deduplication & transfer detection

**The most underrated and highest-risk feature.** Get it wrong and net worth double-counts, and trust is gone permanently.

| Scenario | Correct behavior |
|---|---|
| GoPay top-up from BCA — in both statements | One transfer, not two expenses |
| Paying for Grab with GoPay | One expense, recorded once |
| Transfer between the user's own accounts | Not an expense; net worth unchanged |

Matches on amount + a ±3-day window + account identifiers, scored. Only pairs across *different* accounts are considered. Grey-zone pairs go to the user rather than being decided by the app; resolved pairs never resurface.

### F5 — Net worth

Assets: bank accounts, e-wallet balances, investments, gold, physical assets, cash. **Liabilities are deferred**, so the headline is honestly labelled total assets. `Liability` and `totalLiabilities` are reserved in the schema from day one — retrofitting a second side onto every historical snapshot is far more expensive than reserving space now.

**Balance anchors.** `current balance = anchor + Σ signed amounts of transactions dated after the anchor date`, where the anchor is (`Account.balance` @ `lastSyncedAt`). myBCA's anchor is the statement's printed closing balance; GoPay and Grab print none, so the user sets theirs once and imports roll it forward. An account with no anchor contributes its stored balance as-is and gets no roll-forward — "unknown" is honest, a number extrapolated from an imaginary zero is not.

**Monthly snapshots** are frozen once created for a month so the historical chart doesn't retroactively shift when today's asset prices move. The trade-off: it can't tell "prices moved" apart from "the underlying data was wrong", so a month imported from a bad parse keeps its value even after re-import.

### F6 — Portfolio & physical assets

Crypto, stocks (IDX + US), mutual funds, time deposits, gold, brokerage cash. Manual entry of quantity + cost basis, add/edit/delete, prices refreshed from public sources (Indodax, Yahoo, Frankfurter for FX), unrealized P/L and allocation weights, IDR/USD display toggle.

A successful refresh persists each holding's IDR value onto the model (`lastValueIDR`/`lastQuotedAt`) so net worth and snapshots can value the portfolio synchronously and offline. Editing a holding must keep that cache honest: a quantity change rescales it, a symbol/instrument/currency change clears it, a cost-basis change leaves it alone.

Physical assets carry per-category depreciation curves with manual override. Some categories **appreciate** (watches, gold) — the curve runs both directions. Warranty expiry dates with reminders.

### F7 — Subscriptions

Detected from recurring transaction patterns rather than manual entry — finding a forgotten subscription is the single most memorable moment in the product. Shows monthly and annual commitment, detects price increases, flags likely-dead subscriptions.

### F8 — Insights

**Runway** — "at your current burn rate, your liquid assets last 14 months." Works with a single month of data.
**Anomaly detection** — "transport is 2.4× your average this month." Needs 2+ months; before that the module is hidden entirely, not shown empty.

Computed over a pure `[SpendEntry]` already filtered for dedup and transfers, with partial months excluded from averages and a noise floor on anomalies.

**Insights must be withheld until the data supports them.** A wrong insight in week one does more damage than no insight at all.

### F9 — Widget

Small (net worth + delta) and medium (net worth + 6-month trend). Refreshes on data change, not on a timer. Privacy mode hides amounts while locked.

---

## 7. Design direction

Minimalist, native iOS, lilac accent.

**Native-first.** Standard SwiftUI components and system behaviors — `NavigationStack`, `List`, sheets, `Charts`, Dynamic Type, VoiceOver, Reduce Motion. No custom tab bars, no reinvented controls. A deliberate constraint: native components inherit accessibility, localization and every OS update for free, a solo developer can't maintain a design system alongside a parsing engine, and it reads as trustworthy — which matters more here than visual novelty.

| Token | Light | Dark | Use |
|---|---|---|---|
| `accent` | `#7C6BC4` | `#A99BE0` | Buttons, links, selected states |
| `accentSoft` | `#EDE9F9` | `#2A2340` | Fills, chips, chart bands, cards |
| `accentPressed` | `#6455AB` | `#BFB3EA` | Pressed and focus states |

True lilac (~`#C8B6E2`) is too light to carry text on white — about 1.8:1, failing WCAG AA. The split that works: **deeper lilac for anything conveying meaning**, **light lilac only for fills** where contrast doesn't apply.

**Gains and losses stay green and red.** Never tint them lilac for brand consistency — financial direction is the one place convention beats aesthetics. Always pair with a sign or arrow so meaning survives for colorblind users.

**Numerals use `.monospacedDigit()`** everywhere a value can change or sits in a column. Without it, net worth figures jitter on update and columns fail to align — the most common polish failure in finance apps.

16pt margins, 8pt spacing grid, generous whitespace, SF Symbols only. Motion limited to system transitions plus a subtle count-up on the net worth figure. Dark mode required, not deferred.

**Avoid:** gradient-heavy fintech cards, glassmorphism, custom fonts, illustrated mascots, confetti on milestones. Credibility rests on the numbers being right; the design should recede and let them carry it.

---

## 8. Privacy & security

| Aspect | Decision |
|---|---|
| Storage | Local only (SwiftData), encrypted at rest |
| Cloud sync | None; E2EE sync deferred to v1.1. iCloud device backup until then. |
| Authentication | Face ID / Touch ID to open the app, optional, on by default |
| Analytics | Aggregate, anonymous events only. No amounts, no merchant names. |
| Network | Only parser rules, asset prices, FX rates. None carry user data. |

Until E2EE sync lands, switching phones means losing data unless restored from an iCloud backup. This must be communicated during onboarding.

---

## 9. Success metrics

Primary — these decide whether the product continues:

- **Parse success rate ≥90%** across statements uploaded by real users
- **Activation ≥60%** of installs complete an import within 24 hours

Supporting: D30 retention ≥25% · ≥2 connected issuers per active user · category correction rate <15% · median app open → first net worth view <5 minutes.

> If parse success sits below 80%, adding features is pointless. The entire premise rests on parsing being reliable.

---

## 10. Test corpus

Parser quality is entirely determined by the diversity of statements it's tested against. The current corpus is 15 real statements (5 months × 3 issuers) in `Menej/Financial Statement/`, reconciled against each statement's own printed summary:

| Issuer | Ground truth | Status |
|---|---|---|
| myBCA | `SALDO AWAL`→`SALDO AKHIR` roll-forward + `MUTASI CR`/`MUTASI DB` counts | 5/5 exact, `unaccounted = 0` |
| GoPay | Row count vs date-line count (printed totals are **net of coins**, so they aren't a valid target directly) | 5/5, every row captured |
| Grab | `Jumlah Pemesanan` / `Jumlah` header | 5/5 exact |

**Counts matter as much as totals.** April's myBCA page 3 holds six identical 271,000 credits in a row — a parser can lose one and still look close on any check that only compares sums.

Target for release is ≥20 statements per issuer, covering different date ranges, empty months, and unusually long statements.

---

## 11. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Issuer changes statement format | High | Rules via remote config; opt-in failure diagnostics |
| Insufficient test statements | High | Grow the corpus before adding features |
| Dedup errors → double-counting | High | Conservative thresholds; ambiguous cases go to the user |
| PDFs without a text layer (scans) | Medium | Reject with a clear message; Vision OCR pipeline in v1.1 |
| Users upload screenshots instead of PDFs | Medium | Detect images and explain PDF export is required |
| Vision OCR differs between OS versions | Medium | Never assume a field clustered with its anchor; reconcile against printed totals in tests |

---

## 12. Open questions

1. Which account is the source of truth when two statements disagree?
2. Can users edit parsed transactions? (Recommendation: yes, marked *edited*, retaining the original value.)
3. How do we handle cash that never appears on any statement? (Recommendation: one manual adjustment per month, not per-transaction logging.)
4. Onboarding: request the first upload before or after the user sees the app's interior?
5. For E2EE sync: CloudKit with a user-held key, or a custom backend? CloudKit is cheaper and keeps the "no server sees your data" claim, but locks out a future Android version.

---

## Roadmap

Next up, in no particular order:

- [ ] Make the net worth page prettier
- [ ] AI chatbot over the user's own finance data
- [ ] Redesign the inventory page
- [ ] Make settings prettier
- [ ] Tidy the import page — group by month, auto-rename files
- [ ] Possibly merge the import page into another page
- [ ] Manually add other accounts on the Liquid page
- [ ] Notifications (e.g. remind to upload a statement on the 1st of the month)
- [ ] Widget

Known loose ends in the current code:

- `userCorrections` matches merchant keys as bare substrings, so a correction keyed on a short name can silently recategorize unrelated transactions retroactively.
- Per-transaction edits are lost on **Reset & Reseed** (they survive an ordinary re-import). Only dictionary-keyed corrections come back, via UserDefaults.
- GoPay's June statement is internally inconsistent — it prints `Total pengeluaran Rp3.937.156` while the rows it lists sum to Rp1.937.554. This is in GoPay's own PDF, not the parser.
- GoPay Later (BNPL) rows are recorded as debits, which is right for spend but wrong for the wallet-balance roll-forward, since nothing left the balance.

---

## Appendix A — Data model

```
Account       id, issuer, type, currency, balance, lastSyncedAt, isBalanceManual, nickname
Transaction   id, accountId, date, amount, direction, rawDescription, merchant,
              categoryId, isTransfer, dedupGroupId, sourceStatementId, confidence, isEdited
Statement     id, issuer, fileHash, periodStart, periodEnd, confidence, unaccountedAmount
Asset         id, type, name, acquiredAt, acquisitionCost, currentValue, depreciationCurve
Holding       id, instrument, symbol, quantity, avgCost, currency,
              manualPrice, lastValueIDR, lastQuotedAt
Liability     id, type, principal, outstanding, interestRate, dueDate   // reserved, unused
Subscription  id, merchant, amount, cadence, lastChargedAt, isActive
NetWorthSnapshot  id, date, totalAssets, totalLiabilities, netWorth
```

## Appendix B — Parser rule structure

Bundled at `Menej/Service/Parsing/Rules/*.json`, decoded into `IssuerRule`.

```json
{
  "issuer": "bca_mybca",
  "version": 3,
  "fingerprint": { "textContains": ["REKENING TAHAPAN", "MATA UANG : IDR"] },
  "dateFormats": ["dd/MM"],
  "amountFormat": { "decimalSeparator": ".", "thousandSeparator": "," },
  "transactionPattern": "OCR-based — see OCRRowExtractor.swift",
  "columnMap": {},
  "validation": { "requireBalanceContinuity": true }
}
```

`columnMap` is vestigial: real statement layouts turned out too idiosyncratic for one generic column-index scheme, so extraction dispatches per issuer in `RuleEngine` / `OCRRowExtractor`. The field stays for rule-file compatibility.

## Appendix C — Project structure

See [Architecture](#architecture) above.
