import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'chat_message.dart';
import 'local_llm_repository.dart';

enum EngineStatus {
  initial,
  needsDownload,
  downloading,
  loadingModel,
  ready,
  generating,
  error,
}

class LocalChatState extends Equatable {
  final EngineStatus status;
  final double downloadProgress;
  final List<ChatMessage> messages;
  final String? errorMessage;

  const LocalChatState({
    this.status = EngineStatus.initial,
    this.downloadProgress = 0.0,
    this.messages = const [],
    this.errorMessage,
  });

  LocalChatState copyWith({
    EngineStatus? status,
    double? downloadProgress,
    List<ChatMessage>? messages,
    String? errorMessage,
  }) {
    return LocalChatState(
      status: status ?? this.status,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      messages: messages ?? this.messages,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, downloadProgress, messages, errorMessage];
}

// --- EVENTS ---
abstract class LocalChatEvent {}

class CheckModelStatusEvent extends LocalChatEvent {}

class StartDownloadModelEvent extends LocalChatEvent {}

class SendUserMessageEvent extends LocalChatEvent {
  final String text;
  SendUserMessageEvent(this.text);
}

class ClearConversationEvent extends LocalChatEvent {}

// --- BLOC ---
class LocalChatBloc extends Bloc<LocalChatEvent, LocalChatState> {
  final LocalLlmRepository repository;

  LocalChatBloc({required this.repository}) : super(const LocalChatState()) {
    on<CheckModelStatusEvent>(_onCheckStatus);
    on<StartDownloadModelEvent>(_onDownloadModel);
    on<SendUserMessageEvent>(_onSendMessage);
    on<ClearConversationEvent>(_onClearConversation);
  }

  Future<void> _onCheckStatus(
    CheckModelStatusEvent event,
    Emitter<LocalChatState> emit,
  ) async {
    try {
      final isDownloaded = await repository.isModelDownloaded();
      if (!isDownloaded) {
        emit(state.copyWith(status: EngineStatus.needsDownload));
        return;
      }
      emit(state.copyWith(status: EngineStatus.loadingModel));
      await repository.loadModel();
      emit(state.copyWith(status: EngineStatus.ready));
    } catch (e) {
      emit(
        state.copyWith(status: EngineStatus.error, errorMessage: e.toString()),
      );
    }
  }

  Future<void> _onDownloadModel(
    StartDownloadModelEvent event,
    Emitter<LocalChatState> emit,
  ) async {
    emit(
      state.copyWith(status: EngineStatus.downloading, downloadProgress: 0.0),
    );
    try {
      await repository.downloadModel(
        onProgress: (progress) {
          emit(
            state.copyWith(
              status: EngineStatus.downloading,
              downloadProgress: progress,
            ),
          );
        },
        onStatus: (status) => emit(
          state.copyWith(
            status: EngineStatus.downloading,
            downloadProgress: state.downloadProgress,
          ),
        ),
      );
      emit(state.copyWith(status: EngineStatus.loadingModel));
      await repository.loadModel();
      emit(state.copyWith(status: EngineStatus.ready));
    } catch (e) {
      emit(
        state.copyWith(
          status: EngineStatus.error,
          errorMessage: 'Download failed: $e',
        ),
      );
    }
  }

  Future<void> _onSendMessage(
    SendUserMessageEvent event,
    Emitter<LocalChatState> emit,
  ) async {
    if (event.text.trim().isEmpty || state.status == EngineStatus.generating) {
      return;
    }

    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: event.text.trim(),
    );

    final assistantPlaceholder = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_ai',
      role: MessageRole.assistant,
      content: '',
      isStreaming: true,
    );

    final historyWithUser = [...state.messages, userMsg];
    emit(
      state.copyWith(
        status: EngineStatus.generating,
        messages: [...historyWithUser, assistantPlaceholder],
      ),
    );

    try {
      final tokenStream = repository.streamChatCompletion(historyWithUser);
      final buffer = StringBuffer();

      await emit.forEach<String>(
        tokenStream,
        onData: (token) {
          // Stop if the model emits the ChatML end token
          final cleanToken = token.replaceAll('<|im_end|>', '');
          buffer.write(cleanToken);

          final updatedMessages = List<ChatMessage>.from(state.messages);
          updatedMessages.last = assistantPlaceholder.copyWith(
            content: buffer.toString(),
            isStreaming: true,
          );
          return state.copyWith(messages: updatedMessages);
        },
      );

      // Finalize streaming message
      final finalMessages = List<ChatMessage>.from(state.messages);
      finalMessages.last = finalMessages.last.copyWith(isStreaming: false);
      emit(state.copyWith(status: EngineStatus.ready, messages: finalMessages));
    } catch (e) {
      emit(
        state.copyWith(
          status: EngineStatus.error,
          errorMessage: 'Inference error: $e',
        ),
      );
    }
  }

  void _onClearConversation(
    ClearConversationEvent event,
    Emitter<LocalChatState> emit,
  ) {
    emit(state.copyWith(messages: []));
  }

  @override
  Future<void> close() async {
    await repository.dispose();
    return super.close();
  }
}
