//
//  NetWorthTimelineProvider.swift
//  Menej
//
//  Refreshes on data change, not on a timer — see PRD §6 F9.
//
//  NOTE: see NetWorthWidgetView.swift — this needs to move into a real
//  Widget Extension target before it can run as an actual widget. In that
//  target, `getSnapshot`/`getTimeline` should read from an App Group
//  container shared with the main app, and the app should call
//  `WidgetCenter.shared.reloadTimelines(ofKind:)` whenever net worth changes.
//  TODO(M5).
//

import WidgetKit

struct NetWorthTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NetWorthWidgetEntry {
        NetWorthWidgetEntry(date: .now, netWorth: 0, deltaSinceLastMonth: 0, isPrivacyModeEnabled: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (NetWorthWidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NetWorthWidgetEntry>) -> Void) {
        let entry = placeholder(in: context)
        completion(Timeline(entries: [entry], policy: .never))
    }
}
