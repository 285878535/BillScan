import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Image("AppIcon") // Assuming there's an app icon
                        .resizable()
                        .frame(width: 100, height: 100)
                        .cornerRadius(24)
                        .modernCardStyle()
                    
                    VStack(spacing: 4) {
                        Text("BillScan")
                            .font(.system(size: 24, weight: .bold))
                        
                        Text("版本 1.0.0 (Build 1)")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .padding(.top, 40)
                
                VStack(alignment: .leading, spacing: 20) {
                    Text("BillScan 是一款简洁高效的票据管理工具。通过先进的 OCR 技术，帮助您快速识别、分类并归档各类消费凭证，让财务管理变得轻而易举。")
                        .font(.system(size: 16))
                        .lineSpacing(6)
                        .foregroundColor(AppTheme.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(title: "官方网站", value: "www.billscan.app")
                        InfoRow(title: "联系我们", value: "support@billscan.app")
                        InfoRow(title: "官方小红书", value: "@BillScan 助手")
                    }
                }
                .padding(24)
                .modernCardStyle()
                .padding(.horizontal, 16)
                
                Text("© 2026 BillScan Team. All rights reserved.")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textDisabled)
                    .padding(.bottom, 20)
            }
        }
        .background(AppTheme.bgSecondary)
        .navigationTitle("关于 BillScan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .foregroundColor(AppTheme.textPrimary)
                .fontWeight(.medium)
        }
        .font(.system(size: 15))
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
