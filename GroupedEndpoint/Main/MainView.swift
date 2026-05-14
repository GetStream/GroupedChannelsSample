//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import StreamChat
import Combine
import class StreamChatSwiftUI.DefaultViewFactory
import struct StreamChatSwiftUI.ChatChannelView
import SwiftUI

struct MainView: View {
    @State private var tabSelection: String
    @ObservedObject var viewModel: ViewModel
    
    init(viewModel: ViewModel) {
        self.viewModel = viewModel
        _tabSelection = State(initialValue: viewModel.groups.first?.id ?? "")
    }
    
    var body: some View {
        NavigationStack {
            content
            .task {
                await viewModel.fetchGroupsIfNeeded()
            }
            .navigationDestination(for: ChannelId.self) { cid in
                ChatChannelView(
                    viewFactory: DefaultViewFactory.shared,
                    channelController: viewModel.channelController(for: cid)
                )
            }
            .navigationTitle("Grouped Channels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.markAllRead()
                    } label: {
                        Label("Mark all read", systemImage: "checkmark.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.createChannel()
                    } label: {
                        Label("Create channel", systemImage: "plus")
                    }
                }
            }
        }
    }
    
    @ViewBuilder private var content: some View {
        if viewModel.groups.isEmpty {
            ContentUnavailableView(
                "No Groups",
                systemImage: "rectangle.stack",
                description: Text("The grouped channels response did not include any groups.")
            )
        } else {
            TabView(selection: $tabSelection) {
                ForEach(viewModel.groups) { groupViewModel in
                    Tab(value: groupViewModel.id) {
                        GroupChannelListView(viewModel: groupViewModel)
                    } label: {
                        Label(groupViewModel.title, systemImage: groupViewModel.iconName)
                    }
                    .badge(viewModel.unreadCount(for: groupViewModel))
                }
            }
        }
    }
}

extension MainView {
    @MainActor final class ViewModel: ObservableObject {
        private static let groupKeys = ["all", "new", "current", "old"]

        let groups: [GroupChannelListView.ViewModel]
        @Published private var groupedUnreadChannels: GroupedUnreadChannels = [:]

        private let streamSession: StreamSession
        private var cancellables: Set<AnyCancellable> = []
        private var hasFetchedGroups = false

        init(streamSession: StreamSession) {
            self.streamSession = streamSession
            groups = Self.groupKeys.map { key in
                GroupChannelListView.ViewModel(
                    id: key,
                    title: Self.title(for: key),
                    iconName: Self.iconName(for: key),
                    channelList: streamSession.client.makeChannelList(with: key)
                )
            }

            streamSession.connectedUserState?.$user
                .map { $0.groupedUnreadChannels ?? [:] }
                .sink { [weak self] groupedUnreadChannels in
                    self?.groupedUnreadChannels = groupedUnreadChannels
                }
                .store(in: &cancellables)
        }

        func fetchGroupsIfNeeded() async {
            guard !hasFetchedGroups else { return }
            hasFetchedGroups = true
            do {
                try await streamSession.client.queryGroupedChannels(watch: true)
            } catch {
                hasFetchedGroups = false
                print("[MainView] failed to fetch grouped channels: \(error)")
            }
        }

        func channelController(for cid: ChannelId) -> ChatChannelController {
            streamSession.client.channelController(for: cid)
        }

        func unreadCount(for group: GroupChannelListView.ViewModel) -> Int {
            groupedUnreadChannels[group.id] ?? 0
        }

        func createChannel() {
            Task {
                do {
                    try await streamSession.createChannel()
                } catch {
                    print("[MainView] failed to create channel: \(error)")
                }
            }
        }

        func markAllRead() {
            Task {
                do {
                    try await streamSession.markAllRead()
                } catch {
                    print("[MainView] failed to mark all read: \(error)")
                }
            }
        }

        private static func title(for key: String) -> String {
            switch key {
            case "all":
                return "All"
            case "new":
                return "New"
            case "current":
                return "Current"
            case "old":
                return "Old"
            default:
                return key
                    .split(separator: "_")
                    .map { String($0).capitalized }
                    .joined(separator: " ")
            }
        }
        
        private static func iconName(for key: String) -> String {
            switch key {
            case "all":
                return "tray.full"
            case "new":
                return "sparkles"
            case "current":
                return "bubble.left.and.bubble.right"
            case "old":
                return "archivebox"
            default:
                return "rectangle.stack"
            }
        }
    }
}
