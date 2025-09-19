import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

// Конфигурационные константы - замените на ваши реальные значения
const String _defaultSupabaseUrl = 'https://tpwjupuaflpswdvudexi.supabase.co';
const String _defaultSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRwd2p1cHVhZmxwc3dkdnVkZXhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgwMzk2NDAsImV4cCI6MjA3MzYxNTY0MH0.hKSB7GHtUWS1Jyyo5pGiCe2wX2OBvyywbbG7kjo62fo';
const String _supabaseStorageBucket =
    'chat-images'; // Создайте этот бакет в Supabase Storage

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
  final ImagePicker _imagePicker = ImagePicker();

  List<Map<String, dynamic>> _messages = [];
  bool _isSending = false;
  bool _isUploadingImage = false;
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
                final messageContent = newMessage['type'] == 'image'
                    ? '📷 Фото'
                    : newMessage['content'];
                _showNotification(
                  'Новое сообщение',
                  messageContent,
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
        'type': 'text',
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

  Future<void> _sendImageMessage(String imageUrl) async {
    try {
      await _supabase.from('messages').insert({
        'sender_id': widget.currentUserId,
        'receiver_id': widget.friendId,
        'content': imageUrl,
        'type': 'image',
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки изображения: $e')),
      );
    }
  }

  Future<String?> _uploadImage(XFile imageFile) async {
    try {
      setState(() {
        _isUploadingImage = true;
      });

      // Читаем файл
      final bytes = await imageFile.readAsBytes();

      // Определяем MIME-тип
      final mimeType = lookupMimeType(imageFile.path);

      // Генерируем уникальное имя файла
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = imageFile.path.split('.').last;
      final fileName = '${widget.currentUserId}_$timestamp.$fileExtension';

      // Загружаем в Supabase Storage с указанием MIME-типа
      await _supabase.storage.from('chat-images').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: mimeType ?? 'image/jpeg',
            ),
          );

      // Получаем публичный URL
      final imageUrl =
          _supabase.storage.from('chat-images').getPublicUrl(fileName);

      return imageUrl;
    } catch (e) {
      if (!mounted) return null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки изображения: $e')),
      );
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? imageFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1440,
      );

      if (imageFile != null) {
        final imageUrl = await _uploadImage(imageFile);
        if (imageUrl != null) {
          await _sendImageMessage(imageUrl);
        }
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка выбора изображения: $e')),
      );
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? imageFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1440,
      );

      if (imageFile != null) {
        final imageUrl = await _uploadImage(imageFile);
        if (imageUrl != null) {
          await _sendImageMessage(imageUrl);
        }
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка съемки фото: $e')),
      );
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isMe = message['sender_id'] == widget.currentUserId;
    final isImage = message['type'] == 'image';

    if (isImage) {
      // Сообщение с изображением
      return ImageMessageBubble(
        imageUrl: message['content'],
        isMe: isMe,
        time: DateFormat('HH:mm').format(
          DateTime.parse(message['created_at']).toLocal(),
        ),
      );
    } else {
      // Текстовое сообщение
      return MessageBubble(
        message: message['content'],
        isMe: isMe,
        time: DateFormat('HH:mm').format(
          DateTime.parse(message['created_at']).toLocal(),
        ),
      );
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
                      return _buildMessageBubble(message);
                    },
                  ),
          ),
          if (_isUploadingImage) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo_library),
                  onPressed: _pickImage,
                  tooltip: 'Выбрать из галереи',
                ),
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  onPressed: _takePhoto,
                  tooltip: 'Сделать фото',
                ),
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

class ImageMessageBubble extends StatelessWidget {
  final String imageUrl;
  final bool isMe;
  final String time;

  const ImageMessageBubble({
    super.key,
    required this.imageUrl,
    required this.isMe,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 250),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                placeholder: (context, url) => Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey[200],
                  child: const Icon(Icons.error),
                ),
                fit: BoxFit.cover,
                width: 200,
                height: 200,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                time,
                style: TextStyle(
                  fontSize: 10,
                  color: isMe ? Colors.white70 : Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
