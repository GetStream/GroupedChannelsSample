//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import SwiftUI

struct LoadingView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .orange.opacity(0.28),
                    .yellow.opacity(0.16),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                ProgressView()
                    .controlSize(.large)

                VStack(spacing: 8) {
                    Text("Signing in")
                        .font(.title)
                        .bold()

                    Text("Opening Grouped Channels")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .frame(maxWidth: 320)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 32, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    LoadingView()
}
