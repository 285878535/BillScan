import SwiftUI

// MARK: - Design Tokens
struct AppTheme {
    static let brandPrimary = Color(hex: "#FF9500") // 橙色主色调
    // 动态颜色，自动适配深浅模式
    static let bgPrimary = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#121212") : UIColor.white
    })
    static let bgSecondary = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#2A2A2A") : UIColor(hex: "#F5F5F5")
    })
    static let textPrimary = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor.white : UIColor(hex: "#111111")
    })
    static let textSecondary = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#BBBBBB") : UIColor(hex: "#666666")
    })
    static let textDisabled = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#666666") : UIColor(hex: "#BBBBBB")
    })
    static let divider = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(hex: "#333333") : UIColor(hex: "#EEEEEE")
    })
    
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 16
    static let radiusLg: CGFloat = 24
    static let radiusFull: CGFloat = 999
    
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
}

// MARK: - Hex Color Support
extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 1, 1, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

extension Color {
    init(hex: String) {
        self.init(UIColor(hex: hex))
    }
}

// MARK: - Shared Components
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isDisabled ? AppTheme.textDisabled : AppTheme.brandPrimary)
                .cornerRadius(AppTheme.radiusLg)
        }
        .disabled(isDisabled)
    }
}

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "搜索..."
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
                .font(.system(size: 16))
            TextField(placeholder, text: $text)
                .font(.system(size: 16))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.bgSecondary)
        .cornerRadius(12)
    }
}

struct CategoryItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let iconName: String?
}

struct CategoryPicker: View {
    let categories: [CategoryItem]
    @Binding var selected: String?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 全部
                Button(action: { selected = nil }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 12))
                        Text("全部")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selected == nil ? AppTheme.brandPrimary : AppTheme.bgPrimary)
                    .foregroundColor(selected == nil ? .white : AppTheme.textPrimary)
                    .cornerRadius(999)
                    .overlay(
                        RoundedRectangle(cornerRadius: 999)
                            .stroke(selected == nil ? Color.clear : AppTheme.divider, lineWidth: 1)
                    )
                }
                
                ForEach(categories) { cat in
                    Button(action: { selected = cat.name }) {
                        HStack(spacing: 6) {
                            if let icon = cat.iconName {
                                Image(systemName: icon)
                                    .font(.system(size: 12))
                            }
                            Text(cat.name)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selected == cat.name ? AppTheme.brandPrimary : AppTheme.bgPrimary)
                        .foregroundColor(selected == cat.name ? .white : AppTheme.textPrimary)
                        .cornerRadius(999)
                        .overlay(
                            RoundedRectangle(cornerRadius: 999)
                                .stroke(selected == cat.name ? Color.clear : AppTheme.divider, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            Text(title).font(.system(size: 20, weight: .bold))
            Spacer()
            if let actionTitle = actionTitle {
                Button(actionTitle) { action?() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.brandPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

extension View {
    func modernCardStyle() -> some View {
        self
            .background(AppTheme.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
    
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// ── 丝滑动画组件 ──

struct EnvelopeView: View {
    var isOpen: Bool
    
    var body: some View {
        ZStack {
            // 1. 底层：信封背面 (精致的纸质渐变)
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(
                    colors: [Color(hex: "#FFFFFF"), Color(hex: "#F0F2F5")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: .black.opacity(0.12), radius: 25, x: 0, y: 15)
            
            // 2. 内衬层：给信封增加深度感
            Rectangle()
                .fill(AppTheme.brandPrimary.opacity(0.05))
                .frame(height: 80)
                .offset(y: -40)
                .cornerRadius(12, corners: [.topLeft, .topRight])
            
            // 3. 前层主体 (带丝滑描边和微阴影)
            EnvelopeFrontShape()
                .fill(LinearGradient(
                    colors: [Color(hex: "#FDFDFD"), Color(hex: "#F8F9FA")],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(
                    EnvelopeFrontShape()
                        .stroke(Color.white, lineWidth: 1.5)
                        .blur(radius: 0.5)
                )
                .overlay(
                    EnvelopeFrontShape()
                        .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                )
            
            // 4. 封盖层 (带翻转动画和火漆印章)
            ZStack(alignment: .top) {
                EnvelopeFlapShape()
                    .fill(LinearGradient(
                        colors: [Color(hex: "#FFFFFF"), Color(hex: "#F2F4F7")],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .overlay(
                        EnvelopeFlapShape()
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
                
                // 精致的火漆印章 (Seal)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppTheme.brandPrimary, AppTheme.brandPrimary.opacity(0.8)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 20
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            .padding(4)
                    )
                    .shadow(color: AppTheme.brandPrimary.opacity(0.4), radius: 6, x: 0, y: 3)
                    .offset(y: 105) // 位置调整到封盖尖端
                    .opacity(isOpen ? 0 : 1)
                    .scaleEffect(isOpen ? 0.5 : 1.0)
            }
            .rotation3DEffect(
                .degrees(isOpen ? -170 : 0),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top
            )
        }
        .frame(width: 280, height: 190)
    }
}

struct EnvelopeFrontShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.75))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct EnvelopeFlapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.68))
        path.closeSubpath()
        return path
    }
}
