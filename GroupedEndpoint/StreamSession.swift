//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import Foundation
import StreamChat
import class StreamChatSwiftUI.StreamChat

@MainActor final class StreamSession {
    let client: ChatClient
    private let streamChat: StreamChat
    private var connectedUser: ConnectedUser?
    
    init() {
        LogConfig.level = .debug
        LogConfig.subsystems = [.httpRequests]
        
        let clientConfig = ChatClientConfig(apiKeyString: "vrvdwv6pk4yz")
        client = ChatClient(config: clientConfig)
        streamChat = StreamChat(
            chatClient: client,
            utils: .init(
                messageListConfig: .init(
                    dateIndicatorPlacement: .messageList
                )
            )
        )
    }
    
    func logIn() async throws {
        let token = try Token(
            rawValue: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiYmVuY2gtYnEtMCJ9._GNHNHTR4WyCLTHfoSisYNdXC3sDorPVwRPcb6bwdBQ"
        )
        connectedUser = try await client.connectUser(
            userInfo: UserInfo(
                id: "bench-bq-0",
                name: "bench-bq-0"
            ),
            token: token
        )
    }
    
    func createChannel() async throws {
        let channelId = ChannelId(type: .messaging, id: UUID().uuidString)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM HH:mm:ss"
        let channelName = "Channel \(formatter.string(from: Date()))"
        
        let chat = try client.makeChat(
            with: channelId,
            name: channelName,
            members: ["member_03"]
        )
        try await chat.get(watch: true)
        try await chat.sendMessage(with: "Hello")
    }
    
    func markAllRead() async throws {
        try await connectedUser?.markAllChannelsRead()
    }
    
    var connectedUserState: ConnectedUserState? {
        connectedUser?.state
    }
}
