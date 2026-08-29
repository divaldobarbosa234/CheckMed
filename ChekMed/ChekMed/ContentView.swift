import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
    }
}

#Preview {
    RootView()
        .environment(SessionStore())
        .environment(TodayPathStore())
        .environment(EntitlementStore())
}
