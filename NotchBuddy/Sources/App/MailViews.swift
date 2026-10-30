#if !APPSTORE
import SwiftUI
import AppKit

// MARK: - Mail card (Apple Mail pill)

/// Accent of the Mail pill (the catalog colour, before any colour the user picked).
private let mailAccent = "#2F8CFF"

/// The latest messages of every inbox in Apple Mail, newest first, unread ones highlighted.
/// A click on a message opens it in the card (sender, subject, text) with Open in Mail,
/// Reply (Mail's own reply window: nothing is sent from Coucou) and Mark as read.
struct MailCardView: View {
    @ObservedObject private var mail = MailController.shared
    @State private var openId: String? = nil
    @State private var searchOpen = false
    @FocusState private var searchFocused: Bool

    private var openMessage: MailMessage? {
        guard let openId else { return nil }
        return mail.displayed.first { $0.id == openId }
    }

    var body: some View {
        Group {
            if let message = openMessage {
                MailDetailView(message: message) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { openId = nil }
                }
                .transition(.opacity)
            } else {
                list
                    .transition(.opacity)
            }
        }
        .onAppear { mail.refreshIfStale() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: mailAccent))
                    .frame(width: 7, height: 7)
                Text(verbatim: "Mail")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("Inbox")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                if searchOpen {
                    // The search: free words, or "from:" / "subject:" (MailQuery).
                    TextField(String(localized: "mail.search.placeholder"), text: $mail.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#E8E9EC"))
                        .focused($searchFocused)
                        .onSubmit { mail.runSearch() }
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { searchOpen = false }
                        mail.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Close"))
                } else {
                    if let unread = mail.unreadCount, unread > 0 {
                        Text(String(format: String(localized: "%lld unread"), Int64(unread)))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: mailAccent))
                            .monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color(hex: mailAccent).opacity(0.14))
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 2)
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { searchOpen = true }
                        searchFocused = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "#8E939C"))
                            .frame(width: 18, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "mail.search.help"))
                }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Quick filters: All, Unread, Important, Today.
            HStack(spacing: 4) {
                ForEach(MailFilter.allCases, id: \.self) { f in
                    MailFilterChip(title: f.title, on: mail.filter == f) { mail.setFilter(f) }
                }
                if mail.searching {
                    Text("mail.searching")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .padding(.leading, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
            .padding(.leading, 108)
            .padding(.trailing, 12)

            // Message rows: three in view, the rest a scroll away.
            if mail.displayed.isEmpty {
                Group {
                    if mail.results != nil { Text("mail.no-results") }
                    else if mail.loaded { Text("No messages") } else { Text("Loading…") }
                }
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .padding(.top, 8)
                    .padding(.leading, 116)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(mail.displayed) { message in
                            MailRow(message: message) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    openId = message.id
                                }
                            }
                        }
                        if mail.results == nil && mail.messages.count >= mail.shownCount
                            && mail.shownCount < MailController.maxShown {
                            Button { mail.loadMore() } label: {
                                Text("mail.load-more")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color(hex: mailAccent).opacity(0.9))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 5)
                .padding(.leading, 108)
                .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}

/// One message in the list: sender, age, subject. Unread ones are tinted, with a dot.
private struct MailRow: View {
    let message: MailMessage
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        let accent = Color(hex: mailAccent)
        Button(action: onOpen) {
            HStack(spacing: 5) {
                Circle()
                    .fill(message.isRead ? Color.clear : accent)
                    .overlay(Circle().stroke(Color(hex: "#4D5159"), lineWidth: message.isRead ? 1 : 0))
                    .frame(width: 5, height: 5)
                Text(message.senderName)
                    .font(.system(size: 11, weight: message.isRead ? .regular : .semibold))
                    .foregroundColor(Color(hex: message.isRead ? "#9398A1" : "#E8E9EC"))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 82, alignment: .leading)
                    .layoutPriority(1)
                if message.isFlagged {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 7.5))
                        .foregroundColor(Color(hex: "#F5A524"))
                }
                Text(message.timeAgo)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .fixedSize()
                Text(message.subject)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: message.isRead ? "#4D5159" : "#8E939C"))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(message.isRead
                          ? Color.white.opacity(hovered ? 0.05 : 0)
                          : accent.opacity(hovered ? 0.14 : 0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// A quick filter of the Mail card: a small word, filled when it is on.
private struct MailFilterChip: View {
    let title: String
    let on: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9.5, weight: on ? .semibold : .regular))
                .foregroundColor(Color(hex: on ? "#E8E9EC" : (hovered ? "#B0B5BE" : "#6B7079")))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(on ? Color(hex: mailAccent).opacity(0.22) : Color.white.opacity(hovered ? 0.06 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

extension MailFilter {
    var title: String {
        switch self {
        case .all: return String(localized: "mail.filter.all")
        case .unread: return String(localized: "mail.filter.unread")
        case .flagged: return String(localized: "mail.filter.flagged")
        case .today: return String(localized: "mail.filter.today")
        }
    }
}

// MARK: - Mail detail

/// One message opened in the card: sender, subject, the start of its text, and actions.
struct MailDetailView: View {
    let message: MailMessage
    let onClose: () -> Void
    @ObservedObject private var mail = MailController.shared

    var body: some View {
        let accent = Color(hex: mailAccent)
        VStack(alignment: .leading, spacing: 4) {
            // Header: back, sender, age
            HStack(spacing: 6) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Circle()
                    .fill(message.isRead ? Color(hex: "#4D5159") : accent)
                    .frame(width: 6, height: 6)
                Text(message.senderName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(1)
                    .help(message.senderAddress)
                Spacer(minLength: 2)
                Text(message.timeAgo)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .fixedSize()
            }
            // The card's ↗ button sits in the top-right corner: keep the header clear of it
            // (36 pt from the edge, like every card header).
            .padding(.trailing, 24)

            Text(message.subject.isEmpty ? " " : message.subject)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#C5C8CD"))
                .lineLimit(1).truncationMode(.tail)

            // The start of the message, scrollable.
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if let text = mail.previews[message.id] {
                        Text(text.isEmpty ? " " : text)
                    } else {
                        Text("Loading…")
                    }
                }
                .font(.system(size: 10.5))
                .foregroundColor(Color(hex: "#9398A1"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(height: 28)

            // Actions: each one is the user's own click. Nothing is ever sent from here.
            HStack(spacing: 12) {
                Button("Open in Mail") { mail.openInMail(message) }
                    .foregroundColor(accent.opacity(0.9))
                Button("Reply") { mail.reply(message) }
                    .foregroundColor(Color(hex: "#C5C8CD"))
                if !message.isRead {
                    Button("Mark as read") { mail.markAsRead(message) }
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                Button(message.isFlagged ? String(localized: "mail.not-important") : String(localized: "mail.important")) {
                    mail.toggleFlag(message)
                }
                .foregroundColor(Color(hex: "#F5A524").opacity(0.9))
                Button(String(localized: "mail.junk")) {
                    mail.moveToJunk(message)
                    onClose()
                }
                .foregroundColor(Color(hex: "#8E939C"))
                Menu {
                    Button(String(localized: "mail.make-vip")) { mail.makeVIP(message) }
                    Button(String(localized: "mail.ignore-sender")) {
                        mail.ignoreSender(message)
                        onClose()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onAppear { mail.loadPreview(message) }
    }
}
#endif
