import SwiftUI

struct SettingsMenu: View {

    var body: some View {
        Menu {
            PlayerMenu()

        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.white)
                .padding(5)
                .contentShape(Rectangle())
        }
        .onTapGesture {
            PlayerManager.shared.userInteracted()
        }
    }
}


