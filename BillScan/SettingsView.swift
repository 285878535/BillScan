import SwiftUI
import SwiftData

struct SettingsView: View {
    @Binding var showTabBar: Bool
    @AppStorage("isPremium") private var isPremium = false
    @AppStorage("isCloudSyncEnabled") private var isCloudSyncEnabled = true
    
    @State private var showProView = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingLG) {
                    // Membership Card
                    Button(action: {
                        showProView = true
                    }) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(isPremium ? Color.yellow.opacity(0.2) : Color.gray.opacity(0.1))
                                    .frame(width: 48, height: 48)
                                
                                Image(systemName: isPremium ? "crown.fill" : "crown")
                                    .font(.system(size: 24))
                                    .foregroundColor(isPremium ? .yellow : .gray)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(isPremium ? "Pro 会员" : "免费版用户")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppTheme.textPrimary)
                                
                                Text(isPremium ? "尊享所有高级功能" : "开通会员解锁全部功能")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            
                            Spacer()
                            
                            if !isPremium {
                                Text("立即开通")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(AppTheme.brandPrimary)
                                    .cornerRadius(AppTheme.radiusFull)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppTheme.textDisabled)
                            }
                        }
                        .padding(AppTheme.spacingMD)
                        .modernCardStyle()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 16)
                    
                    // Receipt Management Section
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: "票据管理")
                        
                        VStack(spacing: 0) {
                            NavigationLink(destination: CategoryManagementView()) {
                                SettingRow(icon: "tag.fill", iconColor: .purple, title: "分类管理")
                            }
                            
                            Divider().padding(.leading, 56)
                            
                            NavigationLink(destination: OfflineModelView()) {
                                SettingRow(icon: "sparkles.rectangle.stack.fill", iconColor: .blue, title: "云模型")
                            }
                        }
                        .modernCardStyle()
                        .padding(.horizontal, 16)
                    }

                    // iCloud Sync Section
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: "数据同步")
                        
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "icloud.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                
                                Text("iCloud 同步")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppTheme.textPrimary)
                                
                                Spacer()
                                
                                Toggle("", isOn: $isCloudSyncEnabled)
                                    .tint(AppTheme.brandPrimary)
                            }
                            .padding(AppTheme.spacingMD)
                            
                            Divider()
                                .padding(.leading, 56)
                            
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.gray)
                                    .frame(width: 24)
                                
                                Text("最后同步时间")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppTheme.textPrimary)
                                
                                Spacer()
                                
                                Text("刚刚")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            .padding(AppTheme.spacingMD)
                        }
                        .modernCardStyle()
                        .padding(.horizontal, 16)
                    }
                    
                    // Other Settings
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: "其他")
                        
                        VStack(spacing: 0) {
                            NavigationLink(destination: PrivacyPolicyView()) {
                                SettingRow(icon: "shield.fill", iconColor: .green, title: "隐私政策")
                            }
                            Divider().padding(.leading, 56)
                            
                            NavigationLink(destination: TermsOfServiceView()) {
                                SettingRow(icon: "doc.text.fill", iconColor: .orange, title: "服务协议")
                            }
                            Divider().padding(.leading, 56)
                            
                            NavigationLink(destination: AboutView()) {
                                SettingRow(icon: "info.circle.fill", iconColor: .blue, title: "关于 BillScan")
                            }
                        }
                        .modernCardStyle()
                        .padding(.horizontal, 16)
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding(.vertical, AppTheme.spacingLG)
            }
            .background(AppTheme.bgSecondary)
            .navigationTitle("我的")
            .sheet(isPresented: $showProView) {
                ProSubscriptionView()
            }
        }
    }
}

struct SettingRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var value: String? = nil
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.system(size: 18))
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(AppTheme.textPrimary)
            
            Spacer()
            
            if let value = value {
                Text(value)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.trailing, 4)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textDisabled)
        }
        .padding(AppTheme.spacingMD)
        .contentShape(Rectangle()) // 使整个区域可点击
    }
}

struct CategoryManagementView: View {
    @Query(sort: \Category.createdAt) private var categories: [Category]
    @Environment(\.modelContext) private var modelContext
    @State private var showAddSheet = false

    var body: some View {
        List {
            if categories.isEmpty {
                Section {
                    Text("暂无自定义分类，系统将使用默认分类。")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(categories) { category in
                        NavigationLink(destination: CategoryEditView(category: category)) {
                            HStack(spacing: 12) {
                                Image(systemName: category.iconName)
                                    .foregroundColor(AppTheme.brandPrimary)
                                    .frame(width: 30, height: 30)
                                    .background(AppTheme.brandPrimary.opacity(0.1))
                                    .cornerRadius(8)
                                
                                Text(category.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: deleteCategories)
                } header: {
                    Text("自定义分类")
                } footer: {
                    Text("左滑可删除分类。删除分类不会删除已归类的票据。")
                }
            }
        }
        .navigationTitle("分类管理")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                CategoryEditView(category: nil)
            }
        }
    }

    private func deleteCategories(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(categories[index])
        }
    }
}

struct CategoryEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var category: Category?
    @State private var name: String = ""
    @State private var selectedIcon: String = "folder"
    
    let iconCategories: [(name: String, icons: [String])] = [
        ("购物", ["cart", "bag", "creditcard", "tag", "barcode", "gift", "house", "tag.fill", "square.and.arrow.down", "briefcase", "archivebox"]),
        ("餐饮", ["fork.knife", "cup.and.saucer", "wineglass", "carrot", "mouth", "fish", "popcorn", "heart", "leaf", "drop"]),
        ("交通", ["bus", "car", "airplane", "tram", "bicycle", "fuelpump", "map", "globe", "sailboat", "ferry", "tram.fill"]),
        ("医疗", ["medical.thermometer", "stethoscope", "pill", "heart.fill", "cross.case", "bandage", "brain", "lungs", "eye", "face.smiling"]),
        ("居家", ["house", "paintbrush", "bed.double", "lightbulb", "shower", "hammer", "wrench", "wind", "tv", "speaker.wave.2"]),
        ("财务", ["dollarsign.circle", "yensign.circle", "eurosign.circle", "banknote", "chart.bar", "creditcard.fill", "house.fill", "percent", "chart.pie"]),
        ("办公", ["briefcase", "paperclip", "printer", "laptopcomputer", "desktopcomputer", "tray.full", "calendar", "archivebox", "pencil", "doc.text"]),
        ("娱乐", ["gamecontroller", "tv", "music.note", "theatermasks", "ticket", "camera", "film", "headphones", "guitars", "video"]),
        ("教育", ["book", "graduationcap", "pencil", "bag", "paperplane", "doc.text", "ruler", "books.vertical", "text.book.closed"]),
        ("生活", ["star", "person", "bell", "gear", "scissors", "key", "flashlight.on.fill", "umbrella", "magnifyingglass", "hourglass"]),
        ("运动", ["soccerball", "basketball", "tennisball", "sportscourt", "flag", "flame", "trophy", "medal", "stopwatch"]),
        ("自然", ["leaf", "sun.max", "moon", "cloud", "cloud.rain", "snowflake", "wind", "drop", "flame", "tree", "mountain.2", "pawprint"])
    ]

    init(category: Category?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _selectedIcon = State(initialValue: category?.iconName ?? "folder")
    }

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("分类名称", text: $name)
                    .autocorrectionDisabled()
            }
            
            ForEach(iconCategories, id: \.name) { group in
                Section(group.name) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(group.icons, id: \.self) { icon in
                            ZStack {
                                Circle()
                                    .fill(selectedIcon == icon ? AppTheme.brandPrimary : AppTheme.bgSecondary)
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: icon)
                                    .font(.system(size: 18))
                                    .foregroundColor(selectedIcon == icon ? .white : AppTheme.textPrimary)
                            }
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedIcon = icon
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle(category == nil ? "新增分类" : "编辑分类")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    save()
                    dismiss()
                }
                .disabled(name.isEmpty)
                .fontWeight(.bold)
            }
        }
    }

    private func save() {
        if let category = category {
            category.name = name
            category.iconName = selectedIcon
        } else {
            let newCat = Category(name: name, iconName: selectedIcon)
            modelContext.insert(newCat)
        }
    }
}

#Preview {
    SettingsView(showTabBar: .constant(true))
}
