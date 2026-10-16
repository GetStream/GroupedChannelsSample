//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import StreamChat
import Combine
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
        private static let groupKeys = ["all", "current", "new", "campaign", "expired"]

        let groups: [GroupChannelListView.ViewModel]
        @Published private var unreadChannelCountsByGroup: [String: Int] = [:]

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
                    chatClient: streamSession.client,
                    channelList: streamSession.client.makeChannelList(with: key)
                )
            }

            streamSession.connectedUserState?.$user
                .map { $0.unreadChannelCountsByGroup ?? [:] }
                .removeDuplicates()
                .sink { [weak self] unreadChannelCountsByGroup in
                    self?.unreadChannelCountsByGroup = unreadChannelCountsByGroup
                }
                .store(in: &cancellables)
        }

        func fetchGroupsIfNeeded() async {
            guard !hasFetchedGroups else { return }
            hasFetchedGroups = true
            do {
                // All five tabs in one request. Each tab has its own query_timestamp cutoff;
                // filters require sorting by query_timestamp.
                let query = GroupedChannelsQuery(
                    groups: [
                        .init(key: "all", filter: .or([
                            .and([.equal(.group, to: "ended"), .greaterOrEqual(.queryTimestamp, than: .daysAgo(7))]),
                            .in(.group, values: ["campaign", "new"]),
                            .and([.equal(.group, to: "current"), .greaterOrEqual(.queryTimestamp, than: .daysAgo(365))]),
                            .and([.equal(.group, to: "expired"), .greaterOrEqual(.queryTimestamp, than: .daysAgo(14))])
                        ])),
                        .init(key: "current", filter: .greaterOrEqual(.queryTimestamp, than: .daysAgo(365))),
                        .init(key: "new"),
                        .init(key: "campaign"),
                        .init(key: "expired", filter: .greaterOrEqual(.queryTimestamp, than: .daysAgo(14)))
                    ],
                    sort: [.init(key: .queryTimestamp)],
                    limit: 10
                )
                try await streamSession.client.queryGroupedChannels(with: query)
            } catch {
                hasFetchedGroups = false
                print("[MainView] failed to fetch grouped channels: \(error)")
            }
        }

        func channelController(for cid: ChannelId) -> ChatChannelController {
            streamSession.client.channelController(for: cid)
        }

        func unreadCount(for group: GroupChannelListView.ViewModel) -> Int {
            unreadChannelCountsByGroup[group.id] ?? 0
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
            case "campaign":
                return "Campaign"
            case "expired":
                return "Expired"
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
            case "campaign":
                return "megaphone"
            case "expired":
                return "clock.badge.xmark"
            default:
                return "rectangle.stack"
            }
        }
    }
}
