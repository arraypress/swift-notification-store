# swift-notification-store

A Mac's waiting notifications, read-only: what Notification Center still holds — the app, the sender, the text, where it may appear — read from the store macOS keeps for it. No Apple framework is linked; the store is read from a private copy and never opened in place.

```swift
import NotificationStore

let store = NotificationStore()
for n in try store.notifications() where n.sender == .person {
    print(n.date, n.app, n.title ?? "", n.body ?? "")
}
let waiting = NotificationFilter(since: Date().addingTimeInterval(-7_200), excludedApps: ["com.example.bank"])
    .apply(try store.notifications())
```

## Where it is, and what it is (measured on macOS 27.0.1)

`~/Library/Group Containers/group.com.apple.usernoted/db2/db` — usernoted holds it open, so it is the live store. Behind **Full Disk Access**.

- **It is not a history.** A notification's row appears within seconds of delivery; **clearing it deletes the row**; and **messaging apps withdraw their own** once the chat is read (a Messages notification vanished, badge back to 0, when its chat was opened — without touching the notification). Untouched notifications stay for days. So what is here is what is still unhandled.
- `record.data` is a binary property list: `{app, date, req: {titl, subt, body, cate, thre, iden, dest, …}, resp: {act, for}, …}`. Messages puts the sender in `titl` and the text in `body`, with a conversation `thre`.
- `dest` is a bitmask named by Apple's own `UNNotificationDestinationStrings()`: 1 Alert, 2 Lock Screen, 4 Notification Center, 8 CarPlay.
- `delivered` lists, per app, the raw 16-byte ids of what is delivered now; `app` carries each app's badge, with identifiers lower-cased.
- Oddity: rows two days old stayed listed as delivered (to Notification Center) while Notification Center showed nothing — cause unknown, so "delivered" means macOS still holds it, not that it is on screen.

## Who sent it

`SenderKinds` sorts notifications into **person** (messaging, mail and calling apps — and only when the notification names a sender or a conversation: WhatsApp's own "Download completed" notices carry neither and count as the app), **system** (`_system_center_:` senders and Apple's notification-only services) and **app**.

## What it offers

- `NotificationStore` — `notifications()` (newest first, with whether each is still delivered) and `apps()` (every app allowed to notify, its badge, how many it holds).
- `NotificationFilter` — since, sender kinds, apps, excluded apps, and search (word starts; case and accents ignored).
- `NotificationQueries.byApp` — counts, newest and oldest per app.

## Requirements

macOS 14 or later. Swift 6.2. One dependency: [swift-sqlite-reader](https://github.com/arraypress/swift-sqlite-reader), which makes the private copy and reads it.

## Licence

MIT.
