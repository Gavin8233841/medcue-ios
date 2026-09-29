import SwiftUI

struct AccountBackupView: View {
    var body: some View {
        List {
            Section("本机数据") {
                Label("用药数据保存在这台 iPhone", systemImage: "iphone")
                    .font(.headline)
                Text("当前版本没有 Apple 账号连接或自动 iCloud 备份。更换、抹掉或丢失设备前，请勿假定这些记录已备份或可以恢复。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("本机数据")
        .toolbar(.hidden, for: .tabBar)
    }
}
