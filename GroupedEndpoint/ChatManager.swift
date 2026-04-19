//
//  ChatManager.swift
//  GroupedEndpoint
//
//  Created by Martin Mitrevski on 13/04/2026.
//

import Foundation
import StreamChat
import StreamChatSwiftUI
internal import Combine

// MARK: - Custom filter keys

extension FilterKey where Scope == ChannelListFilterScope {
    static var messageCount: FilterKey<Scope, Int> { "message_count" }
}

// MARK: - ChannelListConfig

struct ChannelListConfig: Identifiable {
    let id: Int
    let groupKey: String
    let title: String
    let icon: String
    let controller: ChatChannelListController
}

// MARK: - ChatManager

class ChatManager: ObservableObject {

    static let shared = ChatManager()

    private(set) var chatClient: ChatClient
    private(set) var channelListConfigs: [ChannelListConfig] = []
    var streamChat: StreamChat
    @Published private(set) var groupedChannels: GroupedChannels?
    @Published private(set) var isPrefilled = false
    @Published private(set) var groupedUnreadChannels: GroupedUnreadChannels = [:]
    // VMs are pre-created after prefill so re-renders of ContentView don't call
    // synchronize() again on the same controller via a discarded wrappedValue VM.
    private(set) var channelListViewModels: [ChatChannelListViewModel] = []

    private var currentUserController: CurrentChatUserController?

    private init() {
        LogConfig.level = .debug
        LogConfig.subsystems = [.httpRequests]
        
        let clientConfig = ChatClientConfig(apiKeyString: "vrvdwv6pk4yz")
        chatClient = ChatClient(config: clientConfig)

        let userId = "bench-bq-0"
        let token = try! Token(
            rawValue: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiYmVuY2gtYnEtMCJ9._GNHNHTR4WyCLTHfoSisYNdXC3sDorPVwRPcb6bwdBQ"
        )

        chatClient.connectUser(
            userInfo: UserInfo(id: userId, name: "bench-bq-0", imageURL: nil),
            token: token
        )

        streamChat = StreamChat(chatClient: chatClient, utils: .init(messageListConfig: .init(dateIndicatorPlacement: .messageList)))
        setupChannelListConfigs(userId: userId)
        setupCurrentUserObserver()
        prefillControllers()
    }

    private func setupCurrentUserObserver() {
        let controller = chatClient.currentUserController()
        currentUserController = controller
        controller.delegate = self
        controller.synchronize { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.groupedUnreadChannels = controller.currentUser?.groupedUnreadChannels ?? [:]
            }
        }
    }

    /// Fetches grouped channel groups in a single request and prefills each
    /// controller so the first `synchronize()` call (made internally by the
    /// view model) skips the redundant per-controller remote query.
    private func prefillControllers() {
        Task {
            defer {
                // Always unblock the UI, even if prefill fails — controllers
                // fall back to individual synchronize() calls in that case.
                // VMs are created before isPrefilled so synchronize() inside their
                // init fires while shouldSkipInitialRemoteUpdate is still true.
                Task { @MainActor in
                    self.createViewModels()
                    self.isPrefilled = true
                }
            }
            do {
                let groupedChannels = try await chatClient.groupedQueryChannels(watch: true)
                await MainActor.run {
                    self.groupedChannels = groupedChannels
                }
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for config in channelListConfigs {
                        let channels = groupedChannels.groups[config.groupKey]?.channels ?? []
                        group.addTask { @MainActor in
                            try await withCheckedThrowingContinuation { continuation in
                                config.controller.prefill(channels: channels) { error in
                                    if let error { continuation.resume(throwing: error) }
                                    else { continuation.resume() }
                                }
                            }
                        }
                    }
                    try await group.waitForAll()
                }
            } catch {
                print("[ChatManager] prefill failed: \(error)")
            }
        }
    }

    // Must be called on MainActor after all prefill() calls complete.
    // Creates one VM per controller while shouldSkipInitialRemoteUpdate is still true,
    // so the synchronize() triggered inside ChatChannelListViewModel.init is skipped.
    @MainActor
    private func createViewModels() {
        channelListViewModels = channelListConfigs.map { config in
            ChatChannelListViewModel(channelListController: config.controller)
        }
    }

    private func setupChannelListConfigs(userId: String) {
        let now = Date()
        let minus24h = now.addingTimeInterval(-1 * 24 * 3600)
        let minus48h = now.addingTimeInterval(-2 * 24 * 3600)
        let minus14d = now.addingTimeInterval(-14 * 24 * 3600)

        // MARK: Queries (remote filter — dates fixed at startup, sent to server)

        // "all" — first-page blended inbox view
        let allQuery = ChannelListQuery(
            filter: .containMembers(userIds: [userId]),
            sort: [Sorting(key: .lastMessageAt, isAscending: false)]
        )

        // "new" — recently opened / early-life channels
        // (message_count = 0 && created_at > now-24h) || (message_count = 1 && created_at > now-48h)
        let newQuery = ChannelListQuery(
            filter: .and([
                .containMembers(userIds: [userId]),
                .or([
                    .and([.equal(.messageCount, to: 0), .greater(.createdAt, than: minus24h)]),
                    .and([.equal(.messageCount, to: 1), .greater(.createdAt, than: minus48h)])
                ])
            ]),
            sort: [Sorting(key: .createdAt, isAscending: false)]
        )

        // "current" — active channels
        // message_count >= 2 && last_message_at > now-14d
        let currentQuery = ChannelListQuery(
            filter: .and([
                .containMembers(userIds: [userId]),
                .greaterOrEqual(.messageCount, than: 2),
                .greater(.lastMessageAt, than: minus14d)
            ]),
            sort: [Sorting(key: .lastMessageAt, isAscending: false)]
        )

        // "expired" — stale / inactive channels
        // (message_count = 0 && created_at <= now-24h) ||
        // (message_count = 1 && created_at <= now-48h) ||
        // (message_count >= 2 && (last_message_at <= now-14d || last_message_at IS NULL))
        let expiredQuery = ChannelListQuery(
            filter: .and([
                .containMembers(userIds: [userId]),
                .or([
                    .and([.equal(.messageCount, to: 0), .lessOrEqual(.createdAt, than: minus24h)]),
                    .and([.equal(.messageCount, to: 1), .lessOrEqual(.createdAt, than: minus48h)]),
                    .and([
                        .greaterOrEqual(.messageCount, than: 2),
                        .or([.lessOrEqual(.lastMessageAt, than: minus14d), .isNil(.lastMessageAt)])
                    ])
                ])
            ]),
            sort: [Sorting(key: .lastMessageAt, isAscending: false)]
        )

        // MARK: Controllers (runtime filter — Date() evaluated fresh on every WS event)
        //
        // The filter closure is invoked by ChannelListLinker on every real-time event to decide
        // whether to link or unlink a channel from this query. It must mirror the server-side
        // query logic exactly, but uses a live Date() so classifications stay accurate over time.

        let allController = chatClient.channelListController(
            query: allQuery,
            filter: { channel in
                channel.membership != nil
            }
        )

        let newController = chatClient.channelListController(
            query: newQuery,
            filter: { channel in
                guard channel.membership != nil else { return false }
                let count = self.effectiveMessageCount(for: channel)
                let now = Date()
                return (count == 0 && channel.createdAt > now.addingTimeInterval(-24 * 3600))
                    || (count == 1 && channel.createdAt > now.addingTimeInterval(-48 * 3600))
            }
        )

        let currentController = chatClient.channelListController(
            query: currentQuery,
            filter: { channel in
                guard channel.membership != nil else {
                    print("[CurrentFilter] \(channel.cid) → false (no membership)")
                    return false
                }
                let emc = self.effectiveMessageCount(for: channel)
                if emc < 2 {
                    print("[CurrentFilter] \(channel.cid) → false (emc=\(emc), msgCount=\(channel.messageCount ?? -1), latestMsgs=\(channel.latestMessages.count))")
                    return false
                }
                guard let lastMessageAt = channel.lastMessageAt else {
                    print("[CurrentFilter] \(channel.cid) → false (no lastMessageAt)")
                    return false
                }
                let result = lastMessageAt > Date().addingTimeInterval(-14 * 24 * 3600)
                print("[CurrentFilter] \(channel.cid) → \(result) (emc=\(emc), lastMsgAt=\(lastMessageAt))")
                return result
            }
        )

        let expiredController = chatClient.channelListController(
            query: expiredQuery,
            filter: { channel in
                guard channel.membership != nil else { return false }
                let count = self.effectiveMessageCount(for: channel)
                let now = Date()
                if count == 0 { return channel.createdAt <= now.addingTimeInterval(-24 * 3600) }
                if count == 1 { return channel.createdAt <= now.addingTimeInterval(-48 * 3600) }
                // count >= 2: stale if last message is old or never sent
                return channel.lastMessageAt.map { $0 <= now.addingTimeInterval(-14 * 24 * 3600) } ?? true
            }
        )

        channelListConfigs = [
            ChannelListConfig(id: 0, groupKey: "all", title: "All", icon: "tray.full", controller: allController),
            ChannelListConfig(id: 1, groupKey: "new", title: "New", icon: "sparkles", controller: newController),
            ChannelListConfig(id: 2, groupKey: "current", title: "Current", icon: "bubble.left.and.bubble.right", controller: currentController),
            ChannelListConfig(id: 3, groupKey: "expired", title: "Expired", icon: "clock.badge.xmark", controller: expiredController)
        ]
    }

    private func effectiveMessageCount(for channel: ChatChannel) -> Int {
        max(
            channel.messageCount ?? 0,
            channel.latestMessages.count,
            channel.lastMessageAt == nil ? 0 : 1
        )
    }

    func title(for config: ChannelListConfig) -> String {
        let unreadCount = groupedUnreadChannels[config.groupKey] ?? 0
        return "\(config.title) (\(unreadCount))"
    }
}

// MARK: - CurrentChatUserControllerDelegate

extension ChatManager: CurrentChatUserControllerDelegate {
    func currentUserController(
        _ controller: CurrentChatUserController,
        didChangeCurrentUser change: EntityChange<CurrentChatUser>
    ) {
        let updated = change.item.groupedUnreadChannels ?? [:]
        DispatchQueue.main.async {
            self.groupedUnreadChannels = updated
        }
    }
}
