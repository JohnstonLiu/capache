import Combine
import Foundation

final class AppRouter: ObservableObject {
    @Published var path: [UUID] = []

    func openNote(id: UUID) {
        path = [id]
    }
}
