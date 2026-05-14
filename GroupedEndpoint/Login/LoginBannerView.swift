//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import SwiftUI

struct LoginBannerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
                .padding(18)
                .background(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: .rect(cornerRadius: 24, style: .continuous)
                )
                .shadow(color: .red.opacity(0.28), radius: 18, y: 10)

            VStack(alignment: .leading, spacing: 10) {
                Text("Welcome to Stream Chat")
                    .font(.largeTitle)
                    .bold()
                    .foregroundStyle(.primary)

                Text("Demonstrates the usage of grouped channels fetch.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 1)
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        LoginBannerView()
            .padding()
    }
}
