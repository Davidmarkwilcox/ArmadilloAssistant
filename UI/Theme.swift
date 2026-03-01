//
//  Theme.swift
//  ArmadilloAssistant
//
//  Centralized design tokens + helpers for app-wide look/feel.
//  Dark-only palette: deep crimson / black / dark grey with white text.
//  Includes a reusable “metallic” background.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum Theme {

    // MARK: - 0) Brand Tokens

    enum Brand {
        static let appName: String = "Armadillo Assistant"
        static let shortName: String = "12 Armadillos, LLC"

        static let symbolName: String = "armadillo_mark"
        static let usesSystemSymbol: Bool = false

        /// Default spacing between icon + wordmark.
        static let wordmarkSpacing: CGFloat = 8

        /// Watermark strength when used as a background overlay.
        static let watermarkOpacity: Double = 0.06
    }

    /// Icon + app name lockup for headers/toolbars.
    struct WordmarkView: View {
        var title: String = Brand.appName
        var markColor: Color = Theme.Colors.textPrimary
        var titleColor: Color = Theme.Colors.textPrimary

        var body: some View {
            ZStack {
                // Centered title text (independent of icon width)
                Text(title)
                    .font(Theme.Typography.title(.bold))
                    .foregroundStyle(titleColor)

                // Left-aligned mark
                HStack {
                    if Brand.usesSystemSymbol {
                        Image(systemName: Brand.symbolName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(markColor)
                    } else {
                        Image(Brand.symbolName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 70)   // <-- keep at 70
                            .foregroundStyle(markColor)
                    }

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
        }
    }

    /// Subtle watermark overlay for select screens (dashboard / empty states).
    struct WatermarkView: View {
        var body: some View {
            WordmarkView(title: Brand.shortName)
                .opacity(Brand.watermarkOpacity)
                .padding(Theme.Spacing.l)
        }
    }

    /// Crimson screen header for tab-root screens (no `NavigationStack`).
    /// Matches the solid crimson header style shown on the Bookings screen.
    struct CrimsonHeaderView: View {
        var title: String

        var body: some View {
            ZStack {
                Theme.Colors.crimson
                    .ignoresSafeArea(edges: .top)

                VStack(spacing: 10) {
                    // Brand lockup inside the header
                    Theme.WordmarkView(markColor: .white, titleColor: .white)

                    // Screen title
                    Text(title)
                        .font(Theme.Typography.title(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .padding(.vertical, 6)
            }
            .frame(height: 75)
        }
    }

    /// Standard branded header used by all top-level screens.
    /// Matches the header sizing/spacing currently used by Bookings + Settings.
    struct BrandedHeaderView: View {
        let title: String

        var body: some View {
            ZStack {
                Theme.Colors.crimson
                    .ignoresSafeArea(edges: .top)

                VStack(spacing: 2) {
                    // Brand lockup
                    Theme.WordmarkView(markColor: .white, titleColor: .white)
                        // The wordmark view is inherently tall; pull the title closer.
                        .padding(.top, 2)

                    Text(title)
                        .font(Theme.Typography.title(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .padding(.top, -6)
                        .padding(.bottom, 2)
                }
                .padding(.horizontal, Theme.Spacing.m)
            }
            // Give enough height so the title never clips on small devices / dynamic type.
            .frame(height: 96)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(title))
        }
    }

    // MARK: - 0b) Navigation Bar Styling (UIKit)

    enum NavigationBar {
        /// Applies a solid crimson nav bar appearance.
        /// Call once at app startup (e.g., in `ArmadilloAssistantApp.init()`).
        static func applyAppearance() {
            #if canImport(UIKit)
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()

            appearance.backgroundColor = UIColor(Theme.Colors.crimson)
            appearance.shadowColor = .clear

            appearance.titleTextAttributes = [
                .foregroundColor: UIColor.white
            ]
            appearance.largeTitleTextAttributes = [
                .foregroundColor: UIColor.white
            ]

            let navBar = UINavigationBar.appearance()
            navBar.standardAppearance = appearance
            navBar.scrollEdgeAppearance = appearance
            navBar.compactAppearance = appearance
            #endif
        }
    }

    // MARK: - 1) Color Tokens

    enum Colors {
        // Core palette
        static let black = Color(red: 0.04, green: 0.04, blue: 0.05)
        static let darkGray = Color(red: 0.10, green: 0.11, blue: 0.12)
        static let elevatedGray = Color(red: 0.14, green: 0.15, blue: 0.16)

        // Deep crimson accent
        static let crimson = Color(red: 0.68, green: 0.08, blue: 0.12)

        // Text
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.78)
        static let textTertiary = Color.white.opacity(0.60)

        // Dividers / strokes
        static let stroke = Color.white.opacity(0.10)
        static let strokeStrong = Color.white.opacity(0.18)

        // Surfaces
        static let background = black
        static let surface = darkGray
        static let elevated = elevatedGray

        // Status colors (muted within palette)
        static let statusError = crimson
        static let statusWarning = textSecondary
        static let statusSuccess = textSecondary
    }

    // MARK: - 2) Layout Tokens

    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
    }

    enum Spacing {
        static let xs: CGFloat = 6
        static let s: CGFloat = 10
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Stroke {
        static let hairline: CGFloat = 1
    }

    // MARK: - 3) Typography (System fonts only)

    enum Typography {
        static func title(_ weight: Font.Weight = .semibold) -> Font { .system(.title3, design: .default).weight(weight) }
        static func headline(_ weight: Font.Weight = .semibold) -> Font { .system(.headline, design: .default).weight(weight) }
        static func body(_ weight: Font.Weight = .regular) -> Font { .system(.body, design: .default).weight(weight) }
        static func caption(_ weight: Font.Weight = .regular) -> Font { .system(.caption, design: .default).weight(weight) }
    }

    // MARK: - 4) Metallic Background

    /// A reusable metallic background that reads as “dark metal” without images.
    /// Use as a view modifier: `.themeMetallicBackground()`
    struct MetallicBackground: View {
        var body: some View {
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Colors.crimson.opacity(0.22), location: 0.00),
                        .init(color: Colors.background, location: 0.18),
                        .init(color: Colors.crimson.opacity(0.16), location: 0.42),
                        .init(color: Colors.surface.opacity(0.92), location: 0.62),
                        .init(color: Colors.crimson.opacity(0.12), location: 0.78),
                        .init(color: Colors.background, location: 1.00)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.00), location: 0.00),
                        .init(color: .white.opacity(0.08), location: 0.22),
                        .init(color: .white.opacity(0.00), location: 0.40),
                        .init(color: .white.opacity(0.06), location: 0.64),
                        .init(color: .white.opacity(0.00), location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .rotationEffect(.degrees(-25))
                .blendMode(.screen)

                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white.opacity(0.00), location: 0.00),
                        .init(color: .white.opacity(0.025), location: 0.50),
                        .init(color: .white.opacity(0.00), location: 1.00)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .scaleEffect(x: 1.0, y: 18.0, anchor: .center)
                .opacity(0.50)
                .blendMode(.overlay)

                RadialGradient(
                    gradient: Gradient(colors: [
                        Colors.crimson.opacity(0.12),
                        .clear
                    ]),
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 360
                )
                .blendMode(.plusLighter)

                RadialGradient(
                    gradient: Gradient(colors: [
                        .clear,
                        Colors.background.opacity(0.85)
                    ]),
                    center: .center,
                    startRadius: 200,
                    endRadius: 900
                )
                .blendMode(.multiply)

                WatermarkView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - 5) Component Styles (basic)

    struct CardStyle: ViewModifier {
        var elevated: Bool = false

        func body(content: Content) -> some View {
            content
                .padding(Theme.Spacing.m)
                .background(elevated ? Theme.Colors.elevated : Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .stroke(Theme.Colors.stroke, lineWidth: Theme.Stroke.hairline)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
        }
    }

    struct PrimaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(Theme.Typography.headline())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(Theme.Colors.crimson.opacity(configuration.isPressed ? 0.85 : 1.0))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .stroke(Theme.Colors.strokeStrong, lineWidth: Theme.Stroke.hairline)
                )
        }
    }
}

// MARK: - View Helpers

extension View {
    func themeMetallicBackground() -> some View {
        background(Theme.MetallicBackground())
    }

    func themeCard(elevated: Bool = false) -> some View {
        modifier(Theme.CardStyle(elevated: elevated))
    }

    func themeWatermark() -> some View {
        overlay(Theme.WatermarkView().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing))
    }
}
