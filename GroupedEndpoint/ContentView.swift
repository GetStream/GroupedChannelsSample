//
//  ContentView.swift
//  GroupedEndpoint
//
//  Created by Martin Mitrevski on 13/04/2026.
//

import SwiftUI
import StreamChat
import StreamChatSwiftUI

private struct LazyView<Content: View>: View {
    private let build: () -> Content

    init(@ViewBuilder _ build: @escaping () -> Content) {
        self.build = build
    }

    var body: some View {
        build()
    }
}

struct ContentView: View {
    @EnvironmentObject var chatManager: ChatManager
    @State private var selectedPage = 0

    var body: some View {
        ZStack {
            if chatManager.isPrefilled {
                VStack(spacing: 0) {
                    pageSelector
                    channelListPager
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.opacity)
            } else {
                loadingView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: chatManager.isPrefilled)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading conversations…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pageSelector: some View {
        HStack(spacing: 0) {
            ForEach(chatManager.channelListConfigs) { config in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedPage = config.id
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: config.icon)
                            .font(.system(size: 18))
                        Text(chatManager.title(for: config))
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selectedPage == config.id ? Color.blue : Color.secondary)
                }
                .overlay(alignment: .bottom) {
                    if selectedPage == config.id {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(height: 2)
                    }
                }
            }
        }
        .background(.bar)
    }

    private var channelListPager: some View {
        TabView(selection: $selectedPage) {
            ForEach(chatManager.channelListConfigs) { config in
                LazyView {
                    ChannelListPageView(
                        config: config,
                        title: chatManager.title(for: config)
                    )
                }
                .tag(config.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

// MARK: - ChannelListPageView

struct ChannelListPageView: View {
    let config: ChannelListConfig
    let title: String

    @StateObject private var viewModel: ChatChannelListViewModel

    init(config: ChannelListConfig, title: String) {
        self.config = config
        self.title = title
        self._viewModel = StateObject(
            wrappedValue: ChatChannelListViewModel(channelListController: config.controller)
        )
    }

    var body: some View {
        NavigationStack {
            VStack {
                Color.clear.frame(height: 50)
                ChatChannelListView(
                    viewFactory: DefaultViewFactory.shared,
                    viewModel: viewModel,
                    title: title
                )
            }
        }
    }
}
