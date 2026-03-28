//
//  SectionHeader.swift
//  App
//
//  Created by Janardhan on 2026-03-25.
//


import SwiftUI

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary)
    }
}