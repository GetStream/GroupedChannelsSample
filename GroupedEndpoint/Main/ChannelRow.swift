//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI

struct ChannelRow: View {
    let channel: ChatChannel
    
    var body: some View {
        HStack(spacing: 12) {
            avatar
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    
                    if let activityDate {
                        Spacer(minLength: 12)
                        Text(activityDate, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(previewText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    Spacer(minLength: 8)
                    
                    if channel.unreadCount.messages > 0 {
                        unreadBadge
                    }
                }
            }
        }
    }
    
    @ViewBuilder private var avatar: some View {
        AsyncImage(url: channel.imageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    Circle()
                        .fill(.blue.gradient)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(.circle)
    }
    
    private var unreadBadge: some View {
        Text(unreadCountText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.blue, in: .capsule)
            .accessibilityLabel("\(channel.unreadCount.messages) unread messages")
    }
    
    private var title: String {
        guard let name = channel.name, !name.isEmpty else {
            return channel.cid.id
        }
        return name
    }
    
    private var previewText: String {
        guard let text = channel.latestMessages.first?.text, !text.isEmpty else {
            return "No messages yet"
        }
        return text
    }
    
    private var activityDate: Date? {
        channel.lastMessageAt
    }
    
    private var unreadCountText: String {
        channel.unreadCount.messages > 99 ? "99+" : "\(channel.unreadCount.messages)"
    }
}
