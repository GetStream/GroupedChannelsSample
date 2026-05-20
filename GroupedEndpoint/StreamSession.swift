//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import Foundation
import StreamChat
import class StreamChatSwiftUI.StreamChat

struct LoginUser: Identifiable, Hashable {
    let id: String
    let name: String
    let token: String
}

extension LoginUser {
    static let myuser01 = LoginUser(
        id: "myuser_1",
        name: "User 1",
        token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoibXl1c2VyXzEifQ.aJlwQTyW7XXO_1lB1s4tjucWzhzycXgODi_t2-ngsG4"
    )
    
    static let myuser02 = LoginUser(
        id: "myuser_2",
        name: "User 2",
        token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoibXl1c2VyXzIifQ.rrb4ucCeRuNZYOAKWw3XKIbriUAUmCNaYHcvmrhTeFo"
    )
    
    static let availableUsers: [LoginUser] = [
        .myuser01,
        .myuser02
    ]
}

@MainActor final class StreamSession {
    let client: ChatClient
    private let streamChat: StreamChat
    private var connectedUser: ConnectedUser?
    
    init() {
        LogConfig.level = .debug
        LogConfig.subsystems = [.httpRequests, .webSocket]
        
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
    
    func logIn(as user: LoginUser) async throws {
        let token = try Token(
            rawValue: user.token
        )
        connectedUser = try await client.connectUser(
            userInfo: UserInfo(
                id: user.id,
                name: user.name
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
            members: [
                LoginUser.myuser01.id,
                LoginUser.myuser02.id
            ],
            extraData: ["group": .string("new")]
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
