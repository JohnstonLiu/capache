import WidgetKit

struct CacheWidgetPushHandler: WidgetPushHandler {
    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        SharedStore.shared.recordWidgetPushToken(pushInfo.token)

        Task {
            await WidgetBackgroundRefreshClient.uploadPendingPushTokens()
        }
    }
}
