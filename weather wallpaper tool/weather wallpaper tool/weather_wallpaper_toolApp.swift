//
//  weather_wallpaper_toolApp.swift
//  weather wallpaper tool
//
//  Created by 楊舒瑋 on 2026/6/29.
//

import SwiftUI
import AppKit

@main
struct YourAppNameApp: App {
    // 透過 NSApplicationDelegate 來監控應用程式生命週期
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 抓取第一個視窗
        if let window = NSApplication.shared.windows.first {
            
            // 1. 去除標題列與邊框，設定為無邊框樣式
            window.styleMask = [.borderless]
            
            // 2. 將視窗層級設定為桌面層級 (Desktop Window Level)
            // 這會讓它永遠停留在桌面圖示的後面，但會在桌布的前面
            window.level = .init(Int(CGWindowLevelForKey(.desktopIconWindow)))
            
            // 3. 設定為背景透明，這對於之後顯示 Metal 渲染的天空至關重要
            window.isOpaque = false
            window.backgroundColor = .clear
            
            // 4. 讓滑鼠點擊穿透視窗
            window.ignoresMouseEvents = true
            
            // 5. 確保視窗填滿整個螢幕
            window.setFrame(NSScreen.main?.frame ?? .zero, display: true)
        }
    }
}
