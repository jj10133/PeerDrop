// Add this extension to post a notification when a transfer completes
// so ReceivedFilesView can auto-refresh.

import Foundation

extension Notification.Name {
    static let transferDidComplete = Notification.Name("PeerDropTransferDidComplete")
}