import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Конфигурационные константы - замените на ваши реальные значения
const String _defaultSupabaseUrl = 'https://tpwjupuaflpswdvudexi.supabase.co';
const String _defaultSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRwd2p1cHVhZmxwc3dkdnVkZXhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgwMzk2NDAsImV4cCI6MjA3MzYxNTY0MH0.hKSB7GHtUWS1Jyyo5pGiCe2wX2OBvyywbbG7kjo62fo';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация уведомлений
  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings();
  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );

  await notificationsPlugin.initialize(initSettings);

  String supabaseUrl;
  String supabaseAnonKey;

  // Пытаемся получить переменные из окружения (для Codemagic)
  supabaseUrl = Platform.environment['SUPABASE_URL'] ?? '';
  supabaseAnonKey = Platform.environment['SUPABASE_ANON_KEY'] ?? '';

  // Если в окружении нет переменных, используем значения по умолчанию
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    supabaseUrl = _defaultSupabaseUrl;
    supabaseAnonKey = _defaultSupabaseAnonKey;
  }

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    runApp(const ErrorApp(
        message: 'Ошибка конфигурации: отсутствуют ключи Supabase'));
    return;
  }

  try {
    // Инициализируем Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  } catch (e) {
    runApp(ErrorApp(message: 'Ошибка инициализации Supabase: $e'));
    return;
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Мой чат',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const UserSelectionScreen(),
    );
  }
}

class UserSelectionScreen extends StatelessWidget {
  const UserSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Выберите пользователя')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChatScreen(
                      currentUserId: 'user1', friendId: 'user2'),
                ),
              ),
              child: const Text('Я - User 1'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChatScreen(
                      currentUserId: 'user2', friendId: 'user1'),
                ),
              ),
              child: const Text('Я - User 2'),
            ),
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
          child: Text(message),
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String currentUserId;
  final String friendId;

  const ChatScreen({
    super.key,
    required this.currentUserId,
    required this.friendId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  late final SupabaseClient _supabase;
  late final RealtimeChannel _messagesChannel;
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  List<Map<String, dynamic>> _messages = [];
  bool _isSending = false;
  Timer? _backgroundTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _supabase = Supabase.instance.client;
    _messagesChannel = _supabase.channel('messages');
    _initializeNotifications();
    _loadMessages();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _stopBackgroundTask();
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _supabase.removeChannel(_messagesChannel);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Приложение переходит в фоновый режим
      _unsubscribeFromMessages();
      _startBackgroundTask();
    } else if (state == AppLifecycleState.resumed) {
      // Приложение возвращается на передний план
      _stopBackgroundTask();
      _loadMessages();
      _subscribeToMessages();
    }
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(settings);
  }

  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'channel_id',
      'Channel Name',
      importance: Importance.max,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      0,
      title,
      body,
      details,
    );
  }

  Future<void> _saveMessagesLocally() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString('cached_messages', json.encode(_messages));
  }

  Future<void> _loadCachedMessages() async {
    final SharedPreferences prefs = await _prefs;
    final String? cachedMessages = prefs.getString('cached_messages');
    if (cachedMessages != null) {
      setState(() {
        _messages =
            List<Map<String, dynamic>>.from(json.decode(cachedMessages));
      });
    }
  }

  Future<void> _loadMessages() async {
    try {
      // Сначала загружаем кэшированные сообщения
      await _loadCachedMessages();

      // Затем загружаем новые сообщения с сервера
      final response = await _supabase
          .from('messages')
          .select()
          .or('sender_id.eq.${widget.currentUserId},receiver_id.eq.${widget.currentUserId}')
          .order('created_at', ascending: true);

      setState(() {
        _messages = List<Map<String, dynamic>>.from(response);
      });

      // Сохраняем сообщения локально
      await _saveMessagesLocally();
    } catch (e) {
      // В случае ошибки используем кэшированные сообщения
      print('Ошибка загрузки сообщений: $e');
    }
  }

  void _subscribeToMessages() {
    _messagesChannel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            final newMessage = payload.newRecord;
            if ((newMessage['sender_id'] == widget.currentUserId &&
                    newMessage['receiver_id'] == widget.friendId) ||
                (newMessage['sender_id'] == widget.friendId &&
                    newMessage['receiver_id'] == widget.currentUserId)) {
              setState(() {
                _messages.add(newMessage);
              });

              // Сохраняем обновленный список сообщений локально
              await _saveMessagesLocally();

              // Показываем уведомление для новых сообщений
              if (newMessage['sender_id'] != widget.currentUserId) {
                _showNotification(
                  'Новое сообщение',
                  newMessage['content'],
                );
              }
            }
          },
        )
        .subscribe();
  }

  void _unsubscribeFromMessages() {
    _supabase.removeChannel(_messagesChannel);
  }

  void _startBackgroundTask() {
    _backgroundTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) async {
      await _checkForNewMessages();
    });
  }

  void _stopBackgroundTask() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  }

  Future<void> _checkForNewMessages() async {
    try {
      final lastMessageId = _messages.isNotEmpty ? _messages.last['id'] : 0;

      final response = await _supabase
          .from('messages')
          .select()
          .gt('id', lastMessageId)
          .or('sender_id.eq.${widget.currentUserId},receiver_id.eq.${widget.currentUserId}')
          .order('created_at', ascending: true);

      if (response.isNotEmpty) {
        // Есть новые сообщения
        setState(() {
          _messages.addAll(List<Map<String, dynamic>>.from(response));
        });

        await _saveMessagesLocally();

        // Показываем уведомление
        _showNotification(
          'Новые сообщения',
          'У вас ${response.length} новых сообщений',
        );
      }
    } catch (e) {
      print('Ошибка проверки новых сообщений: $e');
    }
  }

  Future<void> _sendMessage() async {
    final String content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      await _supabase.from('messages').insert({
        'sender_id': widget.currentUserId,
        'receiver_id': widget.friendId,
        'content': content,
      });

      _messageController.clear();
    } catch (e) {
      // Проверяем, что виджет все еще смонтирован перед использованием контекста
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки: $e')),
      );
    } finally {
      // Проверяем, что виджет все еще смонтирован перед вызовом setState
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Чат с ${widget.friendId}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) => const UserSelectionScreen()),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text('Нет сообщений'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isMe = message['sender_id'] == widget.currentUserId;

                      return MessageBubble(
                        message: message['content'],
                        isMe: isMe,
                        time: DateFormat('HH:mm').format(
                          DateTime.parse(message['created_at']).toLocal(),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Введите сообщение...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                _isSending
                    ? const CircularProgressIndicator()
                    : CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: _sendMessage,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final String message;
  final bool isMe;
  final String time;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white70 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
