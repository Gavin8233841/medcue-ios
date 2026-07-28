import AuthenticationServices
import MedicationAdherenceCore
import OSLog
import QuickLook
import SwiftData
import SwiftUI
import UIKit

struct AccountBackupView: View {
    @AppStorage("appleAccountLocalUserID") private var appleAccountLocalUserID = ""
    @AppStorage("wantsICloudBackup") private var wantsICloudBackup = false
    @State private var statusMessage = ""

    private var hasAppleAccountMark: Bool {
        !appleAccountLocalUserID.isEmpty
    }

    private var hasICloudAccount: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("账号与备份", systemImage: "person.crop.circle")
                        .font(.headline)
                    Text("用药数据默认保存在本机。")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Apple 账号") {
                if hasAppleAccountMark {
                    SettingsStatusRow(
                        iconName: "checkmark.circle.fill",
                        tint: .green,
                        title: "已连接 Apple 账号",
                        subtitle: "账号标识仅保存在本机"
                    )
                    Button(role: .destructive) {
                        appleAccountLocalUserID = ""
                        statusMessage = "已断开本机 Apple 账号连接。"
                    } label: {
                        Text("断开 Apple 账号")
                    }
                } else {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = []
                    } onCompletion: { result in
                        handleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
                }

            }

            Section("备份") {
                SettingsStatusRow(
                    iconName: hasICloudAccount ? "icloud.fill" : "icloud.slash",
                    tint: hasICloudAccount ? .blue : .gray,
                    title: hasICloudAccount ? "已检测到 iCloud" : "未检测到 iCloud",
                    subtitle: hasICloudAccount ? "可用于 iCloud 备份准备" : "请先在系统设置中登录 iCloud"
                )
                SettingsToggleRow(title: "自动备份到 iCloud", isOn: $wantsICloudBackup)
            }

            Section("系统设置") {
                Button {
                    openSystemSettings()
                } label: {
                    Text("打开 App 系统设置")
                }
            }

            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("账号")
        .toolbar(.hidden, for: .tabBar)
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                appleAccountLocalUserID = credential.user
                statusMessage = "Apple 账号已连接。"
            } else {
                statusMessage = "未能读取 Apple 账号状态。"
            }
        case .failure:
            statusMessage = "Apple 账号连接未完成，请稍后重试或前往系统设置检查。"
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

