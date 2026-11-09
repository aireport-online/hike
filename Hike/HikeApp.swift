import SwiftUI

@main
struct HikeApp: App {
    @State private var model = PlannerModel()

    init() {
        Brand.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
    }
}
