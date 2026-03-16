import SwiftUI

struct CostLabel: View {
    let cost: Decimal?
    var style: Font = .headline

    var body: some View {
        Text(Formatters.formatCost(cost))
            .font(style)
            .foregroundStyle(cost != nil ? .grafanaTextPrimary : .grafanaTextDisabled)
            .monospacedDigit()
    }
}
