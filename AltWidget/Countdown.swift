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
    let startDate: Date?
    let endDate: Date?
    
    @Environment(\.font) private var font
    
    private var numberOfDays: Int {
        guard let date = self.endDate else { return 0 }
        
        let numberOfDays = date.numberOfCalendarDays(since: Date())
        return numberOfDays
    }
    
    private var fractionComplete: CGFloat {
        guard let startDate = self.startDate, let endDate = self.endDate else { return 1.0 }
        
        let totalNumberOfDays = endDate.numberOfCalendarDays(since: startDate)
        let fractionComplete = CGFloat(self.numberOfDays) / CGFloat(totalNumberOfDays)
        return fractionComplete
    }
        
    @ViewBuilder
    private func overlay(progress: CGFloat) -> some View
    {
        let strokeStyle = StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round)
        
        if self.numberOfDays > 9 || self.numberOfDays < 0 {
            Capsule(style: .continuous)
                .trim(from: 0.0, to: progress)
                .stroke(style: strokeStyle)
        }
        else {
            Circle()
                .trim(from: 0.0, to: progress)
                .rotation(Angle(degrees: -90), anchor: .center)
                .stroke(style: strokeStyle)
        }
    }
    
    var body: some View {
        Text("\(numberOfDays)")
            .font((font ?? .title).monospacedDigit())
            .bold()
            .opacity(endDate != nil ? 1 : 0)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(
                ZStack {
                    overlay(progress: 1.0)
                        .opacity(0.3)
                    
                    overlay(progress: fractionComplete)
                }
            )
    }
}

struct Countdown_Previews: PreviewProvider {
    static var previews: some View {
        let startDate = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        Group {
            Countdown(startDate: startDate, endDate: Calendar.current.date(byAdding: .day, value: 7, to: startDate))
            Countdown(startDate: startDate, endDate: Calendar.current.date(byAdding: .day, value: 365, to: startDate))
        }
        .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
