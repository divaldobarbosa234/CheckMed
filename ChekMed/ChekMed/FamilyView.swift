import SwiftUI

struct FamilyView: View {
    var go: (AppRoute) -> Void = { _ in }

    var body: some View {
        FamilyProfilesScreen(go: go)
    }
}
