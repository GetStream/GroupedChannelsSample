# GroupedEndpoint

An iOS demo of the Stream Chat SDK's grouped channels endpoint. One API call fetches a user's channels in named groups.

## What it does

The app displays five tabs: All, Current, New, Campaign, and Expired. Each has its own `ChannelList`. One `queryGroupedChannels(with:)` call fetches the first page for all five tabs. Current and Expired have `query_timestamp` cutoffs; All combines group and cutoff filters. New and Campaign have no additional filter. The SDK stores the returned channels in a shared local database, and each list observes the channels linked to its group.

## Key APIs

### `ChatClient.queryGroupedChannels(with:)`

`GroupedChannelsQuery` specifies the groups, an optional filter for each group, and a shared sort order. Filters require sorting by `.queryTimestamp`. The demo sends:

```swift
import StreamChat

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
try await client.queryGroupedChannels(with: query)
```

The request body is:

```json
{
  "limit": 10,
  "presence": false,
  "sort": [{"field": "query_timestamp", "direction": -1}],
  "watch": true,
  "groups": {
    "all": {"filter_conditions": {"$or": [
      {"$and": [{"group": {"$eq": "ended"}}, {"query_timestamp": {"$gte": "now-7d"}}]},
      {"group": {"$in": ["campaign", "new"]}},
      {"$and": [{"group": {"$eq": "current"}}, {"query_timestamp": {"$gte": "now-365d"}}]},
      {"$and": [{"group": {"$eq": "expired"}}, {"query_timestamp": {"$gte": "now-14d"}}]}
    ]}},
    "current": {"filter_conditions": {"query_timestamp": {"$gte": "now-365d"}}},
    "new": {},
    "campaign": {},
    "expired": {"filter_conditions": {"query_timestamp": {"$gte": "now-14d"}}}
  }
}
```

- `.daysAgo(n)` sets a cutoff relative to the first-page request. Pagination keeps that cutoff; a new query, including a refresh after reconnecting, advances it. Use `.date(_:)` for a fixed cutoff.
- Each group's filter and the sort are reused when a `ChannelList` loads more channels and when the SDK refreshes the lists after a reconnect.
- Between requests, WebSocket events only add channels that match the tab's filter. While the app is running, the SDK checks loaded channels against the filter every 60 seconds and removes those that no longer match.
- For filtered groups, the SDK maintains filtered unread channel counts on the connected user, combining the server's count for unloaded channels with local counts for loaded channels.

`limit` caps the first page at 10 channels per group in this sample. Omitting it uses the backend default. `presence` defaults to `false`; setting it to `true` includes presence information and subscribes to presence updates. `watch` defaults to `true` and subscribes to events for returned channels, including `channel.updated`.

The call returns `[ChannelGroup]` and is annotated `@discardableResult`. You can use the returned groups directly or let the `ChannelList`s observe the database updates.

### `ChatClient.queryGroupedChannels(groups:limit:presence:watch:)`

For groups without additional filters, the simpler overload fetches the first page in one request:

```swift
let groups: [ChannelGroup] = try await client.queryGroupedChannels(
    groups: ["all", "current", "new", "campaign", "expired"]
)
for group in groups {
    print("\(group.groupKey) → \(group.channels.count) channels, \(group.unreadChannels) unread")
}
```

The `groups` argument is required. A nonempty list restricts the response to those groups. Include `"all"` explicitly to request the synthetic aggregate alongside named groups. This sample uses the filter-based overload above.

### `ChatClient.makeChannelList(with:)`

Creates a UI-facing `ChannelList` bound to a group key. Pass the group key to this method; `queryGroupedChannels(with:)` supplies the group's filter and sort. The list observes channels linked to that group in the local database.

```swift
let allList      = client.makeChannelList(with: "all")
let currentList  = client.makeChannelList(with: "current")
let newList      = client.makeChannelList(with: "new")
let campaignList = client.makeChannelList(with: "campaign")
let expiredList  = client.makeChannelList(with: "expired")
```

Each list also registers itself with the SDK's sync repository as soon as it's created, so it stays in sync across reconnects with no extra wiring.

### Order does not matter

`queryGroupedChannels(with:)` and `makeChannelList(with:)` can be called in either order. The query writes channels into the shared database, and each list observes its group there. Lists created first populate when the response arrives. Lists created after the query read the stored channels immediately.

The database is the source of truth for the lists, so you do not need to retain the returned `[ChannelGroup]` values.

### `Chat.updatePartial(extraData:)`

Group membership is just `extraData["group"]` on the channel, so moving a channel between groups is a partial channel update through the state-layer `Chat`:

```swift
let chat = client.makeChat(for: cid)
try await chat.updatePartial(extraData: ["group": .string("current")])
```

The server emits a channel-updated event, and the SDK updates the channel's group in the local database. The channel leaves its previous list and joins any lists whose group and filter it matches, without another fetch. Each channel row has a menu for choosing Campaign, Current, Ended, Expired, or New. The All filter includes these groups, with cutoffs for Current, Ended, and Expired.

### Per-group unread counts

The connected user exposes unread channel counts as a `[group: count]` dictionary. For unfiltered groups, the SDK uses the server's counts. For filtered groups, it maintains counts from the grouped response and local channel state, including live events and filter expiry.

#### Reading

`ConnectedUserState.user.unreadChannelCountsByGroup` is `[String: Int]?`, keyed by group. Each value counts channels with at least one unread message. The sample displays zero when the dictionary or a key is missing:

```swift
let counts = connectedUser.state.user.unreadChannelCountsByGroup ?? [:]
let newUnread = counts["new"] ?? 0
```

#### Observing

`ConnectedUserState` declares `user` as `@Published`, so any Combine consumer works:

```swift
connectedUser.state.$user
    .map { $0.unreadChannelCountsByGroup ?? [:] }
    .removeDuplicates()
    .sink { counts in
        // Refresh tab badges from the new dictionary.
    }
    .store(in: &cancellables)
```

`$user` republishes on changes to the current user's avatar, name, total unread count, and other properties. `removeDuplicates()` prevents badge updates when the group counts have not changed.

## Driving SwiftUI from `ChannelList.state`

`ChannelList.state` is a `ChannelListState`, an `ObservableObject` whose `channels` array stays in sync with the database. Pagination uses `loadMoreChannels()`.

```swift
@MainActor
final class GroupChannelListViewModel: ObservableObject, Identifiable {
    let id: String
    let title: String

    private let channelList: ChannelList
    private let state: ChannelListState
    private var cancellables: Set<AnyCancellable> = []

    init(id: String, title: String, channelList: ChannelList) {
        self.id = id
        self.title = title
        self.channelList = channelList
        self.state = channelList.state

        state.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var channels: [ChatChannel] { state.channels }

    func loadMoreIfNeeded(after channel: ChatChannel) async {
        guard state.channels.last?.cid == channel.cid else { return }
        _ = try? await channelList.loadMoreChannels()
    }
}
```

### Wiring it up

```swift
struct MainView: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        TabView {
            ForEach(viewModel.groups) { group in
                GroupChannelListView(viewModel: group)
                    .tabItem { Label(group.title, systemImage: group.iconName) }
            }
        }
        .task {
            try? await client.queryGroupedChannels(with: query)
        }
    }
}
```

This sample creates the `ChannelList`s in the view model's `init` and calls `queryGroupedChannels(with:)` from `.task`.

## Architecture

```
GroupedEndpointApp   — @main, builds the StreamSession and root view
RootView / LoginView — gates the app on connected user state
StreamSession        — owns ChatClient; handles login, channel creation, mark-all-read
MainView             — TabView of five pages; its ViewModel calls queryGroupedChannels and tracks per-group unread counts
GroupChannelListView — renders one ChannelList via its ChannelListState and moves channels between groups
ChannelRow           — single-channel cell
```

Five group keys are used: `all`, `current`, `new`, `campaign`, `expired`. The server decides which channels land in each group, narrowed by each tab's filter. The unread badge on each tab is sourced from `ConnectedUserState.user.unreadChannelCountsByGroup`, which is kept up to date over the WebSocket.

## Dependencies

The project requires StreamChatSwiftUI 5.14.0 or later within version 5. The lockfile resolves both StreamChatSwiftUI and its StreamChat dependency to 5.14.0. These releases include the grouped-channel filter APIs used by the sample.

```
stream-chat-swift    github.com/GetStream/stream-chat-swift    version: 5.14.0 (transitive)
stream-chat-swiftui  github.com/GetStream/stream-chat-swiftui  version: 5.14.0
```
