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
                    users: LoginUser.availableUsers,
                    loginErrorMessage: errorMessage,
                    onSelectUser: { user in
                        logIn(as: user)
                    }
                )
            }
        }
    }

    private func logIn(as user: LoginUser) {
        viewState = .loading
        Task {
            do {
                try await streamSession.logIn(as: user)
                viewState = .loggedIn(
                    MainView.ViewModel(streamSession: streamSession)
                )
            } catch {
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
