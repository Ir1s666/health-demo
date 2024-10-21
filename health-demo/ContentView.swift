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
    @State private var sleepData: (hours: Int, minutes: Int) = (0, 0)
    @State private var stepCount: Int = 0
    @State private var runningDistance: Double = 0
    @State private var caloriesBurned: Double = 0
    @State private var showChat = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HealthDataCard(title: "今日睡眠", value: "\(sleepData.hours)小时 \(sleepData.minutes)分钟", icon: "moon.zzz.fill") {
                    SleepChart(sleepHours: Double(sleepData.hours) + Double(sleepData.minutes) / 60)
                }
                
                HealthDataCard(title: "今日步数", value: "\(stepCount) 步", icon: "figure.walk") {
                    StepChart(steps: stepCount)
                }
                
                HealthDataCard(title: "今日跑步", value: String(format: "%.2f 公里", runningDistance), icon: "figure.run") {
                    RunningChart(distance: runningDistance)
                }
                
                HealthDataCard(title: "今日卡路里", value: String(format: "%.0f 千卡", caloriesBurned), icon: "flame.fill") {
                    CalorieChart(calories: Int(caloriesBurned))
                }
                
                Button(action: {
                    showChat = true
                }) {
                    Text("打开聊天")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding()
        }
        .onAppear {
            self.requestHealthData()
        }
        .sheet(isPresented: $showChat) {
            ChatView()
        }
    }
    
    private func requestHealthData() {
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
            if success {
                self.querySleepData()
                self.queryStepData()
                self.queryRunningData()
                self.queryCalorieData()
            } else {
                print("权限请求失败: \(error?.localizedDescription ?? "未知错误")")
            }
        }
    }
    
    private func querySleepData() {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date(), options: .strictStartDate)
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            guard let sleepSamples = samples as? [HKCategorySample] else {
                print("无法获取睡眠数据: \(error?.localizedDescription ?? "未知错误")")
                return
            }
            
            DispatchQueue.main.async {
                if sleepSamples.isEmpty {
                    print("未发现睡眠数据")
                } else {
                    let totalSleep = sleepSamples.map { $0.endDate.timeIntervalSince($0.startDate) }.reduce(0, +)
                    let hours = Int(totalSleep / 3600)
                    let minutes = Int((totalSleep.truncatingRemainder(dividingBy: 3600)) / 60)
                    self.sleepData = (hours: hours, minutes: minutes)
                }
            }
        }
        healthStore.execute(query)
    }
    
    private func queryStepData() {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
            guard let result = result, let sum = result.sumQuantity() else {
                print("无法获取步数数据: \(error?.localizedDescription ?? "未知错误")")
                return
            }
            
            DispatchQueue.main.async {
                self.stepCount = Int(sum.doubleValue(for: HKUnit.count()))
            }
        }
        healthStore.execute(query)
    }
    
    private func queryRunningData() {
        let runningType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: runningType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
            guard let result = result, let sum = result.sumQuantity() else {
                print("无法获取跑步距离数据: \(error?.localizedDescription ?? "未知错误")")
                return
            }
            
            DispatchQueue.main.async {
                self.runningDistance = sum.doubleValue(for: HKUnit.meter()) / 1000
            }
        }
        healthStore.execute(query)
    }
    
    private func queryCalorieData() {
        let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: calorieType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
            guard let result = result, let sum = result.sumQuantity() else {
                print("无法获取卡路里数据: \(error?.localizedDescription ?? "未知错误")")
                return
            }
            
            DispatchQueue.main.async {
                self.caloriesBurned = sum.doubleValue(for: HKUnit.kilocalorie())
            }
        }
        healthStore.execute(query)
    }
}

struct HealthDataCard<Content: View>: View {
    let title: String
    let value: String
    let icon: String
    let content: Content
    
    init(title: String, value: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            content
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

struct SleepChart: View {
    let sleepHours: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: min(CGFloat(sleepHours / 12) * geometry.size.width, geometry.size.width))
            }
        }
        .frame(height: 20)
        .cornerRadius(10)
    }
}

struct StepChart: View {
    let steps: Int
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<24) { hour in
                Rectangle()
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 8, height: CGFloat(min(steps / 500, 50)))
            }
        }
    }
}

struct RunningChart: View {
    let distance: Double
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<7) { day in
                Rectangle()
                    .fill(Color.orange.opacity(0.7))
                    .frame(width: 20, height: CGFloat(min(distance * 20, 100)))
            }
        }
    }
}

struct CalorieChart: View {
    let calories: Int
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for x in 0..<Int(geometry.size.width) {
                    let y = sin(Double(x) / 20) * 20 + 20
                    if x == 0 {
                        path.move(to: CGPoint(x: CGFloat(x), y: y))
                    } else {
                        path.addLine(to: CGPoint(x: CGFloat(x), y: y))
                    }
                }
            }
            .stroke(Color.red, lineWidth: 2)
        }
        .frame(height: 50)
    }
}

#Preview {
    ContentView()
}
