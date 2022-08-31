//
//  ProgressRing.swift
//  AltWidgetExtension
//
//  Created by Riley Testut on 8/17/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import SwiftUI
import WidgetKit

struct ProgressRing<Content: View>: View
{
    let progress: Double
    
    private let content: Content
    
    init(progress: Double, @ViewBuilder content: () -> Content)
    {
        self.progress = progress
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            ring(progress: 1.0)
                .opacity(0.3)
            
            ring(progress: self.progress)
            
            content
        }
    }
    
    @ViewBuilder
    private func ring(progress: Double) -> some View {
        let strokeStyle = StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round)
        
        Circle()
            .inset(by: 2.0)
            .trim(from: 0.0, to: progress)
            .rotation(Angle(degrees: -90), anchor: .center)
            .stroke(style: strokeStyle)
    }
}

struct ProgressRing_Previews: PreviewProvider {
    static var previews: some View {
        ProgressRing(progress: 0.5) {
            EmptyView()
        }
        .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
