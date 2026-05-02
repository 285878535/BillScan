import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("隐私政策")
                    .font(.system(size: 24, weight: .bold))
                    .padding(.bottom, 10)
                
                Text("更新日期：2026年4月29日")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                
                Group {
                    PolicySection(title: "1. 信息收集", content: "我们仅收集为您提供服务所必需的信息。BillScan 是一款本地优先的应用，您的票据图片和识别结果默认存储在您的设备本地以及您的个人 iCloud 云端（如果您开启了同步功能）。我们不会将您的原始图片上传到我们的私有服务器进行持久化存储。")
                    
                    PolicySection(title: "2. 信息使用", content: "收集的信息主要用于 OCR 识别、分类管理以及生成统计报表。我们不会将您的个人信息出售或共享给第三方广告商。")
                    
                    PolicySection(title: "3. 数据安全", content: "我们采用业界标准的加密技术保护您的数据。由于应用支持 iCloud 同步，您的数据安全也受 Apple iCloud 安全协议的保护。")
                    
                    PolicySection(title: "4. 您的权利", content: "您可以随时在应用内删除任何票据数据。如果您删除应用并清空 iCloud 数据，我们将不再保留您的任何信息。")
                }
                
                Spacer(minLength: 40)
            }
            .padding(24)
        }
        .background(AppTheme.bgPrimary)
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PolicySection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            
            Text(content)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textSecondary)
                .lineSpacing(4)
        }
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("服务协议")
                    .font(.system(size: 24, weight: .bold))
                    .padding(.bottom, 10)
                
                Text("更新日期：2026年4月29日")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                
                Group {
                    PolicySection(title: "1. 服务说明", content: "BillScan 为您提供票据扫描、文字识别、分类管理等功能。部分高级功能需要订阅 Pro 会员方可使用。")
                    
                    PolicySection(title: "2. 订阅服务", content: "订阅费用将在确认购买时从您的 iTunes 账户扣除。订阅会自动续期，除非在当前期限结束前至少 24 小时关闭自动续费。")
                    
                    PolicySection(title: "3. 用户守则", content: "用户不得利用本软件从事违法违规活动，不得上传包含色情、暴力、侵权等违规内容。")
                    
                    PolicySection(title: "4. 免责声明", content: "OCR 识别结果受图片质量影响，可能存在误差，请在使用时核对关键信息。我们不对因识别错误导致的任何财务损失负责。")
                }
                
                Spacer(minLength: 40)
            }
            .padding(24)
        }
        .background(AppTheme.bgPrimary)
        .navigationTitle("服务协议")
        .navigationBarTitleDisplayMode(.inline)
    }
}
