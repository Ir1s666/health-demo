import SwiftUI
import Foundation

struct Message: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
}

class CustomURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
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
    }
    
    func sendMessage() {
        guard !newMessage.isEmpty else { return }
        
        let userMessage = Message(content: newMessage, isUser: true)
        messages.append(userMessage)
        
        callChatGPTAPI(with: newMessage) { response in
            DispatchQueue.main.async {
                let aiMessage = Message(content: response, isUser: false)
                messages.append(aiMessage)
            }
        }
        
        newMessage = ""
    }
    
    func callChatGPTAPI(with message: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: "https://api.openai-next.com/v1/chat/completions") else {
            completion("API URL无效")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer sk-key", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "stream": false,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant."],
                ["role": "user", "content": message]
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let delegate = CustomURLSessionDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("网络错误: \(error.localizedDescription)")
                completion("错误: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP 状态码: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                completion("无数据返回")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let messageObj = firstChoice["message"] as? [String: Any],
                   let content = messageObj["content"] as? String {
                    completion(content)
                } else {
                    completion("无法解析API响应")
                }
            } catch {
                print("JSON解析错误: \(error.localizedDescription)")
                completion("JSON解析错误: \(error.localizedDescription)")
            }
        }.resume()
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
