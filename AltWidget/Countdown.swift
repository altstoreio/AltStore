//
//  Countdown.swift
//  AltWidgetExtension
//
//  Created by Riley Testut on 7/6/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import SwiftUI
import WidgetKit

extension Color
{
    static let countdownLightGreen = Color(red: 139 / 255, green: 245 / 255, blue: 134 / 255)
    static let countdownDarkGreen = Color(red: 96 / 255, green: 197 / 255, blue: 81 / 255)
}

struct Countdown: View {
    
    var numberOfDays: Int
    
    @Environment(\.font) var font
    
    @ViewBuilder
    private var overlay: some View {
        if self.numberOfDays >= 10 {
            Capsule(style: .continuous)
                .stroke(lineWidth: 4.0)
        }
        else {
            Circle()
                .stroke(lineWidth: 4.0)
        }
    }
    
    var body: some View {
        // Badge should be 40% transparent, white
        let gradient = LinearGradient(gradient: Gradient(colors: [
                                                            Color(white: 1.0, opacity: 0.8), Color(white: 1.0, opacity: 0.8)
        ]),
                                      startPoint: .top,
                                      endPoint: .bottom)
        
        let body = Text("\(self.numberOfDays)")
            .font((self.font ?? .title).monospacedDigit())
            .bold()
            .opacity(1.0)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(self.overlay)

        return body
            .opacity(0.0)
            .padding(.all, 3)
            .overlay(
                gradient.mask(
                    body
                        .scaledToFill()
                )
            )
    }
}

struct Countdown_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            Countdown(numberOfDays: 7)
            Countdown(numberOfDays: 365)
        }
        .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
