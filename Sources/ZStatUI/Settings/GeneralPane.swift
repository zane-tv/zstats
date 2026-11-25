import SwiftUI
import AppKit
import ZStatKit

struct GeneralPane: View {
    let settings: SettingsStore

    /// `LoginItem.synchronize` reports a real failure — a missing bundle, a
    /// revoked approval — and the toggle is worthless if that is swallowed.
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Picker(L10n.tr("Language", "Ngôn ngữ"), selection: settings.binding(\.general.language)) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                Toggle(L10n.tr("Open ZStats at login", "Mở ZStats khi đăng nhập"),
                       isOn: settings.binding(\.general.launchAtLogin, onChange: applyLoginItem))
                if let loginItemError {
                    SettingsCaution(loginItemError)
                }
                Toggle(L10n.tr("Show icon in the Dock", "Hiện biểu tượng trên Dock"),
                       isOn: settings.binding(\.general.showsDockIcon, onChange: applyDockIcon))
            } header: {
                Text(L10n.tr("Startup", "Khởi động & Ngôn ngữ"))
            }

            Section {
                Picker(L10n.tr("Update interval", "Chu kỳ cập nhật"), selection: settings.binding(\.general.updateInterval)) {
                    ForEach(GeneralSettings.allowedIntervals, id: \.self) { interval in
                        Text(SettingsLabels.interval(interval)).tag(interval)
                    }
                }
                Toggle(L10n.tr("Slow down when the menu bar is hidden", "Giảm tần suất khi thanh Menu bị ẩn"),
                       isOn: settings.binding(\.general.throttlesWhenOccluded))
                Toggle(L10n.tr("Pause sampling on Low Power Mode", "Tạm dừng khi bật Chế độ nguồn điện thấp"),
                       isOn: settings.binding(\.general.pausesOnLowPower))
            } header: {
                Text(L10n.tr("Sampling", "Lấy mẫu"))
            }

            Section {
                Picker(L10n.tr("Temperature", "Nhiệt độ"), selection: settings.binding(\.general.temperatureUnit)) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                Picker(L10n.tr("Network rate", "Tốc độ mạng"), selection: settings.binding(\.general.networkRateUnit)) {
                    ForEach(NetworkRateUnit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                Picker(L10n.tr("Storage sizes", "Dung lượng lưu trữ"), selection: settings.binding(\.general.byteUnitStyle)) {
                    ForEach(ByteUnitStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                Toggle(L10n.tr("Show the percent sign", "Hiển thị dấu phần trăm (%)"), isOn: settings.binding(\.general.showsPercentSign))
            } header: {
                Text(L10n.tr("Units", "Đơn vị"))
            }

            Section {
                Toggle(L10n.tr("Look up my public IP address", "Tra cứu địa chỉ IP công khai"),
                       isOn: settings.binding(\.general.fetchesPublicIP))
            } header: {
                Text(L10n.tr("Privacy", "Quyền riêng tư"))
            } footer: {
                SettingsFootnote(L10n.tr(
                    "Left off, the Network module shows your local addresses only and ZStats contacts nothing.",
                    "Khi tắt, mục Mạng chỉ hiển thị IP nội bộ và ZStats không gửi bất kỳ yêu cầu mạng nào."))
            }
        }
        .settingsFormStyle()
    }

    // MARK: Side effects

    /// Process-level state rather than a stored preference, so the store's value alone
    /// would change nothing until the next launch.
    private func applyDockIcon(_ shows: Bool) {
        NSApp.setActivationPolicy(shows ? .regular : .accessory)
        // Switching policy drops key window status; take it back so the settings
        // window the user is standing in does not slide behind everything.
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyLoginItem(_ enabled: Bool) {
        if let error = LoginItem.synchronize(enabled: enabled) {
            loginItemError = L10n.tr(
                "macOS refused to \(enabled ? "register" : "remove") the login item: \(error.localizedDescription)",
                "macOS từ chối \(enabled ? "đăng ký" : "gỡ") mục khởi động cùng hệ thống: \(error.localizedDescription)")
            // The stored preference must not claim something the system rejected.
            settings.update { $0.general.launchAtLogin = LoginItem.isEnabled }
        } else {
            loginItemError = nil
        }
    }
}
