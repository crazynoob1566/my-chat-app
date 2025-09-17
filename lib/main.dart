import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Добавляем задержку для инициализации
  await Future.delayed(const Duration(milliseconds: 500));

  print('Запуск приложения...');

  try {
    // Загружаем переменные окружения напрямую из системного окружения
    final supabaseUrl = Platform.environment['SUPABASE_URL'] ?? '';
    final supabaseAnonKey = Platform.environment['SUPABASE_ANON_KEY'] ?? '';

    print(
        'Получены переменные окружения: URL=${supabaseUrl.isNotEmpty}, KEY=${supabaseAnonKey.isNotEmpty}');

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      print('Ошибка: SUPABASE_URL или SUPABASE_ANON_KEY не установлены');
      runApp(const ErrorApp(
          message: 'Ошибка конфигурации: отсутствуют ключи Supabase'));
      return;
    }

    // Инициализируем Supabase
    print('Инициализация Supabase...');
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    print('Supabase инициализирован успешно');

    // Добавляем дополнительную задержку для полной инициализации
    await Future.delayed(const Duration(milliseconds: 1000));

    runApp(const MyApp());
  } catch (e, stack) {
    print('Ошибка инициализации приложения: $e');
    print('Стек вызовов: $stack');
    runApp(ErrorApp(message: 'Ошибка инициализации: ${e.toString()}'));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('Построение MyApp...');

    return MaterialApp(
      title: 'Мой чат',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const AppLoader(),
    );
  }
}

class AppLoader extends StatefulWidget {
  const AppLoader({super.key});

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  String _status = 'Инициализация...';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() => _status = 'Проверка подключения...');

      // Проверяем подключение к Supabase
      final supabase = Supabase.instance.client;
      final response = await supabase.from('messages').select().limit(1);

      setState(() => _status = 'Подключение установлено');

      await Future.delayed(const Duration(milliseconds: 500));

      // Переходим к выбору пользователя
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const UserSelectionScreen()),
      );
    } catch (e) {
      setState(() => _status = 'Ошибка подключения: $e');
      print('Ошибка подключения к Supabase: $e');

      // Показываем экран ошибки через 3 секунды
      await Future.delayed(const Duration(seconds: 3));

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (context) => ErrorApp(message: 'Ошибка подключения: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(_status),
          ],
        ),
      ),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String message;

  const ErrorApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 50, color: Colors.red),
                const SizedBox(height: 20),
                const Text(
                  'Ошибка приложения',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    // Попробовать перезапустить приложение
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (context) => const AppLoader()),
                    );
                  },
                  child: const Text('Попробовать снова'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Остальной код (UserSelectionScreen, ChatScreen и т.д.) остается без изменений
