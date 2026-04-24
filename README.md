# GroupedEndpoint

A focused iOS demo app that showcases two new Stream Chat SDK APIs — **grouped channel endpoint** and **prefill** — that together eliminate redundant network requests when a user has multiple channel lists on the same screen.

## What it does

The app displays four channel list tabs — **All**, **New**, **Current**, and **Expired** — each backed by a separate `ChannelListController`. Normally, four controllers would fire four HTTP requests at startup. This demo replaces those four requests with a single `queryGroupedChannels` call, then seeds each controller locally using `prefill(group:)` so the UI renders immediately without waiting for per-controller network responses.

![Four tabs: All, New, Current, Expired — each showing a live channel list]

## Key APIs

### `ChatClient.queryGroupedChannels(watch:)`

A single HTTP request that fetches all channel groups at once and returns a `GroupedChannels` value — a dictionary keyed by group name, each containing the channels that match that group's query.

```swift
let groupedChannels = try await chatClient.queryGroupedChannels(watch: true)
```

Passing `watch: true` subscribes to WebSocket events for all returned channels simultaneously, so subsequent updates arrive over the existing connection without additional setup.

### `ChannelListController.prefill(group:completion:)`

Seeds a controller's local database state from a `ChannelGroup` taken out of the `GroupedChannels` response, without making a network request. When the controller later calls `synchronize()` internally (e.g. inside `ChatChannelListViewModel.init`), it finds existing data and skips the redundant remote query.

```swift
config.controller.prefill(group: channelGroup) { error in
    // controller is now seeded; creating the view model won't trigger a network call
}
```

### Prefill flow

```swift
func prefillControllers() async {
    defer {
        Task { @MainActor in
            createViewModels()      // view models created after prefill
            isPrefilled = true      // gates the UI
        }
    }

    do {
        let groupedChannels = try await chatClient.queryGroupedChannels(watch: true)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for config in channelListConfigs {
                group.addTask { @MainActor in
                    guard let channelGroup = groupedChannels[config.groupKey] else { return }
                    try await withCheckedThrowingContinuation { continuation in
                        config.controller.prefill(group: channelGroup) { error in
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume() }
                        }
                    }
                }
            }
            try await group.waitForAll()
        }
    } catch {
        // on failure the defer block still runs; controllers fall back
        // to their individual synchronize() calls
    }
}
```

The `defer` block ensures view models are always created, even when `queryGroupedChannels` throws. In the error case, each `ChatChannelListViewModel` falls back to its normal individual network request.

## Channel groups

Four groups are defined. Each group has both a server-side `ChannelListQuery` (evaluated once at startup) and a runtime filter closure (re-evaluated on every WebSocket event to reclassify channels as time passes).

| Group | Title | Server-side filter | Runtime re-classification |
|---|---|---|---|
| `all` | All | User is a member | `membership != nil` |
| `new` | New | `messageCount ≤ 1` and recently created | Same bounds, live `Date()` |
| `current` | Current | `messageCount ≥ 2` and last message within 14 days | Same, live `Date()` |
| `expired` | Expired | No recent activity | Same, live `Date()` |

The server-side dates are fixed snapshots sent with the query. The runtime closures use a fresh `Date()` each time, so channels migrate between groups (e.g. from New to Expired) without requiring a new network request.

## Architecture

```
GroupedEndpointApp   — @main, injects ChatManager into the environment
ContentView          — tab bar + paged TabView, gated on isPrefilled
ChatManager          — ObservableObject singleton, owns all SDK objects
```

`ContentView` shows a loading spinner until `chatManager.isPrefilled` is `true`. Once set, four `ChatChannelListView` pages (from `StreamChatSwiftUI`) are rendered, one per group. Each tab label includes the live unread count for that group, sourced from `CurrentChatUserController`.

A `LazyView` wrapper defers `ChatChannelListViewModel` construction until a tab is actually selected, which keeps the prefill skip-flag active on the controllers that haven't been visited yet.

## Dependencies

Both packages are pinned to the `grouped-channels-endpoint` feature branch — these APIs are not yet part of a released SDK version.

```
stream-chat-swift    github.com/GetStream/stream-chat-swift    branch: grouped-channels-endpoint
stream-chat-swiftui  github.com/GetStream/stream-chat-swiftui  branch: grouped-channels-endpoint
```

## Requirements

- Xcode 26.3+
- iOS 26.2+ deployment target
