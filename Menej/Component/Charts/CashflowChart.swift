//
//  CashflowChart.swift
//  Menej
//
//  Income vs expense for the period — see PRD §6 F8. This is a gain/loss
//  context, exactly where the app's reserved green/red belong: income in the
//  gain color, expense in the loss color. Two labeled bars, so color is never
//  the only cue.
//

import SwiftUI
import Charts

struct CashflowChart: View {
    let cashflow: Cashflow

    private struct Flow: Identifiable {
        let label: String
        let amount: Decimal
        let color: Color
        var id: String { label }
    }

    private var flows: [Flow] {
        [
            Flow(label: "Income", amount: cashflow.income, color: AppColor.gain),
            Flow(label: "Expense", amount: cashflow.expense, color: AppColor.loss),
        ]
    }

    var body: some View {
        Chart(flows) { flow in
            BarMark(
                x: .value("Amount", NSDecimalNumber(decimal: flow.amount).doubleValue),
                y: .value("Flow", flow.label)
            )
            .foregroundStyle(flow.color)
            .cornerRadius(4)
            .annotation(position: .trailing, alignment: .leading) {
                AmountText(amount: flow.amount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 96)
        .accessibilityLabel("Income versus expense")
        .accessibilityValue("Income \(idr(cashflow.income)), expense \(idr(cashflow.expense))")
    }

    private func idr(_ value: Decimal) -> String {
        "Rp \(NSDecimalNumber(decimal: value).intValue)"
    }
}

#Preview {
    CashflowChart(cashflow: Cashflow(income: 12_000_000, expense: 7_500_000, savingsRate: 0.375))
        .padding()
}
