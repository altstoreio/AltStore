//
//  Countdown.swift
//  AltWidgetExtension
//
//  Created by Riley Testut on 7/6/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import SwiftUI
import WidgetKit

struct Countdown: View
{
    let numberOfDays: Int?
    
    @Environment(\.font) var font
    
    @ViewBuilder
    private var overlay: some View {
        if let numberOfDays = self.numberOfDays, numberOfDays >= 10 {
            Capsule(style: .continuous)
                .stroke(lineWidth: 4.0)
        }
        else {
            Circle()
                .stroke(lineWidth: 4.0)
        }
    }
    
    var body: some View {
        Text("\(self.numberOfDays ?? 0)")
            .font((self.font ?? .title).monospacedDigit())
            .bold()
            .opacity(self.numberOfDays != nil ? 1 : 0)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(self.overlay)
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
