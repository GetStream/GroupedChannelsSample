//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import StreamChat
import StreamChatSwiftUI
import SwiftUI

final class CustomViewFactory: ViewFactory {
    static let shared = CustomViewFactory()

    @Injected(\.chatClient) var chatClient
    var styles = LiquidGlassStyles()

    private init() {}

    func makeChannelHeaderViewModifier(
        options: ChannelHeaderViewModifierOptions
    ) -> some ChatChannelHeaderViewModifier {
        GroupPickerHeaderModifier(
            factory: self,
            channel: options.channel,
            shouldShowTypingIndicator: options.shouldShowTypingIndicator,
            chatClient: chatClient
        )
    }
}

struct GroupPickerHeaderModifier: ChatChannelHeaderViewModifier {
    private static let groupOptions: [(value: String, title: String)] = [
        ("new", "New"),
        ("current", "Current"),
        ("old", "Old")
    ]

    let factory: CustomViewFactory
    let channel: ChatChannel
    let shouldShowTypingIndicator: Bool
    let chatClient: ChatClient

    func body(content: Content) -> some View {
        content
            .modifier(DefaultChannelHeaderModifier(
                factory: factory,
                channel: channel,
                shouldShowTypingIndicator: shouldShowTypingIndicator
            ))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(Self.groupOptions, id: \.value) { option in
                            Button {
                                updateGroup(to: option.value)
                            } label: {
                                if currentGroup == option.value {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "rectangle.3.group")
                    }
                    .accessibilityLabel("Change group")
                }
            }
    }

    private var currentGroup: String? {
        if case let .string(value) = channel.extraData["group"] { value } else { nil }
    }

    private func updateGroup(to value: String) {
        let chat = chatClient.makeChat(for: channel.cid)
        Task {
            do {
                try await chat.updatePartial(extraData: ["group": .string(value)])
            } catch {
                print("[GroupPickerHeader] failed to update group: \(error)")
            }
        }
    }
}
