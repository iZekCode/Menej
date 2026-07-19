# Menej — Product Requirements Document

**Version:** 1.0 (draft)
**Platform:** iOS
**Date:** July 19, 2026
**Status:** Draft for review

---

## 1. Summary

Menej is an iOS app for managing a person's **entire net worth** in one place — not just another expense tracker.

The core differentiator: **users never manually log transactions.** They upload e-statements from the financial apps they already use, and Menej extracts income and expenses automatically, entirely on-device.

**Positioning statement:**
> Menej shows you what you're actually worth — without logging a single transaction, and without your financial data ever leaving your iPhone.

---

## 2. Problem

1. **Wealth is scattered.** Bank accounts, GoPay, OVO, ShopeePay, stocks, crypto, gold, plus physical assets like laptops and watches. No single number answers "what do I actually have?"
2. **Expense trackers fail because of manual input.** Retention collapses after 2-3 weeks. The burden sits on the user, even though the data already exists inside other apps.
3. **Bank-sync aggregators are immature in Indonesia**, and require handing over banking credentials — a major trust barrier.

---

## 3. Target User (v1)

**Primary — "Urban multi-wallet professional," age 25-38, Greater Jakarta and other major cities.**

- Holds 1-2 bank accounts plus 3-4 active e-wallets
- Already invests (mutual funds, stocks, crypto, or gold)
- Tech-literate, iPhone user, has tried and abandoned a finance app before
- Motivated by *awareness and wealth growth*, not *spending discipline*

---

## 4. Product Principles

1. **Zero manual entry by default.** Every time we ask the user to type something, that's a design failure. Manual input exists as an escape hatch, never as the primary flow.
2. **On-device, always.** No financial data leaves the device in v1. This is an architecture decision and a market position at the same time.
3. **Be honest about uncertainty.** When parsing fails or numbers don't reconcile, surface the gap. Never silently guess. Trust in a finance app evaporates the moment a number is wrong and the user notices.
4. **Net worth is the hero.** Every other feature exists to support that one number.

---

## 5. v1 Scope

### In scope

| # | Feature | Rationale |
|---|---|---|
| F1 | Statement parsing (3 issuers, deterministic, on-device) | The core feature and the differentiator |
| F2 | Share sheet + in-app import | The data entry point |
| F3 | Auto-categorization with learned corrections | Without it, parsed data isn't usable |
| F4 | Cross-source dedup & transfer detection | Without it, the numbers are wrong — and that's fatal |
| F5 | Net worth: assets, monthly snapshots | The product itself |
| F6 | Portfolio & physical assets | Net worth components |
| F7 | Subscriptions (from recurring detection) | Nearly free once F1 exists |
| F8 | Insights: runway + anomaly detection | The "aha" moment, and workable with thin data |
| F9 | Home Screen widget | Retention without requiring app opens |

### Deferred — with reasoning

| Feature | Deferred to | Why |
|---|---|---|
| Cashflow forecast | v1.1 | Needs 3+ months of history. On day one it would be bad, and bad forecasts destroy trust. |
| Asset allocation drift | v1.1 | Requires users to define target allocations first — heavy setup burden at launch. |
| Goals / sinking funds | v1.1 | High value, but doesn't de-risk the main v1 question (can parsing be trusted). |
| Screenshot + Vision OCR pipeline | v1.1 | A second, separate parsing path. Unlocks every issuer without statement export — ShopeePay, OVO, DANA, LinkAja — in one go, rather than being built badly under v1 pressure for a single issuer. |
| ShopeePay & OVO support | v1.1 | Blocked on the OCR pipeline above. |
| Liabilities (paylater, credit cards, installments, loans) | v1.1 | Deferred by product decision. See the note in F5. |
| E2EE cloud sync | v1.1 | Removes the device-switch data loss risk without compromising the on-device parsing position. |
| Shortcuts / App Intents | v1.1 | Moderate effort, smaller retention impact than the widget. |
| **Live Activity** | **Cut** | Live Activities are designed for *ongoing, time-bounded events* (food delivery, live matches). Net worth has neither property. Apple would likely reject it at review, and even if approved, nobody wants it parked in their Dynamic Island all day. The widget covers this need. |
| On-device LLM (Foundation Models) | v2 | A fallback layer, only relevant once issuer coverage expands. |
| Server-side parsing | v2+ | Conflicts with the privacy position; only under real pressure. |
| Bank sync via API (Brick/Ayoconnect) | Not planned | Expensive, requires a legal entity, and works against the positioning. |

---

## 6. Feature Specifications

### F1 — Statement Parsing (Deterministic, On-Device)

**v1 issuers:** myBCA, GoPay, Grab — all three provide downloadable PDF statements.

ShopeePay and OVO are excluded from v1. ShopeePay offers no monthly PDF/CSV export, so it requires the screenshot + OCR pipeline scheduled for v1.1.

**Input formats:** PDF (with a text layer), plus CSV/XLSX where the issuer provides it.

**Pipeline:**

```
File arrives
  → Issuer detection (fingerprint: headers, logo text, account number patterns)
  → Text layer extraction via PDFKit
  → Apply issuer rules (from JSON config)
  → Normalize into Transaction
  → Confidence scoring
  → User review screen
```

**Parser rules as remote config.**
Rules ship as versioned JSON, bundled in the app **and** refreshable from a CDN. Banks change statement layouts without warning. If rules live in the binary, a fix waits 1-3 days for App Store review while every BCA user experiences broken parsing. With remote config, a fix ships in minutes.

- Versioned JSON, cached locally, checked on app open (max once per day)
- The app must remain fully functional offline using cached rules
- This is the only network call in v1, and it transmits no user data

**Confidence & review.**
Every statement receives a confidence score. Low scores (unparsed rows, totals that don't reconcile) trigger a review screen flagging the problem rows. **Users always confirm before data enters the ledger.** No silent imports in v1.

**Reconciliation gap.**
If the parsed closing balance doesn't match the balance printed on the statement, show the difference explicitly as *Unaccounted*. Never hide it.

**Failure diagnostics (opt-in).**
If all parsing is local, we're blind to real-world failures. Provide a "report a parsing failure" action that sends a **redacted** sample: all digits masked, personal names stripped, structure and merchant names preserved. Explicit opt-in per report, with a preview of exactly what will be sent.

**Acceptance criteria:**
- ≥95% of transaction rows extracted correctly across a test corpus of ≥20 statements per issuer
- A 12-month statement parses in <5 seconds on an iPhone 12
- Zero network calls carrying statement contents

---

### F2 — Import & Share Sheet

- **Share Extension:** users share a PDF from Mail, Files, or WhatsApp straight into Menej without opening the app
- **In-app import:** document picker, multi-file support
- **Idempotent:** uploading the same file twice never duplicates data (file hash + date range + issuer)
- **Backlog batching:** new users will upload 6-12 months at once. This flow must feel smooth, with per-file progress and the ability to resume after a mid-batch failure.

---

### F3 — Auto-Categorization

- Rules-based merchant matching plus a bundled Indonesian merchant dictionary (Tokopedia, Shopee, Indomaret, Alfamart, Gojek, Grab, Netflix, Spotify, etc.)
- Categories: Food, Transport, Shopping, Bills, Entertainment, Health, Education, Transfer, Investment, Income, Other
- **Learns from corrections:** one correction creates a permanent merchant rule and applies retroactively to past transactions
- Supports transaction splits and custom tags

---

### F4 — Deduplication & Transfer Detection

**This is the most underrated and highest-risk feature in v1.** Get it wrong and net worth double-counts, and trust is gone permanently.

**Cases that must be handled:**

| Scenario | Correct behavior |
|---|---|
| GoPay top-up from BCA — appears in both statements | One transfer, not two expenses |
| Paying for Grab with GoPay | One expense, recorded once |
| Transfer between the user's own accounts | Not an expense; net worth unchanged |
| Pending vs settled from different sources | Merged into one |

**Approach:** match on amount + time window (±3 days) + direction + account identifiers, with a similarity score. Pairs landing in the grey zone go to the user rather than being decided by the app.

---

### F5 — Net Worth

**Assets:** bank accounts, e-wallet balances, investments, gold, physical assets, cash.

**Liabilities are deferred to v1.1.** For v1, "net worth" is effectively total assets.

> Two implications to plan for now. First, label the headline number accurately in v1 — calling it "Net Worth" while ignoring debt will overstate the figure for any user who carries paylater or card balances, which is common in the target demographic even if it doesn't apply to you. "Total Assets" is the honest label until liabilities ship. Second, keep a `Liability` table and a `totalLiabilities` field in the schema from day one, defaulting to zero. Retrofitting a second side onto the net worth calculation and all its historical snapshots is far more expensive than reserving space for it now.

**Monthly snapshots.** Net worth is frozen at each month's end so the historical chart stays honest and doesn't retroactively shift when today's asset prices move.

**Multi-currency.** IDR as base, with USD and gold support. Rates fetched daily from a public endpoint that receives no user data.

---

### F6 — Portfolio & Physical Assets

**Investment instruments:** crypto, stocks (IDX + US), mutual funds, time deposits, gold.
- Manual holding entry (quantity + cost basis)
- Prices refreshed from public sources
- Shows unrealized P/L and allocation weights

**Physical assets:** electronics, vehicles, watches, jewelry.
- Per-category depreciation curves with manual override
- Some categories **appreciate** (watches, gold) — the curve must run in both directions
- Warranty expiry dates with reminders

---

### F7 — Subscriptions

Detected from recurring transaction patterns rather than manual entry. The app finds subscriptions the user had forgotten about — which tends to be the single most memorable moment in the product.

- Shows total monthly and annual commitment
- Detects price increases
- Flags likely-dead subscriptions ("last charged 4 months ago")

---

### F8 — Insights

**Runway / Financial Independence**
> "At your current burn rate, your liquid assets last 14 months."

Requires only liquid assets and average spend — works with a single month of data. Highest insight value per unit of effort in the entire app.

**Anomaly Detection**
> "Transport is 2.4x your average this month."

Requires at least 2 months of data. Before that, hide the module entirely — don't show an empty placeholder.

**Important rule:** insights must be *withheld* until the data supports them. A wrong insight in week one does more damage than no insight at all.

All computation is rules-based and statistical, on-device. No LLM in v1 — the phrase "AI-generated insights" shouldn't appear in marketing until there's actually a model behind it.

---

### F9 — Widget

- Sizes: small (net worth + delta), medium (net worth + 6-month trend)
- Refreshes on data change, not on a timer
- **Privacy mode:** hide amounts while the device is locked (optional, on by default)

---

## 7. Design Direction

**Style:** minimalist, native iOS, lilac accent.

### Native-first

Build with standard SwiftUI components and system behaviors — `NavigationStack`, `List`, sheets, `Charts`, standard Dynamic Type, VoiceOver, Reduce Motion. No custom tab bars, no bespoke navigation, no reinvented controls.

This is a deliberate constraint, not laziness. Native components inherit accessibility, localization, and every OS update for free, and a solo developer cannot maintain a custom design system alongside a parsing engine. It also reads as trustworthy, which matters more for a finance app than visual novelty.

### Color

| Token | Light | Dark | Use |
|---|---|---|---|
| `accent` | `#7C6BC4` | `#A99BE0` | Buttons, links, selected states, active tab |
| `accentSoft` | `#EDE9F9` | `#2A2340` | Fills, chips, chart bands, card backgrounds |
| `accentPressed` | `#6455AB` | `#BFB3EA` | Pressed and focus states |

**Important caveat:** true lilac (roughly `#C8B6E2`) is too light to carry text or icons on a white background — it fails WCAG AA at around 1.8:1. The pattern that works is a **deeper lilac for anything conveying meaning** (text, icons, control tints) and **true light lilac only for fills** (backgrounds, chart bands, chips) where contrast doesn't apply. The tokens above follow this split.

**Gains and losses stay green and red.** Do not tint them lilac for brand consistency. Financial direction is the one place where convention beats aesthetics — users read those colors before they read the numbers. Use `systemGreen` and `systemRed`, and always pair them with a sign or arrow so the meaning survives for colorblind users.

### Typography

SF Pro throughout, via system text styles. One exception: **numerals use `.monospacedDigit()`** everywhere a value can change or appear in a column. Without it, net worth figures jitter on update and table columns fail to align — the single most common polish failure in finance apps.

Net worth headline: `.largeTitle`, `.bold`, monospaced digits, high contrast. It is the only element on the home screen allowed to be that large.

### Layout & motion

- Standard 16pt margins, 8pt spacing grid
- Generous whitespace — minimalism here means fewer elements, not tighter ones
- Grouped `List` insets for settings and detail screens
- SF Symbols only, no custom icon set in v1
- Motion limited to system transitions plus a subtle count-up on the net worth figure. No decorative animation.

### Dark mode

Required at launch, not deferred. This app gets opened at night, and semantic colors make it nearly free if adopted from the first screen — while retrofitting it later means auditing every view.

### What to avoid

Gradient-heavy "fintech" cards, glassmorphism, custom fonts, illustrated mascots, confetti on milestones. The product's credibility rests on the numbers being right; the visual design should recede and let them carry it.

---

## 8. Privacy & Security

| Aspect | Decision |
|---|---|
| Data storage | Local only (SwiftData/Core Data), encrypted at rest |
| Cloud sync | None in v1; E2EE sync ships in v1.1. Backup via iCloud device backup until then. |
| Authentication | Face ID / Touch ID to open the app (optional, on by default) |
| Analytics | Aggregate, anonymous events only (Aptabase or similar). No amounts, no merchant names. |
| Network calls | Only: parser rules refresh, asset prices, FX rates. None carry user data. |

**A consequence worth facing:** until E2EE sync lands in v1.1, switching phones means losing data unless the user restores from an iCloud backup. This must be communicated clearly during onboarding.

---

## 9. Success Metrics

**Primary metrics (these decide whether the product continues):**
- **Parse success rate ≥90%** across all statements uploaded by real users
- **Activation:** ≥60% of installs complete at least one import within the first 24 hours

**Supporting metrics:**
- D30 retention ≥25%
- Average ≥2 connected issuers per active user
- Category correction rate <15% of transactions
- Median time from app open → first net worth view: <5 minutes

> If parse success rate sits below 80%, adding features is pointless. The entire product premise rests on parsing being reliable.

---

## 10. Release Plan

| Phase | Contents | Estimate |
|---|---|---|
| **M1** | Parsing engine + myBCA rules, test corpus assembled | 3-4 weeks |
| **M2** | GoPay + Grab rules, share sheet, batch import | 2-3 weeks |
| **M3** | Categorization, dedup, ledger | 3 weeks |
| **M4** | Net worth, portfolio, physical assets | 3 weeks |
| **M5** | Subscriptions, insights, widget | 2 weeks |
| **M6** | Polish, TestFlight, fixes driven by real parsing failures | 3 weeks |

**Roughly 16 weeks to v1.**

**A note on the test corpus:** start collecting real statements **now**, before writing code. Parser quality is entirely determined by the diversity of statements it's tested against. Target a minimum of 20 statements per issuer, covering different date ranges, empty-month cases, and unusually long statements.

---

## 11. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Issuer changes statement format | High | Rules via remote config; opt-in failure diagnostics |
| Insufficient test statements early | High | Collect the corpus before coding; recruit 10-15 beta testers early |
| Dedup errors → double-counting | High | Conservative thresholds; ambiguous cases go to the user; surface the reconciliation gap |
| PDFs without a text layer (scans) | Medium | v1: reject with a clear message. v1.1: Vision OCR. |
| Users upload screenshots instead of PDFs | Medium | Will happen often, including for the three supported issuers. v1: detect images and explain clearly that PDF export is required, with a link to each issuer's export flow. The OCR pipeline in v1.1 resolves this. |
| v1 feels incomplete without ShopeePay | Medium | Monitor activation rate. If users stall because their main wallet is missing, pull the OCR pipeline forward rather than adding more PDF issuers. |
| App Store rejection over finance category | Low | No bank sync, no investment advice, no credential handling |

---

## 12. Open Questions

1. Which account is the "source of truth" when two statements disagree?
2. Can users edit parsed transactions? (Recommendation: yes, but mark them *edited* and retain the original value.)
3. How do we handle cash transactions that never appear on any statement? (Recommendation: one manual adjustment entry per month, not per-transaction logging.)
4. Onboarding: request the first statement upload before or after the user sees the app's interior?
5. For v1.1 E2EE sync: CloudKit with a user-held key, or a custom backend? CloudKit is cheaper and keeps the "no server sees your data" claim intact, but locks out any future Android version.

---

## Appendix A — Data Model (abbreviated)

```
Account       id, issuer, type, currency, balance, lastSyncedAt
Transaction   id, accountId, date, amount, direction, rawDescription,
              merchant, categoryId, isTransfer, dedupGroupId,
              sourceStatementId, confidence, isEdited
Statement     id, issuer, fileHash, periodStart, periodEnd,
              parsedAt, confidence, unaccountedAmount
Asset         id, type, name, acquiredAt, acquisitionCost,
              currentValue, depreciationCurve
Holding       id, instrument, symbol, quantity, avgCost, currency
Liability     id, type, principal, outstanding, interestRate, dueDate
Subscription  id, merchant, amount, cadence, lastChargedAt, isActive
NetWorthSnapshot  id, date, totalAssets, totalLiabilities, netWorth
```

## Appendix B — Parser Rules Structure (example)

```json
{
  "issuer": "bca_mybca",
  "version": 3,
  "fingerprint": {
    "textContains": ["PT BANK CENTRAL ASIA", "REKENING"]
  },
  "dateFormats": ["dd/MM/yyyy", "dd MMM yyyy"],
  "amountFormat": { "decimalSeparator": ",", "thousandSeparator": "." },
  "transactionPattern": "...",
  "columnMap": { "date": 0, "description": 1, "debit": 2, "credit": 3, "balance": 4 },
  "validation": { "requireBalanceContinuity": true }
}
```

---

## Appendix C — Project Structure

MVVM with a service layer. Within each layer, group by feature rather than dumping every file into one flat folder — by M4 you'll have 30+ views, and a single alphabetical `View/` folder becomes unnavigable.

```
Menej/
├── App/
│   ├── MenejApp.swift
│   ├── AppState.swift
│   └── DesignSystem/
│       ├── Colors.swift            // accent, accentSoft, accentPressed
│       ├── Typography.swift
│       └── Spacing.swift
│
├── Model/
│   ├── Account.swift
│   ├── Transaction.swift
│   ├── Statement.swift
│   ├── Asset.swift
│   ├── Holding.swift
│   ├── Liability.swift             // schema reserved, unused in v1
│   ├── Subscription.swift
│   ├── NetWorthSnapshot.swift
│   └── Enums/                      // Issuer, Category, Direction, AssetType
│
├── ViewModel/
│   ├── NetWorth/
│   ├── Import/
│   ├── Ledger/
│   ├── Portfolio/
│   ├── Subscriptions/
│   └── Insights/
│
├── View/
│   ├── NetWorth/                   // NetWorthHomeView, SnapshotChartView
│   ├── Import/                     // ImportFlowView, ReviewStatementView
│   ├── Ledger/                     // TransactionListView, TransactionDetailView
│   ├── Portfolio/
│   ├── Assets/
│   ├── Subscriptions/
│   ├── Insights/
│   └── Settings/
│
├── Component/
│   ├── AmountText.swift            // monospaced digits, sign, green/red
│   ├── DeltaBadge.swift
│   ├── CategoryChip.swift
│   ├── SectionCard.swift
│   ├── EmptyStateView.swift
│   └── ConfidenceBanner.swift
│
├── Service/
│   ├── Parsing/
│   │   ├── ParsingService.swift        // orchestrates the pipeline
│   │   ├── IssuerDetector.swift
│   │   ├── PDFTextExtractor.swift
│   │   ├── RuleEngine.swift
│   │   ├── TransactionNormalizer.swift
│   │   ├── ConfidenceScorer.swift
│   │   └── Rules/                      // bundled JSON fallback
│   ├── RemoteConfigService.swift       // parser rules refresh
│   ├── CategorizationService.swift
│   ├── DedupService.swift
│   ├── NetWorthService.swift
│   ├── SnapshotService.swift
│   ├── InsightService.swift            // runway, anomaly
│   ├── PricingService.swift            // quotes, FX
│   ├── PersistenceService.swift
│   └── AnalyticsService.swift
│
├── Widget/
└── ShareExtension/

MenejTests/
├── ParsingTests/
│   └── Fixtures/                   // redacted statement corpus per issuer
├── DedupTests/
└── ServiceTests/
```

**Notes**

- **Services own all logic; ViewModels only shape it for display.** If a ViewModel contains arithmetic about money, it belongs in a Service. This is what makes the parsing engine testable without instantiating any UI.
- **Services are protocol-backed** (`ParsingServiceProtocol`) so tests can inject fakes. Parsing and dedup are where bugs cost the most, so they need to be testable in isolation.
- **`Component/` holds only reusable, feature-agnostic views.** Anything used by exactly one screen lives in that feature's `View/` folder. Without this rule `Component/` slowly absorbs the whole app.
- **`ParsingService` is a framework-free target if possible.** Keeping it independent of SwiftUI and SwiftData means you can run the corpus against it from a command-line harness and iterate on rules in seconds rather than through the simulator.
- **A note on MVVM with SwiftData:** `@Query` is designed to be used directly inside views, which cuts against routing everything through a ViewModel. The pragmatic split is to let simple list screens query directly, and reserve ViewModels for screens with real logic — import review, insights, net worth composition. Forcing every screen through a ViewModel adds ceremony without benefit.
