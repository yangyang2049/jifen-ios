//
//  DiceToolView.swift
//  jifen
//
//  Dice tool - pixel perfect copy using WKWebView
//

import SwiftUI
import WebKit

struct DiceToolView: View {
    @State private var hasRolled = false
    @State private var webVisible = false
    @State private var showHint = false
    
    private let hintShownKey = "dice_hint_shown"
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // WebView for dice animation
            DiceWebView(
                webVisible: $webVisible,
                hasRolled: $hasRolled,
                onSoundRequest: {
                    playDiceSound()
                }
            )
            .opacity(webVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: webVisible)
            
            // Hint text (only when not rolled and show once)
            if !hasRolled && showHint {
                VStack {
                    Spacer()
                    Text("点击屏幕摇骰子")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 80)
                }
            }
        }
        .navigationTitle("骰子")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            checkAndShowHint()
        }
    }
    
    private func checkAndShowHint() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: hintShownKey) {
            showHint = true
            defaults.set(true, forKey: hintShownKey)
        } else {
            showHint = false
        }
    }
    
    private func playDiceSound() {
        VibrationManager.shared.vibrateMedium()
        SoundManager.shared.playSound("dice")
        
        // Mark as rolled to hide hint
        if !hasRolled {
            hasRolled = true
        }
    }
}

// WKWebView wrapper for SwiftUI
struct DiceWebView: UIViewRepresentable {
    @Binding var webVisible: Bool
    @Binding var hasRolled: Bool
    let onSoundRequest: () -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        
        // Add user script for native interface
        let script = """
        window.nativeInterface = {
            playSound: function() {
                window.webkit.messageHandlers.playSound.postMessage({});
            }
        };
        """
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(userScript)
        
        // Add message handler
        webView.configuration.userContentController.add(context.coordinator, name: "playSound")
        
        // Load HTML from bundle
        if let htmlPath = Bundle.main.path(forResource: "dice", ofType: "html") {
            let htmlURL = URL(fileURLWithPath: htmlPath)
            let htmlString = try? String(contentsOf: htmlURL, encoding: .utf8)
            if let html = htmlString {
                webView.loadHTMLString(html, baseURL: htmlURL.deletingLastPathComponent())
            } else {
                // Fallback: load embedded HTML
                let htmlString = getDiceHTML()
                webView.loadHTMLString(htmlString, baseURL: nil)
            }
        } else {
            // Fallback: load embedded HTML
            let htmlString = getDiceHTML()
            webView.loadHTMLString(htmlString, baseURL: nil)
        }
        
        context.coordinator.webView = webView
        
        // Show WebView after 400ms delay (fade in effect)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            webVisible = true
        }
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Update if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSoundRequest: onSoundRequest)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        var webView: WKWebView?
        let onSoundRequest: () -> Void
        
        init(onSoundRequest: @escaping () -> Void) {
            self.onSoundRequest = onSoundRequest
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "playSound" {
                onSoundRequest()
            }
        }
    }
    
    private func getDiceHTML() -> String {
        // Return the exact HTML from HarmonyOS project
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
            <title>3D Dice</title>
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                    -webkit-tap-highlight-color: transparent;
                }
                body {
                    width: 100vw;
                    height: 100vh;
                    background: #000000;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    overflow: hidden;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    cursor: pointer;
                }
                #wrapper {
                    position: relative;
                    width: 200px;
                    height: 200px;
                    perspective: 1200px;
                }
                #platform {
                    width: 200px;
                    height: 200px;
                    transform-style: preserve-3d;
                }
                #platform.settling {
                    transition: transform 0.6s cubic-bezier(0.2, 0, 0.2, 1);
                }
                #dice {
                    position: absolute;
                    width: 200px;
                    height: 200px;
                    transform-style: preserve-3d;
                    transform: translateZ(-100px);
                }
                #dice.settling {
                    transition: transform 0.6s cubic-bezier(0.2, 0, 0.2, 1);
                }
                .side {
                    position: absolute;
                    width: 200px;
                    height: 200px;
                    background: linear-gradient(145deg, #ffffff 0%, #f5f5f5 100%);
                    box-shadow: inset 0 0 40px rgba(0, 0, 0, 0.1);
                    border-radius: 40px;
                }
                #dice .inner {
                    background: #f0f0f0;
                    box-shadow: none;
                    border-radius: 38px;
                }
                #dice .cover {
                    background: #e8e8e8;
                    box-shadow: none;
                    border-radius: 0;
                    transform: translateZ(0px);
                }
                #dice .cover.x {
                    transform: rotateY(90deg);
                }
                #dice .cover.z {
                    transform: rotateX(90deg);
                }
                #dice .front {
                    transform: translateZ(100px);
                }
                #dice .front.inner {
                    transform: translateZ(98px);
                }
                #dice .back {
                    transform: rotateX(-180deg) translateZ(100px);
                }
                #dice .back.inner {
                    transform: rotateX(-180deg) translateZ(98px);
                }
                #dice .right {
                    transform: rotateY(90deg) translateZ(100px);
                }
                #dice .right.inner {
                    transform: rotateY(90deg) translateZ(98px);
                }
                #dice .left {
                    transform: rotateY(-90deg) translateZ(100px);
                }
                #dice .left.inner {
                    transform: rotateY(-90deg) translateZ(98px);
                }
                #dice .top {
                    transform: rotateX(90deg) translateZ(100px);
                }
                #dice .top.inner {
                    transform: rotateX(90deg) translateZ(98px);
                }
                #dice .bottom {
                    transform: rotateX(-90deg) translateZ(100px);
                }
                #dice .bottom.inner {
                    transform: rotateX(-90deg) translateZ(98px);
                }
                .dot {
                    position: absolute;
                    width: 40px;
                    height: 40px;
                    border-radius: 20px;
                    background: radial-gradient(circle at 30% 30%, #e53935 0%, #c62828 50%, #b71c1c 100%);
                    box-shadow: inset 0 -2px 4px rgba(0, 0, 0, 0.4);
                }
                .dot.center {
                    margin: 80px 0 0 80px;
                }
                .dot.dtop {
                    margin-top: 25px;
                }
                .dot.dleft {
                    margin-left: 135px;
                }
                .dot.dright {
                    margin-left: 25px;
                }
                .dot.dbottom {
                    margin-top: 135px;
                }
                .dot.center.dleft {
                    margin: 80px 0 0 25px;
                }
                .dot.center.dright {
                    margin: 80px 0 0 135px;
                }
                @keyframes spin {
                    0% { transform: translateZ(-100px) rotateX(0deg) rotateY(0deg) rotateZ(0deg); }
                    20% { transform: translateZ(-100px) rotateX(135deg) rotateY(135deg) rotateZ(0deg); }
                    40% { transform: translateZ(-100px) rotateX(270deg) rotateY(70deg) rotateZ(135deg); }
                    60% { transform: translateZ(-100px) rotateX(405deg) rotateY(270deg) rotateZ(270deg); }
                    80% { transform: translateZ(-100px) rotateX(135deg) rotateY(405deg) rotateZ(200deg); }
                    100% { transform: translateZ(-100px) rotateX(270deg) rotateY(270deg) rotateZ(270deg); }
                }
                @keyframes roll {
                    0% { transform: translate3d(-75px, -15px, -150px); }
                    12.5% { transform: translate3d(0px, 0, -45px); }
                    25% { transform: translate3d(75px, -15px, -150px); }
                    37.5% { transform: translate3d(0px, -30px, -225px); }
                    50% { transform: translate3d(-75px, -15px, -150px); }
                    62.5% { transform: translate3d(0px, 0, -45px); }
                    75% { transform: translate3d(75px, -15px, -150px); }
                    87.5% { transform: translate3d(-45px, -8px, -75px); }
                    95% { transform: translate3d(20px, -4px, -35px); }
                    100% { transform: translate3d(0px, 0px, 0px); }
                }
                #dice.rolling {
                    animation: spin 1.4s ease-out forwards;
                }
                #platform.rolling {
                    animation: roll 1.4s ease-out forwards;
                }
            </style>
        </head>
        <body>
            <div id="wrapper">
                <div id="platform">
                    <div id="dice">
                        <div class="side front">
                            <div class="dot center"></div>
                        </div>
                        <div class="side front inner"></div>
                        <div class="side back">
                            <div class="dot dtop dleft"></div>
                            <div class="dot dtop dright"></div>
                            <div class="dot dbottom dleft"></div>
                            <div class="dot dbottom dright"></div>
                            <div class="dot center dleft"></div>
                            <div class="dot center dright"></div>
                        </div>
                        <div class="side back inner"></div>
                        <div class="side top">
                            <div class="dot dtop dleft"></div>
                            <div class="dot dbottom dright"></div>
                        </div>
                        <div class="side top inner"></div>
                        <div class="side bottom">
                            <div class="dot center"></div>
                            <div class="dot dtop dleft"></div>
                            <div class="dot dtop dright"></div>
                            <div class="dot dbottom dleft"></div>
                            <div class="dot dbottom dright"></div>
                        </div>
                        <div class="side bottom inner"></div>
                        <div class="side right">
                            <div class="dot dtop dleft"></div>
                            <div class="dot center"></div>
                            <div class="dot dbottom dright"></div>
                        </div>
                        <div class="side right inner"></div>
                        <div class="side left">
                            <div class="dot dtop dleft"></div>
                            <div class="dot dtop dright"></div>
                            <div class="dot dbottom dleft"></div>
                            <div class="dot dbottom dright"></div>
                        </div>
                        <div class="side left inner"></div>
                        <div class="side cover x"></div>
                        <div class="side cover y"></div>
                        <div class="side cover z"></div>
                    </div>
                </div>
            </div>
            <script>
                const dice = document.getElementById('dice');
                const platform = document.getElementById('platform');
                let isRolling = false;
                const faceRotations = {
                    1: { x: 0, y: 0, z: 0 },
                    2: { x: -90, y: 0, z: 0 },
                    3: { x: 0, y: -90, z: 0 },
                    4: { x: 0, y: 90, z: 0 },
                    5: { x: 90, y: 0, z: 0 },
                    6: { x: 180, y: 0, z: 0 }
                };
                function rollDice() {
                    if (isRolling) return;
                    isRolling = true;
                    try {
                        if (window.nativeInterface && window.nativeInterface.playSound) {
                            window.nativeInterface.playSound();
                        }
                    } catch (e) {
                        console.log('Native sound not available');
                    }
                    const finalValue = Math.floor(Math.random() * 6) + 1;
                    const finalRotation = faceRotations[finalValue];
                    dice.classList.add('rolling');
                    platform.classList.add('rolling');
                    setTimeout(() => {
                        dice.classList.remove('rolling');
                        platform.classList.remove('rolling');
                        setTimeout(() => {
                            dice.classList.add('settling');
                            platform.classList.add('settling');
                            dice.style.transform = `translateZ(-100px) rotateX(${finalRotation.x}deg) rotateY(${finalRotation.y}deg) rotateZ(${finalRotation.z}deg)`;
                            platform.style.transform = 'translate3d(0, 0, 0)';
                            setTimeout(() => {
                                dice.classList.remove('settling');
                                platform.classList.remove('settling');
                                isRolling = false;
                            }, 600);
                        }, 50);
                    }, 1400);
                }
                document.body.addEventListener('click', rollDice);
                document.body.addEventListener('touchstart', function (e) {
                    e.preventDefault();
                    rollDice();
                }, { passive: false });
                dice.style.transform = `translateZ(-100px) rotateX(${faceRotations[1].x}deg) rotateY(${faceRotations[1].y}deg) rotateZ(${faceRotations[1].z}deg)`;
            </script>
        </body>
        </html>
        """
    }
}

#Preview {
    NavigationStack {
        DiceToolView()
    }
}
