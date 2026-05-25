# GroupedEndpoint

A focused iOS demo app that showcases the Stream Chat SDK's **grouped channels endpoint** — a single API call that lets the **server** bucket a user's channels into named groups, eliminating the need for one network request per channel list on screen.

## What it does

The app displays four channel list tabs — **All**, **New**, **Current**, and **Old** — each backed by its own `ChannelList`. Normally that would mean four HTTP requests at startup. This demo replaces them with **one** `queryGroupedChannels` call. The SDK writes every returned channel into the local database tagged with its group key, and each `ChannelList` is just a live, filtered view over that shared database.

## Key APIs

### `ChatClient.queryGroupedChannels(groups:limit:presence:watch:)`

One HTTP request that fetches the first page of channels for the requested groups at once and writes them into the local DB. The alternative — `ChannelList.get()` per group — is N round-trips for N tabs. The call is annotated `@discardableResult`, so you can ignore the return value when you only need the side effect of populating the database.

```swift
import StreamChat

// `groups` is required — pass the list of group keys you want to fetch.
// The demo scopes the request to the four tabs it actually renders, and
// includes "all" explicitly to get the synthetic aggregate that covers
// every other group.
let groups: [ChannelGroup] = try await client.queryGroupedChannels(
    groups: ["all", "new", "current", "old"]
)
for group in groups {
    print("\(group.groupKey) → \(group.channelIds.count) channels, \(group.unreadChannels) unread")
}
```

`groups` is **required** — you must specify the list of group keys to fetch:

- The response is restricted to the groups you request; there is no longer a "fetch every server-configured group" default.
- Include `"all"` explicitly when you want the synthetic aggregate alongside the named groups — it is not added automatically.

The `limit` parameter caps channels-per-group on the first page (defaults to the backend's default), and `presence` opts into online-state updates over the WebSocket.

About `watch:` — ordinary channel and member events arrive for channels the user is a member of either way. What `watch: true` enables is the watcher-scoped event stream, most notably typing indicators (`typing.start` / `typing.stop`). Pass `true` if you'll show typing indicators on top of the grouped channels; leave it `false` otherwise to keep server-side watcher state minimal.

### `ChatClient.makeChannelList(with:)`

Creates a UI-facing `ChannelList` bound to a group key. You do **not** pass a `ChannelListQuery`; the group key itself is the filter, and the channels come from whatever `queryGroupedChannels` (or live events) have placed in the local database under that key.

```swift
let allList     = client.makeChannelList(with: "all")
let newList     = client.makeChannelList(with: "new")
let currentList = client.makeChannelList(with: "current")
let oldList     = client.makeChannelList(with: "old")
```

Each list also registers itself with the SDK's sync repository as soon as it's created, so it stays in sync across reconnects with no extra wiring.

### Order does not matter

`queryGroupedChannels(groups:)` and `makeChannelList(with:)` can be called in **either order**. They both operate on the same shared local database:

- `queryGroupedChannels` **writes** channels into the DB, tagged by group.
- `makeChannelList(with:)` opens a **live read** over that same DB, scoped to the group key.

So you can:

- create the `ChannelList`s up-front (e.g. in a view-model `init`) and call `queryGroupedChannels` later from a `.task { }` — the lists populate as soon as the response lands, **or**
- call `queryGroupedChannels` first and create the lists afterwards — the data is already in the DB, the lists hydrate immediately.

Either way the UI converges to the same state. This is also why you do not need to keep the `[ChannelGroup]` return value around — it's an acknowledgement; the source of truth is the database.

### `Chat.updatePartial(extraData:)`

Group membership is just `extraData["group"]` on the channel, so moving a channel between groups is a partial channel update through the state-layer `Chat`:

```swift
let chat = client.makeChat(for: cid)
try await chat.updatePartial(extraData: ["group": .string("current")])
```

The server emits a channel-updated event, the SDK rewrites the channel's group tag in the local DB, and every affected `ChannelList` updates live — the channel disappears from the old tab and appears in the new one without any extra fetch. The demo wires this into each channel list item with a menu for picking **New / Current / Old**.

### Per-group unread counts

The server tracks how many channels in each group have unread messages and exposes the counts on the connected user as a `[group: count]` dictionary. The SDK keeps the dictionary up to date over the WebSocket — no extra request needed.

#### Reading

`ConnectedUserState.user.unreadChannelCountsByGroup` is the source of truth. It is `[String: Int]?` keyed by group key; the value is the count of channels in that group with at least one unread message. `nil` and missing keys both mean "no unread channels":

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

`removeDuplicates()` matters here — `$user` republishes on any change to the current user (avatar, name, total unread, …), not just on group counts. Without it, badge views re-render on unrelated user updates.

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
            try? await client.queryGroupedChannels(groups: ["all", "new", "current", "old"])
        }
    }
}
```

Creating the `ChannelList`s in the view-model's `init` and firing `queryGroupedChannels` from `.task` is the order this sample uses — but reversing it would produce the same UI.

## Architecture

```
GroupedEndpointApp   — @main, builds the StreamSession and root view
RootView / LoginView — gates the app on connected user state
StreamSession        — owns ChatClient; handles login, channel creation, mark-all-read
MainView             — TabView of four pages; its ViewModel calls queryGroupedChannels and tracks per-group unread counts
GroupChannelListView — renders one ChannelList via its ChannelListState and moves channels between groups
ChannelRow           — single-channel cell
```

Four group keys are used: `all`, `new`, `current`, `old`. The server decides which channels land in each group. The unread badge on each tab is sourced from `ConnectedUserState.user.unreadChannelCountsByGroup`, which is kept up to date over the WebSocket.

## Dependencies

Both packages are pinned to the V5 grouped-channels feature branch — these APIs are not yet part of a released SDK version.

```
stream-chat-swift    github.com/GetStream/stream-chat-swift    branch: grouped-channels-v5
stream-chat-swiftui  github.com/GetStream/stream-chat-swiftui  branch: grouped-channels-v5
```
