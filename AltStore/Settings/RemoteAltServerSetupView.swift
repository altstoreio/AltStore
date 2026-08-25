//
//  RemoteAltServerSetupView.swift
//  AltStore
//
//  Created by Caroline Moore on 8/13/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import SwiftUI

import AltStoreCore

@available(iOS 26, *)
extension RemoteAltServerSetupView
{
    enum Step
    {
        case welcome
        case pairWithComputer
        case pairOnDevice
        case installVPN
        case finish
    }
    
    enum PairingState
    {
        case idle
        case waiting
        case paired
    }
    
    private static func makePlan() async -> [Step]
    {
        var plan: [Step] = [.welcome]
        
        // Relies on the fact that sign-in is required before this view is shown,
        // so nil definitely means "no pairing file" — not "bundled file we can't decrypt yet".
        if AppManager.shared.devicePairingFile == nil
        {
            if #available(iOS 27, *)
            {
                plan.append(.pairOnDevice)
            }
            else
            {
                plan.append(.pairWithComputer)
            }
        }
        
        if await !AppManager.shared.isReachableOnDevice()
        {
            plan.append(.installVPN)
        }
        
        plan.append(.finish)
        return plan
    }
}

@available(iOS 26, *)
struct RemoteAltServerSetupView: View
{
    let plan: [Step]
    
    let completionHandler: () -> Void
    
    @State
    private var currentStep: Step = .welcome
    
    @State
    private var pairingState: PairingState = .idle
    
    @State
    private var pairingAttempt: Int?

    @State
    private var isShowingError = false

    @State
    private var errorMessage = ""
    
    @Environment(\.openURL)
    private var openURL
    
    @Environment(\.dismiss)
    private var dismiss
    
    init(plan: [Step], completionHandler: @escaping () -> Void)
    {
        self.plan = plan
        self.completionHandler = completionHandler
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                switch currentStep
                {
                case .welcome: welcomeStep
                case .pairWithComputer: pairWithComputerStep
                case .pairOnDevice: pairOnDeviceStep
                case .installVPN: installVPNStep
                case .finish: finishStep
                }
            }
            .toolbar {
                SwiftUI.Button(role: .close) {
                    dismiss()
                }
            }
            .task(id: pairingAttempt) {
                guard pairingAttempt != nil else { return } // Only pair after a tap.
                
                do
                {
                    pairingState = .waiting
                    try await AppManager.shared.waitForPairingFile()
                    
                    pairingState = .paired
                    
                    // Brief pause so the user registers 'Paired' before moving on.
                    try await Task.sleep(for: .seconds(1))
                    advance()
                }
                catch is CancellationError {}
                catch
                {
                    pairingState = .idle
                    errorMessage = error.localizedDescription
                    isShowingError = true
                }
            }
            .alert("Unable to Pair with AltServer", isPresented: $isShowingError) {
                SwiftUI.Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sensoryFeedback(.success, trigger: pairingState) { _, newValue in newValue == .paired }
        }
    }
    
    private var pageControl: PageControl {
        PageControl(currentIndex: plan.firstIndex(of: currentStep) ?? 0, count: plan.count)
    }
    
    func advance()
    {
        // If we're on the last step, return complete.
        guard let index = plan.firstIndex(of: currentStep), index + 1 < plan.count else { return completionHandler() }
        
        withAnimation {
            currentStep = plan[index + 1]
        }
    }
}

@available(iOS 26, *)
private extension RemoteAltServerSetupView
{
// MARK: - Welcome [Step]
    
    var welcomeStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("LogoRecessed")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 90, height: 90)
                    .background {
                        Circle()
                            .fill(Color.altTertiary.opacity(0.5))
                            .frame(width: 150, height: 150)
                            .blur(radius: 50)
                    }
                
                VStack(alignment: .center, spacing: 6) {
                    Text("Remote AltServer")
                        .font(.title.bold())
                    
                    Text("Use AltStore without a computer. Set up once, then sideload from anywhere.\nHere's what you'll need:")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
                .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 12) {
                    RequirementRow(systemImage: "link", title: "Pair this device", subtitle: "One-time setup; we'll guide you.")
                    
                    Divider()
                        .padding(.leading, 50)
                    
                    RequirementRow(systemImage: "shield", title: "LocalDevVPN", subtitle: "Connected while you sideload.")
                    
                    Divider()
                        .padding(.leading, 50)
                    
                    RequirementRow(systemImage: "wifi", title: "Wi-Fi", subtitle: "On while you sideload.")
                }
                .padding()
                .background(Color(.systemGroupedBackground), in: .rect(cornerRadius: 26))
                .padding(20)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom, spacing: 20) {
            VStack(spacing: 10) {
                pageControl
                    .padding(.vertical, 10)
                
                SwiftUI.Button("Begin Setup") { advance() }
                    .bold()
                    .tint(.altPrimary)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .buttonSizing(.flexible)
                    .padding(.horizontal, 34)
            }
        }
        .transition(.push(from: .trailing))
    }
    
// MARK: - Pair With Computer [Step]
    
    var pairWithComputerStep: some View {
        StepPage {
            Image("ConnectGraphic")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 500)
        } content: {
            VStack(spacing: 15) {
                VStack(alignment: .center, spacing: 4) {
                    Text("Connect to Computer")
                        .font(.title.bold())
                    
                    Text("Plug this device into your computer with a cable, then open AltServer.")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 50)
                .multilineTextAlignment(.center)
                
                Text("Tap 'Trust' when prompted.")
                    .font(.footnote.bold())
                    .foregroundStyle(Color.altSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(Color.altSecondary.opacity(0.1)), in: .capsule)
            }
        } buttons: {
            pageControl
                .padding(.vertical, 10)
            
            PairingButton(state: pairingState, idleTitle: "Pair with AltServer", waitingTitle: "Connecting to AltServer…") {
                pairingAttempt = (pairingAttempt ?? 0) + 1
            }
        }
    }
    
// MARK: - Pair On Device [Step]
    
    var pairOnDeviceStep: some View {
        StepPage {
            Image("PairOnDeviceGraphic")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 580)
        } content: {
            VStack(spacing: 15) {
                VStack(alignment: .center, spacing: 4) {
                    Text("Pair in Settings")
                        .font(.title.bold())
                    
                    Text("Start Pairing will take you to Settings, where you can 'Pair with AltStore'.")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 50)
                .multilineTextAlignment(.center)
                
                Text("Enter your passcode to pair.")
                    .font(.footnote.bold())
                    .foregroundStyle(Color.altSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(Color.altSecondary.opacity(0.1)), in: .capsule)
            }
        } buttons: {
            pageControl
                .padding(.vertical, 10)
            
            PairingButton(state: pairingState, idleTitle: "Open Settings", waitingTitle: "Waiting to Pair…") {
                advance()
            }
        }
    }
    
// MARK: - Install VPN [Step]
    
    var installVPNStep: some View {
        StepPage {
            Image("LocalDevVPN")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 340)
        } content: {
            VStack(alignment: .center, spacing: 4) {
                Text("Install LocalDevVPN")
                    .font(.title.bold())
                
                Text("Remote AltServer requires LocalDevVPN to sideload apps.")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 50)
            .multilineTextAlignment(.center)
        } buttons: {
            pageControl
                .padding(.vertical, 10)
            
            SwiftUI.Button("Get LocalDevVPN") {
                openURL(URL(string: "https://apps.apple.com/app/id6755608044")!)
                advance()
            }
            
            SwiftUI.Button("Not Now") { advance() }
                .buttonStyle(.glass)
        }
    }
    
// MARK: - Finish [Step]
    
    var finishStep: some View {
        StepPage {
            Image("VPNGraphic")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 480)
        } content: {
            VStack(spacing: 15) {
                VStack(alignment: .center, spacing: 4) {
                    Text("Setup Complete!")
                        .font(.title.bold())
                    
                    Text("To sideload apps, make sure Wi-Fi and your VPN are both connected.")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 50)
                .multilineTextAlignment(.center)
                
                Text("Open LocalDevVPN 􀰾")
                    .font(.footnote.bold())
                    .foregroundStyle(Color.altSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(Color.altSecondary.opacity(0.1)), in: .capsule)
            }
        } buttons: {
            pageControl
                .padding(.vertical, 10)
            
            SwiftUI.Button("Finish") { advance() }
        }
    }
}

// MARK: - Components

@available(iOS 26, *)
private struct StepPage<Graphic: View, Content: View, Buttons: View>: View
{
    private let graphic: Graphic
    private let content: Content
    private let buttons: Buttons
    
    init(@ViewBuilder graphic: () -> Graphic, @ViewBuilder content: () -> Content, @ViewBuilder buttons: () -> Buttons)
    {
        self.graphic = graphic()
        self.content = content()
        self.buttons = buttons()
    }
    
    var body: some View {
        ViewThatFits(in: .vertical) {
            // Everything fits: content takes priority and graphic fills remaining space.
            VStack(spacing: 30) {
                graphic
                    .frame(idealHeight: 0, maxHeight: .infinity, alignment: .top)
                    .accessibilityHidden(true)
                
                content
            }
            
            // Text alone overflows: content scrolls, graphic is hidden.
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaBar(edge: .bottom, spacing: 20) {
            VStack(spacing: 10) {
                buttons
            }
            .bold()
            .tint(.altPrimary)
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .buttonSizing(.flexible)
            .padding(.horizontal, 34)
        }
        .transition(.push(from: .trailing))
    }
}

@available(iOS 26, *)
private struct PairingButton: View
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
        .tint(state == .paired ? .green : .altPrimary)
        .disabled(state == .waiting)
        .allowsHitTesting(state != .paired)
        .animation(.default, value: state)
    }
}

@available(iOS 26, *)
private struct RequirementRow: View
{
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: 16) {
            IconBadge(systemImage: systemImage, color: .altSecondary)

            VStack(alignment: .leading) {
                Text(title)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .opacity(0.8)
            }
        }
    }
}

// The Settings-style icon badge, at row size by default or larger as a step graphic.
@available(iOS 26, *)
private struct IconBadge: View
{
    let systemImage: String
    let color: Color
    
    @ScaledMetric
    private var size: CGFloat
    
    init(systemImage: String, color: Color, size: CGFloat = 34)
    {
        self.systemImage = systemImage
        self.color = color
        self._size = ScaledMetric(wrappedValue: size)
    }
    
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size / 2))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(color), in: RoundedRectangle(cornerRadius: size / 4))
    }
}

@available(iOS 26, *)
private struct PageControl: View
{
    let currentIndex: Int
    let count: Int
    
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.primary : Color(.systemFill))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue("Step \(currentIndex + 1) of \(count)")
    }
}

private extension Color
{
    static let altPrimary = Color(uiColor: .altPrimary)
    static let altSecondary = Color(red: 64/255, green: 165/255, blue: 155/255)
    static let altTertiary = Color(red: 129/255, green: 210/255, blue: 185/255)
}

@available(iOS 26, *)
extension RemoteAltServerSetupView
{
    static func makeViewController(completionHandler: @escaping () -> Void) async -> UIHostingController<some View>
    {
        let plan = await makePlan()
        
        let view = RemoteAltServerSetupView(plan: plan, completionHandler: completionHandler)
        
        let hostingController = UIHostingController(rootView: view)
        hostingController.isModalInPresentation = true
        return hostingController
    }
}

// MARK: - Previews

@available(iOS 26, *)
private struct SetupPreview: View
{
    let plan: [RemoteAltServerSetupView.Step]
    
    var body: some View {
        Color(uiColor: .altPrimary)
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                RemoteAltServerSetupView(plan: plan) { }
//                .environment(\.dynamicTypeSize, .accessibility3)
            }
    }
}

#Preview("Computer Pairing") {
    if #available(iOS 26, *) {
        SetupPreview(plan: [.welcome, .pairWithComputer, .installVPN, .finish])
    }
}

#Preview("On-Device Pairing") {
    if #available(iOS 26, *) {
        SetupPreview(plan: [.welcome, .pairOnDevice, .installVPN, .finish])
    }
}

#Preview("Bundled File") {
    if #available(iOS 26, *) {
        SetupPreview(plan: [.welcome, .installVPN, .finish])
    }
}

#Preview("Bundled File + VPN") {
    if #available(iOS 26, *) {
        SetupPreview(plan: [.welcome, .finish])
    }
}
