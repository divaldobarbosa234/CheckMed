import SwiftUI

struct ScanView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            AddPrescriptionScreen(go: { path.append($0) })
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteView(route: route, path: $path)
                }
        }
    }
}
