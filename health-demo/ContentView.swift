//
//  ContentView.swift
//  health-demo
//
//  Created by ByteDance on 2024/10/13.
//

import SwiftUI
import HealthKit

let healthStore = HKHealthStore()

struct ContentView: View {
    @State private var sleepData: String = "正在加载睡眠数据..."
    
    var body: some View {
        VStack {
            Image(systemName: "moon.stars.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text(sleepData)
                .padding()
        }
        .onAppear {
            self.requestSleepData()
        }
        .padding()
    }
    
    private func requestSleepData() {
        let sleepType = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!
        
        healthStore.requestAuthorization(toShare: nil, read: Set([sleepType])) { success, error in
            if success {
                self.querySleepData()
            } else {
                sleepData = "权限请求失败: \(error?.localizedDescription ?? "未知错误")"
            }
        }
    }
    
    private func querySleepData() {
        let sleepType = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!
        let query = HKSampleQuery(sampleType: sleepType, predicate: nil, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            guard let sleepSamples = samples as? [HKCategorySample] else {
                DispatchQueue.main.async {
                    sleepData = "无法获取睡眠数据: \(error?.localizedDescription ?? "未知错误")"
                }
                return
            }
            
            DispatchQueue.main.async {
                if sleepSamples.isEmpty {
                    sleepData = "未发现睡眠数据"
                } else {
                    let totalSleep = sleepSamples.map { $0.endDate.timeIntervalSince($0.startDate) }.reduce(0, +)
                    let totalHours = totalSleep / 3600
                    sleepData = "总睡眠时间: \(totalHours)小时"
                }
            }
        }
        
        healthStore.execute(query)
    }

    
}

#Preview {
    ContentView()
}
