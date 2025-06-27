import SwiftUI

public struct ErrorAlertModifier: ViewModifier {
    @Binding var error: AppError?
    let onRetry: (() -> Void)?
    
    public init(error: Binding<AppError?>, onRetry: (() -> Void)? = nil) {
        self._error = error
        self.onRetry = onRetry
    }
    
    public func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: .constant(error != nil)) {
                Group {
                    if let error = error, error.isRetryable, let onRetry = onRetry {
                        Button("Retry") {
                            onRetry()
                        }
                        Button("Cancel", role: .cancel) {
                            self.error = nil
                        }
                    } else {
                        Button("OK") {
                            self.error = nil
                        }
                    }
                }
            } message: {
                if let error = error {
                    Text(error.localizedDescription)
                }
            }
    }
}

public struct CustomErrorAlert: ViewModifier {
    @Binding var error: AppError?
    let title: String
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?
    
    public init(
        error: Binding<AppError?>,
        title: String = "Error",
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self._error = error
        self.title = title
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }
    
    public func body(content: Content) -> some View {
        content
            .alert(title, isPresented: .constant(error != nil)) {
                Group {
                    if let error = error {
                        if error.isRetryable, let onRetry = onRetry {
                            Button("Retry") {
                                onRetry()
                                self.error = nil
                            }
                        }
                        
                        if error.requiresUserAction {
                            Button("Settings") {
                                openSettings()
                                self.error = nil
                            }
                        }
                        
                        Button("OK") {
                            self.error = nil
                            onDismiss?()
                        }
                    }
                }
            } message: {
                if let error = error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error.localizedDescription)
                        
                        if error.requiresUserAction {
                            Text("Please check your settings and try again.")
                                .font(.caption)
                        }
                    }
                }
            }
    }
    
    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

public struct ToastErrorModifier: ViewModifier {
    @Binding var error: AppError?
    @State private var showToast = false
    
    public init(error: Binding<AppError?>) {
        self._error = error
    }
    
    public func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if showToast, let error = error {
                        ToastView(error: error) {
                            withAnimation {
                                showToast = false
                                self.error = nil
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                },
                alignment: .top
            )
            .onChange(of: error) { _, newError in
                if newError != nil {
                    withAnimation(.spring()) {
                        showToast = true
                    }
                    
                    // Auto-hide after 4 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        if showToast {
                            withAnimation {
                                showToast = false
                                self.error = nil
                            }
                        }
                    }
                }
            }
    }
}

private struct ToastView: View {
    let error: AppError
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: errorIcon)
                .foregroundColor(errorColor)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(errorTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(error.localizedDescription)
                    .font(.callout)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var errorIcon: String {
        switch error {
        case .musicKitNotAuthorized, .musicKitPermissionDenied:
            return "music.note.list"
        case .cloudKitSyncFailed, .cloudKitNotAvailable:
            return "icloud.slash"
        case .backgroundTaskFailed, .backgroundTaskExpired:
            return "exclamationmark.triangle"
        case .networkUnavailable:
            return "wifi.slash"
        default:
            return "exclamationmark.circle"
        }
    }
    
    private var errorColor: Color {
        switch error {
        case .musicKitNotAuthorized, .musicKitPermissionDenied:
            return .orange
        case .cloudKitSyncFailed, .cloudKitNotAvailable:
            return .blue
        case .backgroundTaskFailed, .backgroundTaskExpired:
            return .red
        case .networkUnavailable:
            return .gray
        default:
            return .red
        }
    }
    
    private var errorTitle: String {
        switch error {
        case .musicKitNotAuthorized, .musicKitPermissionDenied:
            return "Music Access Required"
        case .cloudKitSyncFailed, .cloudKitNotAvailable:
            return "Sync Issue"
        case .backgroundTaskFailed, .backgroundTaskExpired:
            return "Background Task Failed"
        case .networkUnavailable:
            return "No Internet Connection"
        default:
            return "Error"
        }
    }
}

public struct InlineErrorView: View {
    let error: AppError
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?
    
    public init(
        error: AppError,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.error = error
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Something went wrong")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(error.localizedDescription)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            HStack(spacing: 12) {
                if error.isRetryable, let onRetry = onRetry {
                    Button(action: onRetry) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Try Again")
                        }
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                if error.requiresUserAction {
                    Button(action: {
                        openSettings()
                        onDismiss?()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "gear")
                            Text("Settings")
                        }
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Spacer()
                
                if let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                            .padding(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

// MARK: - View Extensions

extension View {
    public func errorAlert(error: Binding<AppError?>, onRetry: (() -> Void)? = nil) -> some View {
        modifier(ErrorAlertModifier(error: error, onRetry: onRetry))
    }
    
    public func customErrorAlert(
        error: Binding<AppError?>,
        title: String = "Error",
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(CustomErrorAlert(error: error, title: title, onRetry: onRetry, onDismiss: onDismiss))
    }
    
    public func toastError(error: Binding<AppError?>) -> some View {
        modifier(ToastErrorModifier(error: error))
    }
}

#Preview("Alert Error") {
    struct PreviewView: View {
        @State private var error: AppError? = AppError.musicKitNotAuthorized
        
        var body: some View {
            VStack {
                Button("Show Error") {
                    error = AppError.musicKitNotAuthorized
                }
                .padding()
            }
            .errorAlert(error: $error) {
                print("Retry tapped")
            }
        }
    }
    
    return PreviewView()
}

#Preview("Toast Error") {
    struct PreviewView: View {
        @State private var error: AppError?
        
        var body: some View {
            VStack {
                Button("Show Toast Error") {
                    error = AppError.cloudKitSyncFailed("Sync failed")
                }
                .padding()
            }
            .toastError(error: $error)
        }
    }
    
    return PreviewView()
}

#Preview("Inline Error") {
    VStack {
        InlineErrorView(
            error: AppError.backgroundTaskFailed("Background task failed"),
            onRetry: {
                print("Retry tapped")
            },
            onDismiss: {
                print("Dismiss tapped")
            }
        )
        .padding()
        
        Spacer()
    }
}