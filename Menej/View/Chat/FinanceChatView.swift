//
//  FinanceChatView.swift
//  Menej
//
//  Ask — questions in words about the money already in the ledger. Presented
//  as a sheet from InsightsView, which charts the same spending data.
//
//  Every assistant turn is the model's prose *plus* a card built from the
//  computed `FinanceAnswer`. The card's figures come from FinanceQueryService
//  through AmountText — never from the model's text — so a misphrased sentence
//  can't put a wrong number on screen without the real one beside it.
//

import SwiftUI
import SwiftData

struct FinanceChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var viewModel = FinanceChatViewModel()
    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let reason = viewModel.unavailabilityReason {
                    unavailable(reason)
                } else {
                    conversation
                }
            }
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Done only. There's no Clear because closing the sheet
                // already discards the conversation — the view is rebuilt on
                // each presentation and history is in-memory by design.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Unavailable

    /// Apple Intelligence is hardware-, region- and settings-gated, so this
    /// state is normal rather than exceptional — it states the actual reason
    /// (from SystemLanguageModel's availability) instead of failing vaguely.
    private func unavailable(_ reason: String) -> some View {
        VStack(spacing: AppSpacing.margin) {
            EmptyStateView(
                systemImage: "bubble.left.and.bubble.right",
                title: "Ask isn't available",
                message: reason
            )
            Text("Everything else in Menej works without it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Conversation

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.margin) {
                        if viewModel.messages.isEmpty {
                            emptyState
                        }
                        ForEach(viewModel.messages) { message in
                            MessageView(message: message, isHidden: appState.areAmountsHidden)
                                .id(message.id)
                        }
                        if viewModel.isResponding {
                            HStack(spacing: AppSpacing.grid) {
                                ProgressView()
                                Text("Thinking…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let errorMessage = viewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(AppSpacing.margin)
                }
                // Dragging the transcript puts the keyboard away, which is the
                // gesture people reach for first.
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages.count) { _, _ in
                    guard let last = viewModel.messages.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            composer
        }
    }

    /// The starter questions are the ones known to route to a real intent, so
    /// they double as documentation of what this can answer — better than
    /// letting the user find the edges by hitting them.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.margin) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ask about your money")
                    .font(.title3.weight(.semibold))
                Text("Answers come from the statements you've imported. The model runs on your iPhone — nothing is sent anywhere.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: AppSpacing.grid) {
                ForEach(FinanceChatViewModel.starterQuestions, id: \.self) { question in
                    Button {
                        ask(question)
                    } label: {
                        HStack(spacing: AppSpacing.grid) {
                            Text(question)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, AppSpacing.margin)
                        .padding(.vertical, AppSpacing.grid + 2)
                        .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius, style: .continuous))
                        .foregroundStyle(AppColor.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: AppSpacing.grid) {
            suggestionMenu
            TextField("Ask a question", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($isComposerFocused)
                .padding(.horizontal, AppSpacing.margin)
                .padding(.vertical, AppSpacing.grid + 2)
                .background(Color(.secondarySystemBackground), in: Capsule())
            Button {
                ask(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isResponding)
            .accessibilityLabel("Send")
        }
        .padding(AppSpacing.margin)
        .background(.bar)
        // Swiping down anywhere on the composer puts the keyboard away. A
        // vertical-axis TextField takes Return as a newline, so there's no
        // submit key to dismiss with; this and the send button are the two
        // ways out. `simultaneousGesture` so it doesn't compete with the
        // field's own text selection and caret dragging.
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard value.translation.height > 30 else { return }
                    isComposerFocused = false
                }
        )
    }

    /// The starter questions, reachable at any point in the conversation. They
    /// live in a menu rather than a row of chips so they don't take space from
    /// the transcript once the conversation is under way.
    private var suggestionMenu: some View {
        Menu {
            ForEach(FinanceChatViewModel.starterQuestions, id: \.self) { question in
                Button(question) { ask(question) }
            }
        } label: {
            Image(systemName: "lightbulb")
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(AppColor.accentSoft, in: Circle())
        }
        // Menu tints its label from `.tint`, not the label's own
        // foregroundStyle — same trick PortfolioView's currency picker needs.
        .tint(AppColor.accent)
        .disabled(viewModel.isResponding)
        .accessibilityLabel("Suggested questions")
    }

    private func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = ""
        // Sending is the end of typing — leaving the keyboard up would cover
        // the answer that's about to arrive.
        isComposerFocused = false
        Task { await viewModel.send(trimmed, modelContext: modelContext) }
    }
}

// MARK: - Messages

private struct MessageView: View {
    let message: ChatMessage
    var isHidden: Bool = false

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.subheadline)
                    .padding(.horizontal, AppSpacing.margin)
                    .padding(.vertical, AppSpacing.grid + 2)
                    .background(AppColor.accent, in: RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius, style: .continuous))
                    .foregroundStyle(.white)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: AppSpacing.grid) {
                Text(message.text)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let answer = message.answer {
                    AnswerCard(answer: answer, isHidden: isHidden)
                }
            }
        }
    }
}

/// The authoritative half of an answer. Everything here is rendered from the
/// `FinanceAnswer` the services computed.
private struct AnswerCard: View {
    let answer: FinanceAnswer
    var isHidden: Bool = false

    var body: some View {
        switch answer {
        case .spendTotal(let amount, let category, let window):
            headline(
                label: category.map { "\($0.displayName), \(window.label)" } ?? "Spent \(window.label)",
                amount: amount
            )

        case .categoryBreakdown(let breakdown, let total, let window):
            SectionCard(title: "Spent \(window.label)") {
                HStack(alignment: .center, spacing: AppSpacing.margin) {
                    CategoryDonutChart(breakdown: breakdown, total: total)
                        .frame(width: 130, height: 130)
                    VStack(alignment: .leading, spacing: AppSpacing.grid) {
                        ForEach(breakdown.prefix(5)) { slice in
                            HStack(spacing: AppSpacing.grid) {
                                Circle()
                                    .fill(slice.category.chartTint)
                                    .frame(width: 8, height: 8)
                                Text(slice.category.displayName)
                                    .font(.caption)
                                Spacer()
                                AmountText(amount: slice.total, isHidden: isHidden)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

        case .merchantSpend(let merchant, let amount, let count, let window):
            SectionCard(title: merchant) {
                VStack(alignment: .leading, spacing: 4) {
                    AmountText(amount: amount, isHidden: isHidden)
                        .font(.title2.bold())
                    Text("\(count == 1 ? "1 transaction" : "\(count) transactions") · \(window.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .largestExpenses(let entries, let window):
            SectionCard(title: "Largest, \(window.label)") {
                VStack(spacing: AppSpacing.grid) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.merchant ?? "Unknown")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(entry.date, format: .dateTime.day().month(.abbreviated))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            AmountText(amount: entry.amount, isHidden: isHidden)
                                .font(.subheadline)
                        }
                    }
                }
            }

        case .comparison(let comparison, _):
            SectionCard(title: "This month vs last") {
                VStack(alignment: .leading, spacing: AppSpacing.grid) {
                    AmountText(amount: comparison.currentTotal, isHidden: isHidden)
                        .font(.title2.bold())
                    DeltaBadge(delta: comparison.currentTotal - comparison.previousTotal)
                    Text("Last month: \(isHidden ? "••••••" : AmountText.string(amount: comparison.previousTotal))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .cashflow(let cashflow, let window):
            SectionCard(title: "Cashflow, \(window.label)") {
                VStack(spacing: AppSpacing.grid) {
                    row("Money in", cashflow.income)
                    row("Money out", cashflow.expense)
                    Divider()
                    row("Net", cashflow.net)
                }
            }

        case .netWorth(let total, let liquid, let portfolio, let inventory, let liabilities):
            SectionCard(title: "Net Worth") {
                VStack(spacing: AppSpacing.grid) {
                    AmountText(amount: total, isHidden: isHidden)
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    row("Liquid", liquid)
                    row("Portfolio", portfolio)
                    row("Inventory", inventory)
                    if liabilities > 0 {
                        row("Liabilities", liabilities, isNegative: true)
                    }
                }
            }

        case .accountBalance(let name, let amount), .assetValue(let name, let amount):
            headline(label: name, amount: amount)

        case .runway(let months, let averageMonthlySpend):
            SectionCard(title: "Runway") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(FinanceAnswerSummary.monthsText(months).capitalizedFirst)
                        .font(.title3.weight(.semibold))
                    Text("Liquid assets at \(isHidden ? "••••••" : AmountText.string(amount: averageMonthlySpend)) a month.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .anomalies(let anomalies):
            SectionCard(title: "Unusual") {
                VStack(spacing: AppSpacing.grid) {
                    ForEach(Array(anomalies.enumerated()), id: \.offset) { _, anomaly in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(anomaly.category.displayName)
                                    .font(.subheadline)
                                Text("vs \(isHidden ? "••••••" : AmountText.string(amount: anomaly.averageAmount)) average")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            AmountText(amount: anomaly.currentAmount, isHidden: isHidden)
                                .font(.subheadline)
                        }
                    }
                }
            }

        // Nothing to render: the prose above already says it, and an empty
        // card would imply data that isn't there.
        case .merchantNotFound, .merchantAmbiguous, .noData, .unsupported:
            EmptyView()
        }
    }

    private func headline(label: String, amount: Decimal) -> some View {
        SectionCard(title: nil) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                AmountText(amount: amount, isHidden: isHidden)
                    .font(.title2.bold())
            }
        }
    }

    private func row(_ label: String, _ amount: Decimal, isNegative: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            if isHidden {
                Text(verbatim: "••••••")
                    .font(.subheadline)
                    .monospacedDigit()
            } else if isNegative {
                Text("-\(AmountText.string(amount: amount))")
                    .font(.subheadline)
                    .numericStyle()
                    .foregroundStyle(AppColor.loss)
            } else {
                AmountText(amount: amount)
                    .font(.subheadline)
            }
        }
    }
}

private extension String {
    /// Sentence-cases a fragment that reads mid-sentence elsewhere ("over 3
    /// years" → "Over 3 years"). Not `capitalized`, which would title-case
    /// every word. Kept private: this is a phrasing detail of one card, not a
    /// general String utility the app should grow a dependency on.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

#Preview {
    FinanceChatView()
        .environment(AppState())
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
