//
//  Worker.swift
//  App
//
//  Created by Janardhan on 2026-03-21.
//

import Foundation
import BareKit

class Worker: ObservableObject {
    let worklet = Worklet()
    
    @Published var activeDevices: [PeerDevice] = [
        PeerDevice(id: "g1", name: "Galaxy S21", systemImage: "smartphone", status: "Ready"),
        PeerDevice(id: "i12", name: "iPhone 12", systemImage: "iphone", status: "Active")
    ]
    
    init() {
        worklet.start(name: "app", ofType: "bundle")
    }
}
