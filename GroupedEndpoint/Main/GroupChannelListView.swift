//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import Combine
import StreamChat
import SwiftUI

struct GroupChannelListView: View {
    @ObservedObject var viewModel: GroupChannelListView.ViewModel
    
    init(viewModel: GroupChannelListView.ViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.channels) { channel in
                    NavigationLink(value: channel.cid) {
                        ChannelRow(channel: channel)
                    }
                    .buttonStyle(.plain)
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
        
        private let channelList: ChannelList
        private let state: ChannelListState
        private var cancellables: Set<AnyCancellable> = []
        
        init(
            id: String,
            title: String,
            iconName: String,
            channelList: ChannelList
        ) {
            self.id = id
            self.title = title
            self.iconName = iconName
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
    }
}
