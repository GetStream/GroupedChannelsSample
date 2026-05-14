//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import SwiftUI

struct LoginView: View {
    let loginErrorMessage: String?
    let onSelectUser: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .orange.opacity(0.22),
                    .yellow.opacity(0.18),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .center, spacing: 28) {
                    LoginBannerView()

                    VStack(alignment: .center, spacing: 14) {
                        if let loginErrorMessage {
                            Text(loginErrorMessage)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.red.opacity(0.1), in: .rect(cornerRadius: 16, style: .continuous))
                                .accessibilityLabel("Login error: \(loginErrorMessage)")
                        }
                        Button(
                            action: { onSelectUser() },
                            label: {
                                Text("Login")
                                    .font(.headline)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                            }
                        )
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 24)
                .safeAreaPadding(.top, 28)
                .safeAreaPadding(.bottom, 32)
            }
        }
    }
}

#Preview {
    LoginView(loginErrorMessage: nil) {}
}
