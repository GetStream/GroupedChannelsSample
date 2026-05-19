# GroupedEndpoint

A focused iOS demo app that showcases the Stream Chat SDK's **grouped channels endpoint** — a single API call that lets the **server** bucket a user's channels into named groups, eliminating the need for one network request per channel list on screen.

## What it does

The app displays four channel list tabs — **All**, **New**, **Current**, and **Old** — each backed by its own `ChannelList`. Normally that would mean four HTTP requests at startup. This demo replaces them with **one** `queryGroupedChannels` call. The SDK writes every returned channel into the local database tagged with its group key, and each `ChannelList` is just a live, filtered view over that shared database.

## Key APIs

### `ChatClient.queryGroupedChannels(watch:)`

One HTTP request that fetches every group the server has defined for the current user and stores the results locally. The call is annotated `@discardableResult`, so you can ignore the return value when you only need the side effect of populating the database.

```swift
import StreamChat

// Capture the return value when you want to inspect the response directly:
let groupedChannels: GroupedChannels = try await client.queryGroupedChannels(watch: true)
for (groupKey, group) in groupedChannels.groups {
    print("\(groupKey) → \(group.channels.count) channels, \(group.unreadChannels) unread")
}

// Or fire-and-forget when the local DB is the only thing you care about:
try await client.queryGroupedChannels(watch: true)
```

Passing `watch: true` subscribes to WebSocket updates for every returned channel over the existing connection — no per-list watch setup.

### `ChatClient.makeChannelList(with:)`

Creates a UI-facing `ChannelList` bound to a group key. You do **not** pass a `ChannelListQuery`; the group key itself is the filter, and the channels come from whatever `queryGroupedChannels` (or live events) have placed in the local database under that key.

```swift
let allList     = client.makeChannelList(with: "all")
let newList     = client.makeChannelList(with: "new")
let currentList = client.makeChannelList(with: "current")
let oldList     = client.makeChannelList(with: "old")
```

### Order does not matter

`queryGroupedChannels(watch:)` and `makeChannelList(with:)` can be called in **either order**. They both operate on the same shared local database:

- `queryGroupedChannels` **writes** channels into the DB, tagged by group.
- `makeChannelList(with:)` opens a **live read** over that same DB, scoped to the group key.

So you can:

- create the `ChannelList`s up-front (e.g. in a view-model `init`) and call `queryGroupedChannels` later from a `.task { }` — the lists populate as soon as the response lands, **or**
- call `queryGroupedChannels` first and create the lists afterwards — the data is already in the DB, the lists hydrate immediately.

Either way the UI converges to the same state. This is also why you do not need to keep the `GroupedChannels` return value around — it's an acknowledgement; the source of truth is the database.

### `Chat.updatePartial(extraData:)`

Group membership is just `extraData["group"]` on the channel, so moving a channel between groups is a partial channel update through the state-layer `Chat`:

```swift
let chat = client.makeChat(for: cid)
try await chat.updatePartial(extraData: ["group": .string("current")])
```

The server emits a channel-updated event, the SDK rewrites the channel's group tag in the local DB, and every affected `ChannelList` updates live — the channel disappears from the old tab and appears in the new one without any extra fetch. The demo wires this into the chat header via a custom `ViewFactory` (`CustomViewFactory`) that adds a trailing menu for picking **New / Current / Old**.

## Driving SwiftUI from `ChannelList.state`

`ChannelList.state` is a `ChannelListState` — an `ObservableObject` whose `channels` array is kept in sync with the DB. Pagination uses `loadMoreChannels()`.

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
            try? await client.queryGroupedChannels(watch: true)
        }
    }
}
```

Creating the `ChannelList`s in the view-model's `init` and firing `queryGroupedChannels` from `.task` is the order this sample uses — but reversing it would produce the same UI.

## Architecture

```
GroupedEndpointApp   — @main, builds the StreamSession and root view
RootView / LoginView — gates the app on connected user state
StreamSession        — owns ChatClient and calls queryGroupedChannels
MainView             — TabView of four GroupChannelListView pages
GroupChannelListView — renders one ChannelList via its ChannelListState
ChannelRow           — single-channel cell
CustomViewFactory    — overrides the channel header with a group picker that calls Chat.updatePartial
```

Four group keys are used: `all`, `new`, `current`, `old`. The server decides which channels land in each group. The unread badge on each tab is sourced from `ConnectedUserState.user.groupedUnreadChannels`, which is kept up to date over the WebSocket.

## Dependencies

Both packages are pinned to the V5 grouped-channels feature branch — these APIs are not yet part of a released SDK version.

```
stream-chat-swift    github.com/GetStream/stream-chat-swift    branch: <V5 grouped-channels branch>
stream-chat-swiftui  github.com/GetStream/stream-chat-swiftui  branch: <V5 grouped-channels branch>
```
