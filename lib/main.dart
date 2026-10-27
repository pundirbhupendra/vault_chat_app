import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'chat_screen.dart';
import 'local_chat_bloc.dart';
import 'local_llm_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OfflineAiApp());
}

class OfflineAiApp extends StatelessWidget {
  const OfflineAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline AI Chat',
      theme: ThemeData.dark(useMaterial3: true),
      home: RepositoryProvider(
        create: (_) => LocalLlmRepository(),
        child: BlocProvider(
          create: (ctx) => LocalChatBloc(
            repository: ctx.read<LocalLlmRepository>(),
          )..add(CheckModelStatusEvent()),
          child: const LocalChatScreen(),
        ),
      ),
    );
  }
}