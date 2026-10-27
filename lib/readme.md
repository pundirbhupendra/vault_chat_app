# Offline & Hybrid AI Chat (Flutter)

A production-grade, privacy-first mobile AI chat application built in Flutter. It seamlessly bridges **100% on-device offline LLM execution** (via `llama.cpp` FFI and GGUF model formats) with **cloud AI fallback routing**, **background OS-managed GGUF downloading**, and **reactive state management** using BLoC.

---

## 🌟 Key Architecture & Features

1. **Hybrid Execution Engine (`HybridAiRepository`)**
   * **Device-Primary, Cloud-Fallback:** Executes prompts locally using mobile compute for zero cost and total privacy. Automatically escalates to cloud frontier models (OpenAI, Groq, Gemini) if context token limits are exceeded, local RAM fails, or complex multi-step reasoning is required.
   * **Connectivity & Privacy Gates:** Automatically detects network availability and adheres to user privacy overrides (hard offline mode).

2. **Resilient Background GGUF Downloader (`background_downloader`)**
   * Downloads large GGUF weights (e.g., Qwen 2.5 1.5B/3B, ~1GB–2GB) via native iOS/Android background tasks.
   * Supports **HTTP Range pause/resume** and **Android 14+ User-Initiated Data Transfer (UIDT)** to prevent OS suspension when users minimize the app.
   * Stores files safely in `ApplicationSupportDirectory` (exempt from iOS iCloud backups and OS temp cache purges).

3. **On-Device Inference (`llamadart`)**
   * Runs GGUF models using `llama.cpp` through `LlamaEngine`.
   * Uses the supported platform backend: CPU on Android and automatic device selection on Apple platforms.
   * Passes typed chat messages to the model's chat template and limits recent history to maintain memory stability.

4. **Robust State Management (`Bloc`)**
   * Reactive stream updates for token generation, download progress, and engine status transitions (`initial`, `needsDownload`, `downloading`, `loadingModel`, `ready`, `generating`, `error`).

---

## 📁 Project Directory Structure

```text
lib/
│
├── chat_message.dart          # Domain models (ChatMessage, MessageRole, SourceCitation)
├── model_spec.dart            # GGUF model catalog registry (File sizes, URLs, specs)
├── chat_screen.dart           # UI Layer (Material 3 chat bubbles, markdown rendering, downloader cards)
├── local_chat_bloc.dart       # BLoC state machine managing chat history and downloader events
├── local_llm_repository.dart  # On-device GGUF engine wrapper (llama.cpp FFI & background downloader)
├── cloud_llm_repository.dart  # Server-Sent Events (SSE) stream client for cloud LLM fallback
├── hybrid_ai_repository.dart  # Hybrid router implementing privacy, context, and fallback rules
└── main.dart                  # App bootstrap with MultiRepositoryProvider dependency injection
```

---

## 🚀 Getting Started & Setup

### 1. Prerequisites
* Flutter SDK (3.x or higher)
* Dart 3+
* Android Studio / Xcode (for mobile FFI compilation and native background permissions)

### 2. Dependencies (`pubspec.yaml`)
Ensure your project includes the following core packages:
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_bloc: ^8.1.3
  equatable: ^2.0.5
  dio: ^5.4.0
  background_downloader: ^9.5.4
  llamadart: ^0.16.3
  llamadart_llama_cpp_flutter: ^0.16.0 # Apple llama.cpp runtime companion
  flutter_markdown: ^0.6.18
  path_provider: ^2.1.2
  connectivity_plus: ^5.0.2
```

### 3. Build & Run
To run the app with an optional cloud API key injected at build time:
```bash
flutter run --dart-define=CLOUD_API_KEY=your_openai_or_groq_api_key
```

---

## 🔄 Request Lifecycle Flow

```text
[User Types Message]
        │
        ▼
[LocalChatBloc: SendUserMessageEvent]
        │
        ▼
[HybridAiRepository]
   ├── Check Privacy Override / Hard Offline? ──► Force On-Device GGUF
   ├── Check Network Connectivity?
   └── Check Token Budget / Complexity Gate?
          ├── If Heavy Task & Online ──► [CloudLlmRepository (SSE Stream)] ──(Fallback on Error)──┐
          └── If Normal / Offline   ──► [LocalLlmRepository (llamadart Stream)] ◄─────────────────┘
        │
        ▼
[Tokens Streamed into BLoC State Buffer]
        │
        ▼
[UI Renders Live Markdown in _MessageBubble]
```

---

## 🛡️ Platform Permissions & Configuration

### Android (`android/app/src/main/AndroidManifest.xml`)
Ensure internet and foreground service/background download permissions are present:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

### iOS (`ios/Runner/Info.plist`)
Configure background fetch and background processing capabilities in Xcode under **Signing & Capabilities**, and ensure background audio/download keys are handled if required by your build target.
```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>processing</string>
</array>