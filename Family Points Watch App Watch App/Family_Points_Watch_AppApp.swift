//
//  Family_Points_Watch_AppApp.swift
//  Family Points Watch App Watch App
//
//  Created by Jeffrey Sutherland on 11/13/26.
//

import SwiftUI

@main
struct Family_Points_Watch_App_Watch_AppApp: App {
    @State private var dashboardModel = WatchDashboardModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dashboardModel)
        }
    }
}
