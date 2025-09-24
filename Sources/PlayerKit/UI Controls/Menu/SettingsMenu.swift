import SwiftUI

struct SettingsMenu: View {

    var body: some View {
        Menu {
            PlayerMenu()

        } label: {
            Image(systemName: "ellipsis")
                .circularGlassIcon()
        }
        .onTapGesture {
            PlayerManager.shared.userInteracted()
        }
    }
}


