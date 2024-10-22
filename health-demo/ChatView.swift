import SwiftUI
import Foundation

struct Message: Identifiable, Codable {
    let id = UUID()
    var content: String // 将 let 改为 var
    let isUser: Bool
}

struct Delta: Codable {
    let role: String?
    let content: String?
}

struct Choice: Codable {
    let index: Int
    let delta: Delta
}

struct APIResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
}

class CustomURLSessionDelegate: NSObject, URLSessionDataDelegate, URLSessionDelegate {
    private var receivedData = ""
    private let decoder = JSONDecoder()
    private var content = ""

    // 定义请求成功的回调类型
    var onSuccess: ((APIResponse) -> Void)?

    // 处理接收到的数据
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let streamData = data.split(separator: 10) // 按换行符分割数据

        for line in streamData {
            let jsonData = Data(line) 
            do {
                // 尝试将 jsonData 转换为字符串
                guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                    print("无法将数据转换为字符串，返回")
                    return
                }

                // 去掉 data: 前缀
                let jsonStringWithoutPrefix = jsonString.replacingOccurrences(of: "data: ", with: "")

                // 检查是否为 [DONE]
                if jsonStringWithoutPrefix == "[DONE]" {
                    print("流式渲染完成")
                    return 
                }

                // 将处理后的字符串转换为 Data
                guard let validJsonData = jsonStringWithoutPrefix.data(using: .utf8) else {
                    print("无法将处理后的字符串转换为 Data，返回")
                    return
                }

                // 使用 JSONDecoder 进行解析
                let apiResponse = try decoder.decode(APIResponse.self, from: validJsonData)
                // 调用成功的回调
                self.onSuccess?(apiResponse)
            } catch {
                print("JSON解析错误: \(error.localizedDescription)")
            }
        }
    }

    // 处理请求完成或出错
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("网络错误: \(error.localizedDescription)")
        } else {
            print("流式请求完成")
        }
    }

    // 处理 SSL 证书挑战
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            // 忽略 SSL 验证
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

struct ChatView: View {
    @State private var messages: [Message] = []
    @State private var newMessage = ""

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            
            HStack {
                TextField("输入消息", text: $newMessage)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .padding(.trailing)
            }
            .padding(.bottom)
        }
        .onAppear {
            loadMessages() // 加载消息
        }
    }
    
    func sendMessage() {
        guard !newMessage.isEmpty else { return }
        
        let userMessage = Message(content: newMessage, isUser: true)
        messages.append(userMessage)

        callChatGPTAPI()
        DispatchQueue.main.async {
            saveMessages() // 保存消息
        }
        
        newMessage = ""
    }
    
    func callChatGPTAPI() {
        guard let url = URL(string: "https://api.openai-next.com/v1/chat/completions") else {
            print("API URL无效")
            return
        }
        
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String else {
            print("API_KEY not found")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // 构建消息数组
        let messagesForAPI = messages.map { message in
            ["role": message.isUser ? "user" : "assistant", "content": message.content]
        }
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messagesForAPI,
            "stream": true // 启用流式渲染
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("请求体序列化错误: \(error.localizedDescription)")
            return
        }
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        
        // 创建 CustomURLSessionDelegate 实例并传入回调
        let sessionDelegate = CustomURLSessionDelegate()
        var content = ""
        sessionDelegate.onSuccess = { apiResponse in
            if let firstChoice = apiResponse.choices.first {
                    if let deltaContent = firstChoice.delta.content {
                        content += deltaContent // 使用 deltaContent 进行拼接

                        DispatchQueue.main.async {
                            // 更新最后一条消息的内容
                            if !messages.isEmpty {
                                messages[messages.count - 1].content = content 
                            }
                            saveMessages()            
                        }
                    }
                }
        }

        let session = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)

        // 创建 AI 消息并添加到 messages
        var aiMessage = Message(content: "", isUser: false) // 初始内容为空
        messages.append(aiMessage) // 直接在这里添加

        let dataTask = session.dataTask(with: request)
        dataTask.resume()
    }
    
    private func saveMessages() {
        if let encoded = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(encoded, forKey: "savedMessages")
        }
    }
    
    private func loadMessages() {
        if let data = UserDefaults.standard.data(forKey: "savedMessages"),
           let decodedMessages = try? JSONDecoder().decode([Message].self, from: data) {
            messages = decodedMessages
        }
    }
}

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.isUser { Spacer() }
            
            Text(message.content)
                .padding(10)
                .background(message.isUser ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
            
            if !message.isUser { Spacer() }
        }
    }
}
