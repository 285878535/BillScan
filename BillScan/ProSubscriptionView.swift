import SwiftUI

struct ProSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isPremium") private var isPremium = false
    @State private var selectedPlan: Int = 1 // 0: Monthly, 1: Yearly, 2: Lifetime
    
    let plans = [
        SubscriptionPlan(title: "按月订阅", price: "¥12.00", period: "/月", description: "每月自动续期，随时取消"),
        SubscriptionPlan(title: "按年订阅", price: "¥88.00", period: "/年", description: "首年特惠，低至 7.33 元/月", isRecommended: true),
        SubscriptionPlan(title: "终身买断", price: "¥198.00", period: "", description: "一次购买，终身享有所有功能")
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: "#FFD700"), Color(hex: "#FF9500")], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                            .shadow(color: Color(hex: "#FF9500").opacity(0.3), radius: 10, x: 0, y: 5)
                        
                        Image(systemName: "crown.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 8) {
                        Text("开通 BillScan Pro")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Text("解锁全部高级功能，提升财务管理效率")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 40)
                
                // Features Grid
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(icon: "infinite", color: .blue, title: "无限次数扫描", subtitle: "突破每日扫描限制，随心记录")
                    FeatureRow(icon: "icloud.fill", color: .cyan, title: "iCloud 云端同步", subtitle: "多设备数据实时同步，安全无忧")
                    FeatureRow(icon: "doc.text.fill", color: .orange, title: "高清 PDF 导出", subtitle: "支持单张或批量导出，方便报销")
                    FeatureRow(icon: "sparkles", color: .purple, title: "AI 智能分类", subtitle: "自动识别消费类型，生成专业报表")
                    FeatureRow(icon: "lock.shield.fill", color: .green, title: "隐私应用锁", subtitle: "面容 ID/密码保护，隐私更安全")
                }
                .padding(.horizontal, 24)
                
                // Subscription Plans
                VStack(spacing: 16) {
                    ForEach(0..<plans.count, id: \.self) { index in
                        PlanCard(plan: plans[index], isSelected: selectedPlan == index)
                            .onTapGesture {
                                withAnimation(.spring()) {
                                    selectedPlan = index
                                }
                            }
                    }
                }
                .padding(.horizontal, 20)
                
                // Action Buttons
                VStack(spacing: 16) {
                    Button(action: {
                        isPremium = true
                        dismiss()
                    }) {
                        Text(isPremium ? "已开通" : "立即订阅")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isPremium ? AppTheme.textDisabled : AppTheme.brandPrimary)
                            .cornerRadius(AppTheme.radiusLg)
                            .shadow(color: AppTheme.brandPrimary.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .disabled(isPremium)
                    
                    HStack(spacing: 24) {
                        Button("恢复购买") {
                            // Restore logic
                        }
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                        
                        Text("|")
                            .foregroundColor(AppTheme.divider)
                        
                        Link("服务协议", destination: URL(string: "https://example.com/terms")!)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        Text("|")
                            .foregroundColor(AppTheme.divider)
                        
                        Link("隐私政策", destination: URL(string: "https://example.com/privacy")!)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .background(AppTheme.bgSecondary)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
        }
    }
}

struct SubscriptionPlan {
    let title: String
    let price: String
    let period: String
    let description: String
    var isRecommended: Bool = false
}

struct PlanCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(plan.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    if plan.isRecommended {
                        Text("最实惠")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
                
                Text(plan.description)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()
            
            HStack(alignment: .bottom, spacing: 2) {
                Text(plan.price)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.brandPrimary)
                
                Text(plan.period)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.bottom, 2)
            }
        }
        .padding(20)
        .background(AppTheme.bgPrimary)
        .cornerRadius(AppTheme.radiusMd)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                .stroke(isSelected ? AppTheme.brandPrimary : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(isSelected ? 0.1 : 0.03), radius: 10, x: 0, y: 5)
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProSubscriptionView()
    }
}
