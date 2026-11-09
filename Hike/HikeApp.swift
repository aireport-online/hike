import SwiftUI

@main
struct HikeApp: App {
    @State private var model = PlannerModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
    }
}
