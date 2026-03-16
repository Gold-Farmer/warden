import Foundation

struct Account: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let providerType: Provider
    var label: String
    let createdAt: Date

    init(id: UUID = UUID(), providerType: Provider, label: String, createdAt: Date = Date()) {
        self.id = id
        self.providerType = providerType
        self.label = label
        self.createdAt = createdAt
    }
}
