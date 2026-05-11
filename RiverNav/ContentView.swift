//
//  ContentView.swift
//  RiverNav
//
//  Created by Oleg Samoylov on 11.05.2026.
//

import SwiftUI

struct ContentView: View {
    @State private var sessionManager = NavigationSessionManager()
    @State private var locationService = LocationService()

    var body: some View {
        RouteListView()
            .environment(sessionManager)
            .environment(locationService)
    }
}

#Preview {
    ContentView()
}
