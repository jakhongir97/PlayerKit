import SwiftUI
import GoogleCast

struct GoogleCastButton: View {
    @State private var showCastDialog = false

    var body: some View {
        VStack {
            Button(action: {
                showCastDialog = true
            }) {
                Image(systemName: "airplayvideo")
                    .foregroundColor(.white)
                    .padding()
            }
            .sheet(isPresented: $showCastDialog) {
                CastDialogPresenter()
            }
        }
    }
}

import SwiftUI
import GoogleCast

struct CastDialogPresenter: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> UIViewController {
        return UIViewController()  // Return an empty view controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Present the Google Cast dialog
        DispatchQueue.main.async {
            if GCKCastContext.sharedInstance().castState != .noDevicesAvailable {
                GCKCastContext.sharedInstance().presentCastDialog()
            } else {
                print("No Chromecast devices available")
            }
        }
    }
}

