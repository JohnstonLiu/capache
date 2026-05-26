import WidgetKit

// WidgetKit push-token callbacks are only available in newer SDKs. Keep the
// widget extension buildable with older Xcodes used by CI and contributors.
#if compiler(>=6.3)
@available(iOSApplicationExtension 26.0, *)
struct CacheWidgetPushHandler: WidgetPushHandler {
    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        SharedStore.shared.recordWidgetPushToken(pushInfo.token)

        Task {
            await WidgetBackgroundRefreshClient.uploadPendingPushTokens()
        }
    }
}
#endif
