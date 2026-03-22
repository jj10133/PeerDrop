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
    
    init() {
        worklet.start(name: "app", ofType: "bundle")
    }
}
