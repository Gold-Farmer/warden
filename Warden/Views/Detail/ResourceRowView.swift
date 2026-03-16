import SwiftUI

struct ResourceRowView: View {
    let resource: ResourceQuota

    var body: some View {
        HStack(spacing: 12) {
            // Utilization indicator dot
            Circle()
                .fill(Color.forUtilization(resource.utilizationLevel))
                .frame(width: 6, height: 6)

            // Name
            Text(resource.name)
                .font(.system(size: 12))
                .foregroundStyle(.grafanaTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Bar gauge
            BarGaugeView(
                fraction: resource.utilizationFraction,
                label: resource.name,
                valueText: "",
                height: 10,
                showLabel: false,
                style: .segmented
            )
            .frame(width: 120)

            // Usage text
            Text(usageText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.grafanaTextPrimary)
                .frame(width: 110, alignment: .trailing)

            // Cost
            if let cost = resource.cost {
                Text(Formatters.formatCost(cost))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.grafanaGreen)
                    .frame(width: 70, alignment: .trailing)
            } else {
                Color.clear.frame(width: 70)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color.grafanaPanelBg)
    }

    private var usageText: String {
        let used = Formatters.formatUsage(resource.used, unit: resource.unit)
        if let limit = resource.limit {
            return "\(used) / \(Formatters.formatUsage(limit, unit: resource.unit))"
        }
        return used
    }
}
