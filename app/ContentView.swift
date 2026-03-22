//
//  ContentView.swift
//  App
//
//  Created by Janardhan on 2026-03-21.
//

import SwiftUI

struct ContentView: View {
    @State private var query: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    Text("PeerDrop")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button {
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    TextField("Search by Peer ID", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
            }
            .padding(16)
            .background(.ultraThinMaterial)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        
                        Text("Looking for peers...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 60)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}
