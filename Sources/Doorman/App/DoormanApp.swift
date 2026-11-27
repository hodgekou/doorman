import SwiftUI

@main
struct DoormanApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPopover(model: model)
        } label: {
            Image(systemName: model.summary.menuSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
