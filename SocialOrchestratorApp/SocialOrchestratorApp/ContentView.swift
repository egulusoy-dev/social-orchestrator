import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Models

struct ScheduledPostItem: Identifiable, Codable {
    var id: Int?
    let title: String
    let content_text: String
    let media_url: String?
    let target_platforms: [String]
    let scheduled_time: String
    let status: String
}

struct AnalyticsSummary: Codable {
    let total_impressions: Int
    let total_likes: Int
    let total_comments: Int
    let average_engagement_rate: Double
}

struct AccountStatus: Codable {
    let youtube: String?
    let twitter: String?
    let linkedin: String?
}

struct PostCreatePayload: Encodable {
    let title: String
    let content_text: String
    let media_url: String?
    let target_platforms: [String]
    let scheduled_time: String
}

struct AIRepurposeResponse: Decodable {
    let twitter_text: String
    let linkedin_text: String
    let youtube_script: String
    let twitter_hashtags: String
    let linkedin_hashtags: String
    let youtube_tags: String
}

// MARK: - ViewModel

@MainActor
class OrchestratorViewModel: ObservableObject {
    @Published var posts: [ScheduledPostItem] = []
    @Published var analytics: AnalyticsSummary?
    @Published var accountStatus: AccountStatus?
    @Published var isConnected: Bool = false
    
    // Post Form State
    @Published var newTitle: String = ""
    @Published var newContent: String = ""
    @Published var targetYouTube: Bool = true
    @Published var targetTwitter: Bool = true
    @Published var targetLinkedIn: Bool = false
    
    // AI Content State
    @Published var promptInput: String = ""
    @Published var twitterPost: String = ""
    @Published var linkedinPost: String = ""
    @Published var youtubeScript: String = ""
    @Published var twitterHashtags: String = ""
    @Published var linkedinHashtags: String = ""
    @Published var youtubeTags: String = ""
    @Published var isGeneratingAI: Bool = false
    
    // Local Mac File Path
    @Published var selectedVideoURL: URL? = nil
    
    private var timer: AnyCancellable?
    
    init() {
        startPolling()
    }
    
    func startPolling() {
        fetchData()
        timer = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.fetchData() }
    }
    
    func fetchData() {
        guard let postsURL = URL(string: "http://127.0.0.1:8000/posts") else { return }
        URLSession.shared.dataTask(with: postsURL) { data, _, _ in
            if let data = data, let fetched = try? JSONDecoder().decode([ScheduledPostItem].self, from: data) {
                DispatchQueue.main.async {
                    self.posts = fetched
                    self.isConnected = true
                }
            } else {
                DispatchQueue.main.async { self.isConnected = false }
            }
        }.resume()
        
        guard let analyticsURL = URL(string: "http://127.0.0.1:8000/analytics/summary") else { return }
        URLSession.shared.dataTask(with: analyticsURL) { data, _, _ in
            if let data = data, let summary = try? JSONDecoder().decode(AnalyticsSummary.self, from: data) {
                DispatchQueue.main.async { self.analytics = summary }
            }
        }.resume()
        
        guard let accountsURL = URL(string: "http://127.0.0.1:8000/accounts/status") else { return }
        URLSession.shared.dataTask(with: accountsURL) { data, _, _ in
            if let data = data, let status = try? JSONDecoder().decode(AccountStatus.self, from: data) {
                DispatchQueue.main.async { self.accountStatus = status }
            }
        }.resume()
    }
    
    // Open Mac Finder Dialog
    func openMacFileFinder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .avi]
        
        if panel.runModal() == .OK {
            self.selectedVideoURL = panel.url
            if promptInput.isEmpty {
                promptInput = "Analyze video content and give title, caption, hook, and hashtag recommendations."
            }
        }
    }
    
    func connectAccount(platform: String) {
        guard let url = URL(string: "http://127.0.0.1:8000/auth/\(platform)") else { return }
        NSWorkspace.shared.open(url)
    }
    
    func generateAIContent() {
        isGeneratingAI = true
        
        if let videoURL = selectedVideoURL {
            uploadVideoAndAnalyze(url: videoURL)
        } else {
            guard let url = URL(string: "http://127.0.0.1:8000/ai/repurpose") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = ["prompt": promptInput]
            request.httpBody = try? JSONEncoder().encode(body)
            
            URLSession.shared.dataTask(with: request) { data, _, error in
                DispatchQueue.main.async { self.isGeneratingAI = false }
                guard let data = data, error == nil else { return }
                self.parseAIResponse(data: data)
            }.resume()
        }
    }
    
    private func uploadVideoAndAnalyze(url: URL) {
        guard let apiURL = URL(string: "http://127.0.0.1:8000/ai/analyze-video") else { return }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(promptInput)\r\n".data(using: .utf8)!)
        
        if let fileData = try? Data(contentsOf: url) {
            let filename = url.lastPathComponent
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async { self.isGeneratingAI = false }
            guard let data = data, error == nil else { return }
            self.parseAIResponse(data: data)
        }.resume()
    }
    
    private func parseAIResponse(data: Data) {
        if let result = try? JSONDecoder().decode(AIRepurposeResponse.self, from: data) {
            DispatchQueue.main.async {
                self.twitterPost = result.twitter_text
                self.linkedinPost = result.linkedin_text
                self.youtubeScript = result.youtube_script
                self.twitterHashtags = result.twitter_hashtags
                self.linkedinHashtags = result.linkedin_hashtags
                self.youtubeTags = result.youtube_tags
                
                if self.newContent.isEmpty {
                    self.newContent = "\(result.youtube_script)\n\n\(result.youtube_tags)"
                }
                if self.newTitle.isEmpty {
                    self.newTitle = "AI Strategy Clip"
                }
            }
        }
    }
    
    func schedulePost() {
        guard !newTitle.isEmpty, !newContent.isEmpty, let url = URL(string: "http://127.0.0.1:8000/posts") else { return }
        
        var targets: [String] = []
        if targetYouTube { targets.append("youtube") }
        if targetTwitter { targets.append("twitter") }
        if targetLinkedIn { targets.append("linkedin") }
        
        let formatter = ISO8601DateFormatter()
        let payload = PostCreatePayload(
            title: newTitle,
            content_text: newContent,
            media_url: selectedVideoURL?.lastPathComponent,
            target_platforms: targets,
            scheduled_time: formatter.string(from: Date().addingTimeInterval(2))
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(payload)
        
        URLSession.shared.dataTask(with: request) { _, _, error in
            if error == nil {
                DispatchQueue.main.async {
                    self.newTitle = ""
                    self.newContent = ""
                    self.selectedVideoURL = nil
                    self.fetchData()
                }
            }
        }.resume()
    }
}

// MARK: - Main UI

struct ContentView: View {
    @StateObject private var viewModel = OrchestratorViewModel()
    
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.08).ignoresSafeArea()
            
            NavigationView {
                SidebarView(viewModel: viewModel)
                MainDashboardView(viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1100, minHeight: 720)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var viewModel: OrchestratorViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Engine Health Status
            HStack {
                Circle()
                    .fill(viewModel.isConnected ? Color.cyan : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: viewModel.isConnected ? .cyan : .red, radius: 4)
                Text(viewModel.isConnected ? "CORE ONLINE" : "CORE DISCONNECTED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(viewModel.isConnected ? .cyan : .red)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
            
            Text("AI Content Engine")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            // Native Mac Finder Upload Button
            VStack(alignment: .leading, spacing: 6) {
                Text("LOCAL MEDIA FILE").font(.system(size: 9, weight: .bold)).foregroundColor(.gray)
                
                Button(action: { viewModel.openMacFileFinder() }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14))
                        Text(viewModel.selectedVideoURL?.lastPathComponent ?? "Browse Mac Storage...")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            
            TextField("Enter prompt or target topic...", text: $viewModel.promptInput)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
            
            Button(action: { viewModel.generateAIContent() }) {
                HStack {
                    if viewModel.isGeneratingAI {
                        ProgressView().controlSize(.small)
                        Text(" Analyzing Clip...").font(.system(size: 12, weight: .bold))
                    } else {
                        Image(systemName: "cpu")
                        Text("Generate Strategy")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Color.cyan.opacity(0.8))
                .foregroundColor(.black)
                .cornerRadius(6)
                .shadow(color: .cyan.opacity(0.3), radius: 6)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGeneratingAI)
            
            if !viewModel.youtubeScript.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        AdviceCard(platform: "YouTube Shorts", icon: "play.rectangle.fill", color: .red, text: viewModel.youtubeScript, tags: viewModel.youtubeTags) {
                            viewModel.newContent = "\(viewModel.youtubeScript)\n\n\(viewModel.youtubeTags)"
                        }
                        AdviceCard(platform: "Twitter / X", icon: "bubble.left.fill", color: .cyan, text: viewModel.twitterPost, tags: viewModel.twitterHashtags) {
                            viewModel.newContent = "\(viewModel.twitterPost)\n\n\(viewModel.twitterHashtags)"
                        }
                        AdviceCard(platform: "LinkedIn", icon: "briefcase.fill", color: .blue, text: viewModel.linkedinPost, tags: viewModel.linkedinHashtags) {
                            viewModel.newContent = "\(viewModel.linkedinPost)\n\n\(viewModel.linkedinHashtags)"
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 320)
        .background(Color(red: 0.07, green: 0.08, blue: 0.11))
    }
}

struct AdviceCard: View {
    let platform: String
    let icon: String
    let color: Color
    let text: String
    let tags: String
    let onSelect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).foregroundColor(color)
                Text(platform).font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button("Apply") { onSelect() }
                    .font(.system(size: 10, weight: .bold))
                    .buttonStyle(.bordered)
            }
            
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(4)
            
            if !tags.isEmpty {
                Text(tags)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Main Dashboard

struct MainDashboardView: View {
    @ObservedObject var viewModel: OrchestratorViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            // OAuth Account Connect Bar
            HStack(spacing: 12) {
                Text("CHANNELS:").font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
                
                ChannelConnectBadge(platform: "youtube", label: "YouTube", name: viewModel.accountStatus?.youtube, color: .red) {
                    viewModel.connectAccount(platform: "youtube")
                }
                ChannelConnectBadge(platform: "twitter", label: "Twitter/X", name: viewModel.accountStatus?.twitter, color: .cyan) {
                    viewModel.connectAccount(platform: "twitter")
                }
                ChannelConnectBadge(platform: "linkedin", label: "LinkedIn", name: viewModel.accountStatus?.linkedin, color: .blue) {
                    viewModel.connectAccount(platform: "linkedin")
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Analytics Metric Cards
            if let analytics = viewModel.analytics {
                HStack(spacing: 16) {
                    MetricBox(title: "Impressions", value: "\(analytics.total_impressions)", icon: "eye.fill", color: .cyan)
                    MetricBox(title: "Total Likes", value: "\(analytics.total_likes)", icon: "heart.fill", color: .pink)
                    MetricBox(title: "Comments", value: "\(analytics.total_comments)", icon: "message.fill", color: .blue)
                    MetricBox(title: "Engagement", value: String(format: "%.1f%%", analytics.average_engagement_rate), icon: "chart.bar.fill", color: .green)
                }
            }
            
            // Campaign Scheduler
            VStack(alignment: .leading, spacing: 14) {
                Text("Schedule Campaign")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                TextField("Campaign or Post Title", text: $viewModel.newTitle)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(10)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
                
                TextEditor(text: $viewModel.newContent)
                    .frame(height: 90)
                    .padding(4)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
                
                HStack {
                    Toggle("YouTube Shorts", isOn: $viewModel.targetYouTube).toggleStyle(.checkbox)
                    Toggle("Twitter/X", isOn: $viewModel.targetTwitter).toggleStyle(.checkbox)
                    Toggle("LinkedIn", isOn: $viewModel.targetLinkedIn).toggleStyle(.checkbox)
                    
                    Spacer()
                    
                    Button("Dispatch Post") { viewModel.schedulePost() }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.cyan)
                        .foregroundColor(.black)
                        .font(.system(size: 12, weight: .bold))
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                        .disabled(viewModel.newTitle.isEmpty || viewModel.newContent.isEmpty)
                }
            }
            .padding()
            .background(Color(red: 0.08, green: 0.09, blue: 0.12))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
            
            // Queue Table
            VStack(alignment: .leading) {
                Text("Live Queue").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                
                List(viewModel.posts) { post in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(post.title).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                            Text(post.content_text).font(.system(size: 11)).foregroundColor(.gray).lineLimit(2)
                            if let media = post.media_url {
                                Text("📁 File: \(media)").font(.system(size: 10)).foregroundColor(.cyan)
                            }
                        }
                        Spacer()
                        
                        HStack {
                            ForEach(post.target_platforms, id: \.self) { platform in
                                Text(platform.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.cyan.opacity(0.15))
                                    .foregroundColor(.cyan)
                                    .cornerRadius(4)
                            }
                        }
                        
                        Text(post.status.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(post.status == "published" ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                            .foregroundColor(post.status == "published" ? .green : .orange)
                            .cornerRadius(4)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .padding()
    }
}

struct ChannelConnectBadge: View {
    let platform: String
    let label: String
    let name: String?
    let color: Color
    let onConnect: () -> Void
    
    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 6) {
                Circle()
                    .fill(name != nil ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text(name != nil ? "\(label): \(name!)" : "Connect \(label)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(name != nil ? .white : .gray)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct MetricBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundColor(color)
                Spacer()
                Text(title).font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
            }
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(.white)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}
