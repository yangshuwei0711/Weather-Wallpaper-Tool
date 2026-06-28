//
//  MoonMath.swift
//  weather wallpaper tool
//
//  Created by 楊舒瑋 on 2026/6/29.
//

import Foundation
import simd

struct MoonMath {
    /// 根據給定時間與經緯度，計算月球在 3D 空間中的方向向量
    static func getMoonVector(date: Date, latitude: Double, longitude: Double) -> SIMD3<Float> {
        
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(abbreviation: "UTC")!
        
        // 1. 計算自 J2000.0 (2000年1月1日 12:00 UTC) 以來的日數 (Julian Days since J2000)
        let j2000Date = Date(timeIntervalSince1970: 946728000)
        let daysSinceJ2000 = date.timeIntervalSince(j2000Date) / 86400.0
        
        // 2. 月球軌道參數 (Jean Meeus 近似法)
        // L: 月球平黃經 (Mean Longitude)
        let L = (218.316 + 13.176396 * daysSinceJ2000).truncatingRemainder(dividingBy: 360.0)
        // M: 月球平近點角 (Mean Anomaly)
        let M = (134.963 + 13.064993 * daysSinceJ2000).truncatingRemainder(dividingBy: 360.0)
        // F: 月球距交點平距離 (Mean distance from ascending node)
        let F = (93.272 + 13.229350 * daysSinceJ2000).truncatingRemainder(dividingBy: 360.0)
        
        let deg2rad = Double.pi / 180.0
        
        // 3. 計算黃經 (Ecliptic Longitude) 與 黃緯 (Ecliptic Latitude)
        // 加入最大的微擾項 (出差, 中心差等) 來修正位置
        let eclipticLongitude = L + 6.289 * sin(M * deg2rad)
        let eclipticLatitude = 5.128 * sin(F * deg2rad)
        
        let lambda = eclipticLongitude * deg2rad
        let beta = eclipticLatitude * deg2rad
        
        // 4. 黃道座標轉換為赤道座標 (Equatorial Coordinates)
        // 地球黃赤交角約為 23.439 度
        let obliquity = 23.439 * deg2rad
        
        let sinDeclination = sin(beta) * cos(obliquity) + cos(beta) * sin(obliquity) * sin(lambda)
        let declination = asin(sinDeclination) // 赤緯
        
        let y = sin(lambda) * cos(obliquity) - tan(beta) * sin(obliquity)
        let x = cos(lambda)
        var rightAscension = atan2(y, x) // 赤經 (Right Ascension)
        if rightAscension < 0 { rightAscension += 2 * .pi }
        
        // 5. 計算格林威治恆星時 (Greenwich Mean Sidereal Time, GMST)
        let gmst = (18.697374558 + 24.06570982441908 * daysSinceJ2000).truncatingRemainder(dividingBy: 24.0)
        
        // 6. 計算地方恆星時 (Local Sidereal Time) 與 時角 (Hour Angle)
        let lst = (gmst * 15.0 + longitude).truncatingRemainder(dividingBy: 360.0) * deg2rad
        let hourAngle = lst - rightAscension
        
        let latRad = latitude * deg2rad
        
        // 7. 球面三角學：轉換為地平座標 (Altitude & Azimuth)
        let sinAltitude = sin(latRad) * sin(declination) + cos(latRad) * cos(declination) * cos(hourAngle)
        let altitude = asin(sinAltitude)
        
        let cosAzimuth = (sin(declination) - sin(latRad) * sinAltitude) / (cos(latRad) * cos(altitude))
        var azimuth = acos(max(-1.0, min(1.0, cosAzimuth)))
        if sin(hourAngle) > 0 {
            azimuth = 2.0 * .pi - azimuth
        }
        
        // 8. 轉換為 3D 向量 (y軸為天頂, x軸為東, z軸為南)
        let vecX = Float(cos(altitude) * sin(azimuth))
        let vecY = Float(sin(altitude))
        let vecZ = Float(cos(altitude) * cos(azimuth))
        
        return simd_normalize(SIMD3<Float>(vecX, vecY, vecZ))
    }
    
    /// 根據給定時間計算月相 (0.0 ~ 1.0)
    /// - Parameter date: 當下時間
    /// - Returns: 月相進度，0.0 為新月，0.5 為滿月
    static func getMoonPhase(date: Date) -> Float {
        // 使用 2000 年 1 月 6 日 18:14 UTC 作為已知的新月基準點 (J2000 附近)
        let referenceNewMoon = Date(timeIntervalSince1970: 947182440)
        
        let daysSince = date.timeIntervalSince(referenceNewMoon) / 86400.0
        let lunarCycle = 29.53058867 // 朔望月平均天數
        
        // 計算餘數並轉換為 0~1 的比例
        var phase = Float(daysSince.truncatingRemainder(dividingBy: lunarCycle) / lunarCycle)
        
        // 確保為正數
        if phase < 0 {
            phase += 1.0
        }
        
        return phase
    }
}
