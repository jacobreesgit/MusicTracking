//
//  MusicTrackingApp.swift
//  MusicTracking
//
//  Created by Jacob Rees on 27/06/2025.
//

import SwiftUI
import CoreData
import BackgroundTasks
import AVFoundation

@main
struct MusicTrackingApp: App {
    
    @State private var appStateManager = AppStateManager.shared
    private let backgroundTaskManager = BackgroundTaskManager.shared
    @State private var audioSessionManager = AudioSessionManager.shared
    
    var body: some Scene {
        WindowGroup {
            Group {
                if appStateManager.isInitialized {
                    MainTabView()
                } else {
                    SplashScreenView()
                }
            }
            .environment(\.managedObjectContext, appStateManager.persistenceController.container.viewContext)
            .onAppear {
                setupApplication()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                handleAppDidEnterBackground()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                handleAppWillEnterForeground()
            }
        }
    }
    
    private func setupApplication() {
        registerBackgroundTasks()
        configureAudioSession()
        backgroundTaskManager.scheduleBackgroundTasks()
    }
    
    private func registerBackgroundTasks() {
        backgroundTaskManager.registerBackgroundTasks()
        print("Background tasks registered in app startup")
    }
    
    private func configureAudioSession() {
        do {
            try audioSessionManager.configureForBackgroundMonitoring()
            print("Audio session configured for background monitoring")
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    private func handleAppDidEnterBackground() {
        backgroundTaskManager.scheduleBackgroundTasks()
        
        do {
            try audioSessionManager.activateSession()
            print("Audio session activated for background mode")
        } catch {
            print("Failed to activate audio session in background: \(error)")
        }
    }
    
    private func handleAppWillEnterForeground() {
        print("App entering foreground")
    }
}

private struct SplashScreenView: View {
    @State private var appStateManager = AppStateManager.shared
    @State private var animationPhase: Int = 0
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .scaleEffect(animationPhase >= 1 ? 1.1 : 0.8)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: animationPhase)
                
                Text("Music Tracking")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .opacity(animationPhase >= 2 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5).delay(0.3), value: animationPhase)
                
                Text("Discover your music patterns")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .opacity(animationPhase >= 3 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5).delay(0.6), value: animationPhase)
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                if let error = appStateManager.initializationError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundColor(.orange)
                        
                        Text("Initialization Failed")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        Text(error.localizedDescription)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Try Again") {
                            Task {
                                await appStateManager.initialize()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(1.2)
                        .opacity(animationPhase >= 4 ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3).delay(0.9), value: animationPhase)
                    
                    Text("Setting up your music tracking...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .opacity(animationPhase >= 4 ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3).delay(1.2), value: animationPhase)
                }
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            startAnimationSequence()
            
            if !appStateManager.isInitialized {
                Task {
                    await appStateManager.initialize()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appInitializationCompleted)) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                // MainTabView will appear automatically when isInitialized becomes true
            }
        }
    }
    
    private func startAnimationSequence() {
        withAnimation {
            animationPhase = 1
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                animationPhase = 2
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation {
                animationPhase = 3
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation {
                animationPhase = 4
            }
        }
    }
}