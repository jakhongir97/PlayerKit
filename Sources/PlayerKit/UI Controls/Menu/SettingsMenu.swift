import SwiftUI

struct SettingsMenu: View {

    var body: some View {
        Menu {
            PlayerMenu()

        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(.white)
        }
        .onTapGesture {
            PlayerManager.shared.userInteracted()
        }
    }
}


