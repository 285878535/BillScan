import SwiftUI

struct HealthStyle {
    static let sage = Color(hex: "718F78")
    static let ink = Color(hex: "1D2522")
    static let muted = Color(hex: "7D837F")
    static let background = Color(hex: "F6F7F8")
    static let pale = Color(hex: "EBF2EC")
}

struct HealthPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

extension View {
    func healthCard() -> some View {
        self.padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.black.opacity(0.035)))
            .shadow(color: .black.opacity(0.025), radius: 12, y: 5)
    }
    func healthError(_ error: Binding<String?>) -> some View {
        alert("未能完成操作", isPresented: Binding(get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } })) {
            Button("好", role: .cancel) { error.wrappedValue = nil }
        } message: { Text(error.wrappedValue ?? "") }
    }
}

struct HealthAction: View {
    var title: String
    var icon: String = "plus"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 17)
                .foregroundStyle(.white)
                .background(HealthStyle.sage, in: RoundedRectangle(cornerRadius: 23))
        }.buttonStyle(HealthPressStyle())
    }
}

struct HealthBadge: View {
    var text: String
    var warning = false
    var body: some View {
        Text(text).font(.system(size: 12, weight: .medium))
            .foregroundStyle(warning ? Color.brown : HealthStyle.sage)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(warning ? Color.orange.opacity(0.10) : HealthStyle.pale, in: Capsule())
    }
}

struct DocumentThumbnail: View {
    var document: HealthDocument
    var width: CGFloat = 54
    var body: some View {
        Group {
            if let data = document.images.first, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(hex: "F3F4F6")
                    VStack(spacing: 5) {
                        Image(systemName: document.kind == .record ? "doc.text" : "list.bullet.clipboard")
                            .font(.system(size: 23, weight: .light)).foregroundStyle(HealthStyle.muted)
                        Text(document.kind.rawValue).font(.system(size: 8)).foregroundStyle(HealthStyle.muted)
                    }
                }
            }
        }
        .frame(width: width, height: width * 1.35).clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.black.opacity(0.04)))
        .accessibilityHidden(true)
    }
}

/// Uses the system's continuous card zoom where supported; iOS 17 retains native push navigation.
struct HealthNavigationSource: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *), !reduceMotion {
            content.matchedTransitionSource(id: id, in: namespace)
        } else { content }
    }
}

struct HealthNavigationDestination: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *), !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else { content }
    }
}

struct HealthDate {
    static func short(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day())
    }
    static func section(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day().weekday(.wide))
    }
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
