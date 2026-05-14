//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import SwiftUI

struct RootView: View {
    @State private var streamSession = StreamSession()
    @State private var viewState: ViewState = .loggedOut(nil)

    var body: some View {
        Group {
            switch viewState {
            case .loading:
                LoadingView()
            case .loggedIn(let viewModel):
                MainView(viewModel: viewModel)
            case .loggedOut(let errorMessage):
                LoginView(
                    loginErrorMessage: errorMessage,
                    onSelectUser: {
                        logIn()
                    }
                )
            }
        }
    }

    private func logIn() {
        viewState = .loading
        Task {
            do {
                try await streamSession.logIn()
                guard !Task.isCancelled else {
                    viewState = .loggedOut(nil)
                    return
                }
                viewState = .loggedIn(
                    MainView.ViewModel(streamSession: streamSession)
                )
            } catch {
                guard !Task.isCancelled else { return }
                viewState = .loggedOut("Could not sign in. Check your connection and try again.")
            }
        }
    }
}

extension RootView {
    enum ViewState {
        case loading, loggedIn(MainView.ViewModel), loggedOut(String?)
    }
}
