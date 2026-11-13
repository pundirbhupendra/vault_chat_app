import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'chat_screen.dart';
import 'local_chat_bloc.dart';
import 'local_llm_repository.dart';
import 'rag/rag_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final ragRepository = RagRepository();
  await ragRepository.initialize();
  final localLlmRepository = LocalLlmRepository();
  await localLlmRepository.initDownloader();

  runApp(
    OfflineAiApp(
      ragRepository: ragRepository,
      localLlmRepository: localLlmRepository,
    ),
  );
}

class OfflineAiApp extends StatelessWidget {
  final RagRepository ragRepository;
  final LocalLlmRepository localLlmRepository;

  const OfflineAiApp({
    super.key,
    required this.ragRepository,
    required this.localLlmRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline AI Chat',
      theme: ThemeData.dark(useMaterial3: true),
      home: RepositoryProvider.value(
        value: ragRepository,
        child: RepositoryProvider.value(
          value: localLlmRepository,
          child: Builder(
            builder: (context) => BlocProvider(
              create: (_) => LocalChatBloc(
                repository: localLlmRepository,
                ragRepository: ragRepository,
              )..add(CheckModelStatusEvent()),
              child: const LocalChatScreen(),
            ),
          ),
        ),
      ),
    );
  }
}
