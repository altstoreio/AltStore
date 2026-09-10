//
//  RemoteAltServerSetupComponents.swift
//  AltStore
//
//  Created by Caroline Moore on 9/4/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import SwiftUI

// MARK: - Page Layouts

struct HeroPage<Graphic: View, Content: View, Buttons: View>: View
{
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    
    @ViewBuilder
    let graphic: () -> Graphic
    
    @ViewBuilder
    let content: () -> Content
    
    @ViewBuilder
    let buttons: () -> Buttons
    
    var body: some View {
        VStack(spacing: 30) {
            graphic()
                .background {
                    ZStack {
                        Circle()
                            .fill(Color(.altLight).opacity(0.6))
                            .frame(width: 300, height: 300)
                            .blur(radius: 100)
                        
                        Circle()
                            .fill(Color(.altSecondary).opacity(0.2))
                            .frame(width: 250, height: 250)
                            .blur(radius: 100)
                    }
                }
                .accessibilityHidden(true)
            
            VStack(alignment: .center, spacing: 6) {
                Text(title)
                    .font(.title.bold())
                
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
            .multilineTextAlignment(.center)
            .layoutPriority(1)
            
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .bottomButtonBar(buttons: {
            buttons()
        })
        .transition(.push(from: .trailing))
    }
}

struct StepPage<Graphic: View, Accessory: View, Buttons: View>: View
{
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    
    @ViewBuilder
    let graphic: () -> Graphic
    
    @ViewBuilder
    let accessory: () -> Accessory
    
    @ViewBuilder
    let buttons: () -> Buttons
    
    var body: some View {
        ViewThatFits(in: .vertical) {
            // Everything fits: content takes priority and graphic fills remaining space.
            VStack(spacing: 30) {
                graphic()
                    .frame(idealHeight: 0, maxHeight: .infinity, alignment: .center)
                    .accessibilityHidden(true)
                
                content
            }
            
            // Text alone overflows: content scrolls, graphic is hidden.
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .bottomButtonBar(buttons: {
            buttons()
        })
        .transition(.push(from: .trailing))
    }
    
    private var content: some View {
        VStack(spacing: 15) {
            VStack(alignment: .center, spacing: 4) {
                Text(title)
                    .font(.title.bold())
                
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 50)
            .multilineTextAlignment(.center)
            
            accessory()
        }
    }
}

// MARK: - Components

struct PairingButton: View
{
    let state: RemoteAltServerSetupView.PairingState
    let idleTitle: LocalizedStringKey
    let waitingTitle: LocalizedStringKey
    let action: () -> Void
    
    private var title: LocalizedStringKey {
        switch state
        {
        case .idle: idleTitle
        case .waiting: waitingTitle
        case .paired: "Paired"
        }
    }
    
    var body: some View {
        SwiftUI.Button(action: action) {
            HStack(spacing: 8) {
                if state == .waiting
                {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.regular)
                }
                if state == .paired
                {
                    Image(systemName: "checkmark")
                }
                
                Text(title)
                    .contentTransition(.opacity)
            }
            .bold()
        }
        .tint(state == .paired ? .green : Color(.altPrimary))
        .disabled(state == .waiting)
        .allowsHitTesting(state != .paired) // Prevents interaction during confirmation state
        .animation(.default, value: state)
    }
}

struct GlassBadge: View
{
    let content: Text
    let color: Color
    
    var body: some View {
        if #available(iOS 26, *)
        {
            content
                .font(.footnote.bold())
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(color.opacity(0.1)), in: .capsule)
        }
        else
        {
            content
                .font(.footnote.bold())
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color.opacity(0.1), in: .capsule)
        }
    }
}

private struct BottomButtonBar<Buttons: View>: ViewModifier
{
    let buttons: Buttons
    
    func body(content: Content) -> some View
    {
        if #available(iOS 26, *)
        {
            content.safeAreaBar(edge: .bottom, spacing: 40) {
                VStack(spacing: 10) {
                    buttons
                }
                .bold()
                .tint(Color(.altPrimary))
                .controlSize(.large)
                .padding(.horizontal, 34)
                .buttonStyle(.glassProminent)
                .buttonSizing(.flexible)
            }
        }
        else
        {
            content.safeAreaInset(edge: .bottom, spacing: 40) {
                VStack(spacing: 10) {
                    buttons
                }
                .bold()
                .tint(Color(.altPrimary))
                .controlSize(.large)
                .padding(.horizontal, 34)
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private extension View
{
    func bottomButtonBar<Buttons: View>(@ViewBuilder buttons: () -> Buttons) -> some View
    {
        modifier(BottomButtonBar(buttons: buttons()))
    }
}
