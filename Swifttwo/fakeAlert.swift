// Licensed under the Any Distance Source-Available License
//
//  AppleHealthPermissionsView.swift
//  ADAC
//
//  Created by Daniel Kuntz on 11/15/22.
//

import SwiftUI

/// A view that looks like a UIAlertController that prompts the user to allow Apple Health permissions.
/// Contains a looping video showing how to allow permissions.
struct AppleHealthPermissionsView: View {
    @State var dismissing: Bool = false
    @State var isPresented: Bool = false
    var nextAction: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .opacity(isPresented ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isPresented)

            VStack(spacing: 0) {
                Text("Permissions for Apple Health")
                    .padding([.leading, .trailing, .top], 16)
                    .padding([.bottom], 4)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 17, weight: .semibold))
                Text("To sync your Activities, Any Distance needs permission to view your Apple Health data. The data is only read, it's never stored or shared elsewhere.\n\nOn the next screen, tap “Turn On All” and “Allow” to continue with your setup.")
                    .padding([.leading, .trailing, .bottom], 16)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13))

                LoopingVideoView(videoUrl: Bundle.main.url(forResource: "health-how-to", withExtension: "mp4"),
                                 videoGravity: .resizeAspect)
                    .frame(width: UIScreen.main.bounds.width * 0.7,
                           height: UIScreen.main.bounds.width * 0.55)
                    .background(Color.white)

                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(height: 0.5)

                HStack(spacing: 0) {
                    Button {
                        dismissing = true
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            UIApplication.shared.topViewController?.dismiss(animated: false)
                        }
                    } label: {
                        Text("Cancel")
                            .foregroundColor(.blue)
                            .brightness(0.1)
                            .frame(width: (UIScreen.main.bounds.width * 0.35) - 1, height: 46)
                    }
                    .buttonStyle(AlertButtonStyle())

                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 0.5, height: 46)

                    Button {
                        nextAction?()
                    } label: {
                        Text("Next")
                            .foregroundColor(.blue)
                            .brightness(0.1)
                            .frame(width: (UIScreen.main.bounds.width * 0.35) - 1, height: 46)
                    }
                    .buttonStyle(AlertButtonStyle())
                }
            }
            .background {
                BlurView()
            }
            .cornerRadius(14, style: .continuous)
            .frame(width: UIScreen.main.bounds.width * 0.7)
            .opacity(isPresented ? 1 : 0)
            .scaleEffect(dismissing ? 1 : (isPresented ? 1 : 1.15))
            .animation(.easeOut(duration: 0.25), value: isPresented)
        }
        .onAppear {
            isPresented = true
        }
    }
}

struct AppleHealthPermissionsView_Previews: PreviewProvider {
    static var previews: some View {
        AppleHealthPermissionsView()
    }
}