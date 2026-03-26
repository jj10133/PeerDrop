//
//  FileTransfer.swift
//  App
//
//  Created by Janardhan on 2026-03-21.
//

import Foundation

struct FileTransfer: Identifiable {
    let id:        String
    let peerId:    String   // discoveryKey of the remote peer
    let fileName:  String
    let fileSize:  Int64
    var progress:  Double
    let direction: Direction

    enum Direction {
        case sending
        case receiving
    }

    var progressPercentage: Int { Int(progress * 100) }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var isComplete: Bool { progress >= 1.0 }
}
