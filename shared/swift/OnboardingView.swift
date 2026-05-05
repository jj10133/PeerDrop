// OnboardingView.swift — Shared onboarding UI for iOS and macOS.
// Shown once on first launch via AppStorage("hasCompletedOnboarding").

import SwiftUI

// Cross-platform color helper
#if os(iOS)
import UIKit
private typealias PlatformColor = UIColor
private extension UIColor {
    static let background = UIColor.systemBackground
}
#else
import AppKit
private typealias PlatformColor = NSColor
private extension NSColor {
    static let background = NSColor.windowBackgroundColor
}
#endif


struct OnboardingView: View {
    @EnvironmentObject var worker: Worker
    @Binding var isPresented: Bool
    @State private var currentPage = 0

    var body: some View {
        #if os(iOS)
        iOSOnboarding
        #else
        macOSOnboarding
        #endif
    }

    // MARK: - iOS

    var iOSOnboarding: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                OnboardingPage1().tag(0)
                OnboardingPage2().tag(1)
                OnboardingPage3(worker: worker).tag(2)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .animation(.easeInOut, value: currentPage)

            // Page indicator + button
            VStack(spacing: 24) {
                PageIndicator(count: 3, current: currentPage)

                Button {
                    if currentPage < 2 {
                        withAnimation { currentPage += 1 }
                    } else {
                        isPresented = false
                    }
                } label: {
                    Text(currentPage < 2 ? "Continue" : "Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                if currentPage < 2 {
                    Button("Skip") { isPresented = false }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
            .padding(.top, 16)
        }
        .background(Color(PlatformColor.background))
    }

    // MARK: - macOS

    var macOSOnboarding: some View {
        VStack(spacing: 0) {
            // Pages
            Group {
                switch currentPage {
                case 0: OnboardingPage1()
                case 1: OnboardingPage2()
                default: OnboardingPage3(worker: worker)
                }
            }
            .frame(width: 480, height: 380)
            .animation(.easeInOut, value: currentPage)
            .transition(.opacity)

            Divider()

            // Bottom bar
            HStack {
                PageIndicator(count: 3, current: currentPage)
                Spacer()
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation { currentPage -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Button(currentPage < 2 ? "Continue" : "Get Started") {
                    if currentPage < 2 {
                        withAnimation { currentPage += 1 }
                    } else {
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(20)
        }
        .frame(width: 480)
    }
}

// MARK: - Pages

struct OnboardingPage1: View {
    var body: some View {
        OnboardingPageLayout(
            symbol:   "arrow.left.arrow.right.circle.fill",
            color:    .blue,
            title:    "Welcome to PeerDrop",
            subtitle: "The fastest way to send files between your devices and contacts — directly, no middle-man."
        ) {
            FeatureRow(icon: "lock.shield.fill",    color: .blue,   text: "End-to-end encrypted")
            FeatureRow(icon: "server.rack",         color: .red,    text: "No servers, no accounts")
            FeatureRow(icon: "bolt.fill",           color: .yellow, text: "Full network speed, peer-to-peer")
        }
    }
}

struct OnboardingPage2: View {
    var body: some View {
        OnboardingPageLayout(
            symbol:   "person.badge.key.fill",
            color:    .purple,
            title:    "Your Identity",
            subtitle: "Your Peer ID is a unique cryptographic key stored only on your device. Share it once with someone — PeerDrop finds them automatically from then on."
        ) {
            FeatureRow(icon: "iphone.and.arrow.forward", color: .purple, text: "Same ID across all your devices")
            FeatureRow(icon: "qrcode",                   color: .purple, text: "Share via QR code or copy-paste")
            FeatureRow(icon: "arrow.triangle.2.circlepath", color: .green, text: "Reconnects automatically when online")
        }
    }
}

struct OnboardingPage3: View {
    let worker: Worker

    var body: some View {
        OnboardingPageLayout(
            symbol:   "checkmark.circle.fill",
            color:    .green,
            title:    "You're Ready",
            subtitle: "Your Peer ID has been generated. Share it with someone to start sending files."
        ) {
            // Show peer ID
            VStack(spacing: 8) {
                if worker.myPeerID.isEmpty {
                    ProgressView()
                        .padding(.vertical, 8)
                } else {
                    Text(worker.myPeerID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                HStack(spacing: 12) {
                    CopyButton(text: worker.myPeerID)
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Reusable layout

struct OnboardingPageLayout<Content: View>: View {
    let symbol:   String
    let color:    Color
    let title:    String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(color)
            }
            .padding(.bottom, 24)

            // Title
            Text(title)
                .font(.title2).fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            // Subtitle
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)

            // Content
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

// MARK: - Feature row

struct FeatureRow: View {
    let icon:  String
    let color: Color
    let text:  String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

// MARK: - Page indicator

struct PageIndicator: View {
    let count:   Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: i == current ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: current)
            }
        }
    }
}

// MARK: - Copy button

struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            #if os(iOS)
            UIPasteboard.general.string = text
            #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
        } label: {
            Label(copied ? "Copied!" : "Copy Peer ID",
                  systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(copied ? .green : .primary)
        .animation(.easeInOut, value: copied)
    }
}
