//
//  SunMath.swift
//  weather wallpaper tool
//
//  Created by 楊舒瑋 on 2026/6/29.
//

import Foundation
import simd // 引入 Apple 的向量與矩陣運算庫

struct SunMath {
    /// 根據給定時間與經緯度，計算太陽在 3D 空間中的方向向量
    /// - Parameters:
    ///   - date: 當下時間 (UTC 或本地時間皆可，透過 Calendar 處理)
    ///   - latitude: 緯度 (以台中大里為例，約為 24.1 度)
    ///   - longitude: 經度 (以台中大里為例，約為 120.68 度)
    /// - Returns: 指向太陽的三維單位向量 (x: 東方, y: 天頂, z: 南方)
    static func getSunVector(date: Date, latitude: Double, longitude: Double) -> SIMD3<Float> {
        
        // --- 修正區域開始 ---
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(abbreviation: "UTC")! // 強制使用絕對時間
        
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        
        // 這裡抓出來的會是標準的 UTC 小時
        let hour = Double(calendar.component(.hour, from: date))
        let minute = Double(calendar.component(.minute, from: date))
        let second = Double(calendar.component(.second, from: date))
        let utcTimeInHours = hour + minute / 60.0 + second / 3600.0
        // --- 修正區域結束 ---
        
        // 1. 估算太陽赤緯
        let fractionalYear = (2.0 * .pi / 365.24) * (dayOfYear - 1.0 + (utcTimeInHours - 12.0) / 24.0)
        let declination = 0.006918
                        - 0.399912 * cos(fractionalYear)
                        + 0.070257 * sin(fractionalYear)
                        - 0.006758 * cos(2 * fractionalYear)
                        + 0.000907 * sin(2 * fractionalYear)
        
        // 2. 估算真太陽時與時角 (把原本的 localTimeInHours 改成 utcTimeInHours)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(fractionalYear) - 0.032077 * sin(fractionalYear) - 0.014615 * cos(2 * fractionalYear) - 0.040849 * sin(2 * fractionalYear))
        let trueSolarTime = (utcTimeInHours * 60.0 + eqTime + 4.0 * longitude).truncatingRemainder(dividingBy: 1440.0) / 60.0
        let hourAngle = (trueSolarTime - 12.0) * 15.0 * (.pi / 180.0)
        
        let latRad = latitude * .pi / 180.0
        
        // 3. 球面三角學：計算高度角
        let sinAltitude = sin(latRad) * sin(declination) + cos(latRad) * cos(declination) * cos(hourAngle)
        let altitude = asin(sinAltitude)
        
        // 4. 球面三角學：計算方位角
        let cosAzimuth = (sin(declination) - sin(latRad) * sinAltitude) / (cos(latRad) * cos(altitude))
        var azimuth = acos(max(-1.0, min(1.0, cosAzimuth)))
        if hourAngle > 0 {
            azimuth = 2.0 * .pi - azimuth
        }
        
        // 5. 轉換為 3D 向量
        let x = Float(cos(altitude) * sin(azimuth))
        let y = Float(sin(altitude))
        let z = Float(cos(altitude) * cos(azimuth))
        
        return simd_normalize(SIMD3<Float>(x, y, z))
    }
}
