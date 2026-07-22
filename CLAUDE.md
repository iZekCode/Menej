# CLAUDE.md

Guidance for Claude Code working in this repo. Product and architecture live in [README.md](README.md) — this file is only the things that will bite you.

## This machine cannot build the app

Only Command Line Tools are installed, no full Xcode. `xcodebuild` cannot verify an iOS build here. Do not claim a change compiles unless you actually verified it.

What *is* available:

```bash
# Syntax only — works on any file, including SwiftUI views
swiftc -parse path/to/File.swift

# Real typecheck — only for files free of UIKit/SwiftUI-iOS-only API
swiftc -typecheck -sdk $(xcrun --show-sdk-path --sdk macosx) -parse-as-library \
  $(find Menej -name "*.swift" -path "*Parsing*") Menej/Model/Enums/*.swift
```

Most of `Service/` typechecks against the macOS SDK. Views do not (`textInputAutocapitalization`, `keyboardType`, `navigationBarTitleDisplayMode`, `Color(.secondarySystemBackground)` are iOS-only) — `swiftc -parse` is the ceiling for those. Say so plainly rather than implying more verification than happened.

Tests **do** run on the user's machine (⌘U). The `MenejTests` target exists and uses Xcode 16 synchronized folder groups, so any file added under `MenejTests/` is automatically a member — no project-file edit needed. Same for `Menej/` and `MenejShareExtension/`.

## Verifying parser changes

`ParsingService` imports no SwiftUI and no SwiftData specifically so the corpus can be run from a command-line harness. This is the main workflow for parsing work: copy the extractor logic into a standalone `.swift` file, `swiftc -O` it, and run it against `Menej/Financial Statement/`. Iterating through the simulator is far slower.

**Every statement carries its own ground truth. Always reconcile against it:**

| Issuer | Printed truth | Expected |
|---|---|---|
| myBCA | `SALDO AWAL`→`SALDO AKHIR` + `MUTASI CR`/`MUTASI DB` counts and totals | exact, `unaccounted = 0` |
| Grab | `Jumlah Pemesanan` / `Jumlah: IDR` header | exact |
| GoPay | `records + coins-only == date-line count` | every row captured |

GoPay's printed `Total pemasukan`/`Total pengeluaran` are **net of coins** and are not a valid target — the gap equals that month's `Total Coins dipakai`. GoPay's June statement is additionally self-inconsistent by Rp 2.000.000; that's in the PDF, not the parser.

Check **counts, not just sums.** April's myBCA page 3 holds six identical 271,000 credits; a parser can lose one and still look close on a sum-only check.

### Two traps that have already caused wrong conclusions

1. **Join pages with a newline.** `PDFTextExtractor` does `text += pageText + "\n"`. A harness doing `text += page.string` glues each page's last line onto the next page's header (`-Rp46.065E-statement Halaman 4 dari 6`), which breaks the end-anchored amount regex and fabricates a parsing bug that does not exist. This exact mistake produced a confident, fully-wrong report of 12 missing transactions.
2. **macOS Vision ≠ iOS Vision.** The harness OCRs with the macOS engine; the app uses iOS. Bounding-box baselines differ. A harness result is evidence about the *logic*, not proof about the device. Don't upgrade "reproduced a mechanism" into "confirmed the cause."

## Hard rules

- **`SeedDataService` is `#if DEBUG` only.** The bundled PDFs are real personal financial documents — a real account number, real name, real transactions. Never remove the guard without replacing the corpus with redacted files first.
- **`resetAndSeed` must not delete `Account` rows.** For GoPay and Grab the balance the user typed is the only balance that exists; those issuers print none. Clear statement-derived anchors (`!isBalanceManual`) instead.
- **A record that fails extraction must still be emitted**, with an empty amount, so normalization rejects it. `ConfidenceScorer.score` is `transactions.count / rawRowCount` — silently dropping a bad row shrinks both sides and reports a lost transaction as a perfect 1.0 parse.
- **Never tint gains/losses with the brand accent.** Green/red plus a sign, always.

## SwiftData gotchas hit in this codebase

- `#Predicate` cannot capture enum values. It compiles and throws at runtime ("Captured/constant values of type 'Issuer' are not supported"). Fetch and filter in Swift instead — see `ImportViewModel.findOrCreateAccount`.
- `NetWorthSnapshot` is frozen once written for a month (`upsertSnapshotIfNeeded` returns early). Re-importing corrected data does **not** repair history.
- Holdings cache a whole-position `lastValueIDR` that net worth reads synchronously. Any edit that changes quantity must rescale it; changing symbol/instrument/currency must clear it.

## Conventions

- **Services own logic; ViewModels only shape it for display.** Arithmetic about money in a ViewModel belongs in a Service.
- **Comments explain *why*, not *what*.** This codebase's comments carry hard-won findings — real-corpus evidence, rejected alternatives, the reason a threshold has its value. Match that. When you record a finding, be exact about its status: reproduced, inferred, or assumed.
- `Component/` is for feature-agnostic reusable views only. One-screen views live in that feature's `View/` folder.
- Source comments cite `PRD §6 F1`-style references. The PRD was folded into README.md with the numbering preserved; keep new references in that form.
- Match surrounding comment density and naming. Don't restate the README in code comments.

## Scratch work

Harnesses, dumps and experiments go in the session scratchpad, never in the repo.
