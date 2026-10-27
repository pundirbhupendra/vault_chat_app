Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final ragRepository = RagRepository();
  await ragRepository.initialize();

  runApp(OfflineAiApp(ragRepository: ragRepository));
}

class OfflineAiApp extends StatelessWidget {
  final RagRepository ragRepository;

  const OfflineAiApp({
    super.key,
    required this.ragRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline AI Chat',
      theme: ThemeData.dark(useMaterial3: true),
      home: RepositoryProvider.value(
        value: ragRepository,
        child: RepositoryProvider(
          create: (_) => LocalLlmRepository(),
          child: Builder(
            builder: (context) => BlocProvider(
              create: (_) => LocalChatBloc(
                repository: context.read<LocalLlmRepository>(),
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