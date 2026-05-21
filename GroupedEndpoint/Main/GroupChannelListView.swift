//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import Combine
import StreamChat
import SwiftUI

struct ChannelGroupOption: Identifiable {
    let id: String
    let title: String
}

extension ChannelGroupOption {
    static let available: [ChannelGroupOption] = [
        ChannelGroupOption(id: "new", title: "New"),
        ChannelGroupOption(id: "current", title: "Current"),
        ChannelGroupOption(id: "old", title: "Old")
    ]
}

struct GroupChannelListView: View {
    @ObservedObject var viewModel: GroupChannelListView.ViewModel
    
    init(viewModel: GroupChannelListView.ViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.channels) { channel in
                    channelListItem(for: channel)
                    .task {
                        await viewModel.loadMoreIfNeeded(after: channel)
                    }
                }
                
                footer
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .overlay {
            if viewModel.channels.isEmpty {
                ContentUnavailableView(
                    "No \(viewModel.title) Channels",
                    systemImage: viewModel.iconName,
                    description: Text(viewModel.errorMessage ?? "Channels in this group will appear here.")
                )
            }
        }
    }
    
    private func channelListItem(for channel: ChatChannel) -> some View {
        HStack(spacing: 8) {
            NavigationLink(value: channel.cid) {
                ChannelRow(channel: channel)
            }
            .buttonStyle(.plain)
            
            Spacer(minLength: 0)
            
            moveMenu(for: channel)
            
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 18, style: .continuous))
    }
    
    private func moveMenu(for channel: ChatChannel) -> some View {
        Menu {
            ForEach(ChannelGroupOption.available) { option in
                Button {
                    viewModel.move(channel: channel, to: option)
                } label: {
                    if currentGroup(for: channel) == option.id {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Image(systemName: "rectangle.3.group")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
        }
        .disabled(!channel.canUpdateChannel)
        .accessibilityLabel("Move channel")
    }
    
    private func currentGroup(for channel: ChatChannel) -> String? {
        if case let .string(value) = channel.extraData["group"] {
            value
        } else {
            nil
        }
    }
    
    @ViewBuilder private var footer: some View {
        if viewModel.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if let errorMessage = viewModel.errorMessage, !viewModel.channels.isEmpty {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }
}

extension GroupChannelListView {
    @MainActor final class ViewModel: ObservableObject, Identifiable {
        let id: String
        let title: String
        let iconName: String
        
        @Published private(set) var isLoadingMore = false
        @Published private(set) var hasLoadedAllChannels = false
        @Published private(set) var errorMessage: String?
        
        private let chatClient: ChatClient
        private let channelList: ChannelList
        private let state: ChannelListState
        private var cancellables: Set<AnyCancellable> = []
        
        init(
            id: String,
            title: String,
            iconName: String,
            chatClient: ChatClient,
            channelList: ChannelList
        ) {
            self.id = id
            self.title = title
            self.iconName = iconName
            self.chatClient = chatClient
            self.channelList = channelList
            self.state = channelList.state
            
            state.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
        
        var channels: [ChatChannel] {
            state.channels
        }
        
        func loadMoreIfNeeded(after channel: ChatChannel) async {
            guard !hasLoadedAllChannels,
                  !isLoadingMore,
                  state.channels.last?.cid == channel.cid else {
                return
            }
            
            isLoadingMore = true
            errorMessage = nil
            defer { isLoadingMore = false }
            
            do {
                let loadedChannels = try await channelList.loadMoreChannels()
                hasLoadedAllChannels = loadedChannels.isEmpty
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Could not load more channels."
            }
        }
        
        func move(channel: ChatChannel, to group: ChannelGroupOption) {
            let chat = chatClient.makeChat(for: channel.cid)
            Task {
                do {
                    try await chat.updatePartial(extraData: ["group": .string(group.id)])
                } catch {
                    print("[GroupChannelListView] failed to move channel: \(error)")
                }
            }
        }
    }
}
