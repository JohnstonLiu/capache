//
//  cacheWidgetLiveActivity.swift
//  cacheWidget
//
//  Created by Johnston Liu on 2025-12-28.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct cacheWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct cacheWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: cacheWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension cacheWidgetAttributes {
    fileprivate static var preview: cacheWidgetAttributes {
        cacheWidgetAttributes(name: "World")
    }
}

extension cacheWidgetAttributes.ContentState {
    fileprivate static var smiley: cacheWidgetAttributes.ContentState {
        cacheWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: cacheWidgetAttributes.ContentState {
         cacheWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: cacheWidgetAttributes.preview) {
   cacheWidgetLiveActivity()
} contentStates: {
    cacheWidgetAttributes.ContentState.smiley
    cacheWidgetAttributes.ContentState.starEyes
}
