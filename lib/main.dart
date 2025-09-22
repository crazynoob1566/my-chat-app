import 'dart:io';
import 'dart:convert';
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
import 'package:photo_view/photo_view.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

// Конфигурационные константы - ЗАМЕНИТЕ НА ВАШИ РЕАЛЬНЫЕ ЗНАЧЕНИЯ
const String _defaultSupabaseUrl = 'https://tpwjupuaflpswdvudexi.supabase.co';
const String _defaultSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRwd2p1cHVhZmxwc3dkdnVkZXhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgwMzk2NDAsImV4cCI6MjA3MzYxNTY0MH0.hKSB7GHtUWS1Jyyo5pGiCe2wX2OBvyywbbG7kjo62fo';
const String _supabaseStorageBucket = 'chat-images';

// Цвета Telegram
const Color telegramBlue = Color(0xFF0088CC);
const Color telegramGrey = Color(0xFFE8E8E8);
const Color telegramDarkGrey = Color(0xFFA0A0A0);
const Color telegramLightBlue = Color(0xFF5EC2FF);
const Color telegramBackground = Color(0xFFF5F5F5);

// Пароль для доступа к приложению (по умолчанию)
const String _defaultPassword = '1234';

// Информация о пользователях
final Map<String, Map<String, dynamic>> users = {
  'user1': {
    'name': 'Labooba',
    'avatarColor': Color(0xFF6B4D8C),
    'avatarText': 'L',
    'imageAsset': 'assets/images/user1_avatar.png',
  },
  'user2': {
    'name': 'Babula',
    'avatarColor': Color(0xFF2A6EBB),
    'avatarText': 'B',
    'imageAsset': 'assets/images/user2_avatar.png',
  },
};

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

  supabaseUrl = Platform.environment['SUPABASE_URL'] ?? '';
  supabaseAnonKey = Platform.environment['SUPABASE_ANON_KEY'] ?? '';

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
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
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
      title: 'Telegram Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const PasswordScreen(),
    );
  }
}

// Экран ввода пароля (оставляем без изменений)
class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  String _storedPassword = '';
  bool _isFirstLaunch = true;
  bool _obscurePassword = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadPassword();
  }

  Future<void> _loadPassword() async {
    final SharedPreferences prefs = await _prefs;
    setState(() {
      _storedPassword = prefs.getString('app_password') ?? '';
      _isFirstLaunch = _storedPassword.isEmpty;
    });
  }

  Future<void> _savePassword(String password) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString('app_password', password);
    setState(() {
      _storedPassword = password;
      _isFirstLaunch = false;
    });
  }

  void _checkPassword() {
    final enteredPassword = _passwordController.text.trim();
    if (_isFirstLaunch) {
      if (enteredPassword.length >= 4) {
        _savePassword(enteredPassword);
        _navigateToUserSelection();
      } else {
        setState(() {
          _errorMessage = 'Пароль должен содержать не менее 4 символов';
        });
      }
    } else {
      if (enteredPassword == _storedPassword) {
        _navigateToUserSelection();
      } else {
        setState(() {
          _errorMessage = 'Неверный пароль';
          _passwordController.clear();
        });
      }
    }
  }

  void _navigateToUserSelection() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const UserSelectionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: telegramBlue,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [telegramBlue, telegramLightBlue],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 80, color: Colors.white),
                  const SizedBox(height: 20),
                  Text(
                    _isFirstLaunch ? 'Установите пароль' : 'Введите пароль',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Пароль',
                      hintStyle: const TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.2),
                      prefixIcon: const Icon(Icons.lock, color: Colors.white),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.white),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    onSubmitted: (_) => _checkPassword(),
                  ),
                  if (_errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_errorMessage,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 14)),
                    ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _checkPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: telegramBlue,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(_isFirstLaunch ? 'Установить' : 'Войти',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Экран выбора пользователя (оставляем без изменений)
class UserSelectionScreen extends StatefulWidget {
  const UserSelectionScreen({super.key});

  @override
  State<UserSelectionScreen> createState() => _UserSelectionScreenState();
}

class _UserSelectionScreenState extends State<UserSelectionScreen> {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  void _showChangePasswordDialog() {
    final TextEditingController oldPasswordController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController =
        TextEditingController();
    bool obscureOldPassword = true;
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;
    String errorMessage = '';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Смена пароля'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: oldPasswordController,
                  obscureText: obscureOldPassword,
                  decoration: InputDecoration(
                    labelText: 'Старый пароль',
                    suffixIcon: IconButton(
                      icon: Icon(obscureOldPassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () => setState(
                          () => obscureOldPassword = !obscureOldPassword),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPasswordController,
                  obscureText: obscureNewPassword,
                  decoration: InputDecoration(
                    labelText: 'Новый пароль',
                    suffixIcon: IconButton(
                      icon: Icon(obscureNewPassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () => setState(
                          () => obscureNewPassword = !obscureNewPassword),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Подтвердите новый пароль',
                    suffixIcon: IconButton(
                      icon: Icon(obscureConfirmPassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () => setState(() =>
                          obscureConfirmPassword = !obscureConfirmPassword),
                    ),
                  ),
                ),
                if (errorMessage.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(errorMessage,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 14))),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена')),
              TextButton(
                onPressed: () async {
                  final oldPassword = oldPasswordController.text.trim();
                  final newPassword = newPasswordController.text.trim();
                  final confirmPassword = confirmPasswordController.text.trim();

                  if (oldPassword.isEmpty ||
                      newPassword.isEmpty ||
                      confirmPassword.isEmpty) {
                    setState(() =>
                        errorMessage = 'Все поля обязательны для заполнения');
                    return;
                  }
                  if (newPassword.length < 4) {
                    setState(() => errorMessage =
                        'Новый пароль должен содержать не менее 4 символов');
                    return;
                  }
                  if (newPassword != confirmPassword) {
                    setState(() => errorMessage = 'Новые пароли не совпадают');
                    return;
                  }

                  final SharedPreferences prefs = await _prefs;
                  final storedPassword = prefs.getString('app_password') ?? '';
                  if (oldPassword != storedPassword) {
                    setState(() => errorMessage = 'Неверный старый пароль');
                    return;
                  }

                  await prefs.setString('app_password', newPassword);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Пароль успешно изменен')));
                },
                child: const Text('Сохранить'),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildClickableArea(String userId, String userName, Rect area) {
    return Positioned(
      left: area.left,
      top: area.top,
      width: area.width,
      height: area.height,
      child: GestureDetector(
        onTap: () {
          final friendId = userId == 'user1' ? 'user2' : 'user1';
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    ChatScreen(currentUserId: userId, friendId: friendId)),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
          ),
          child: Center(
            child: AnimatedOpacity(
              opacity: 0.7,
              duration: const Duration(milliseconds: 300),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(userName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final laboobaArea = Rect.fromLTWH(
        screenSize.width * 0.1,
        screenSize.height * 0.4,
        screenSize.width * 0.35,
        screenSize.height * 0.4);
    final babulaArea = Rect.fromLTWH(
        screenSize.width * 0.55,
        screenSize.height * 0.4,
        screenSize.width * 0.35,
        screenSize.height * 0.4);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Выберите персонажа'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.purple.withOpacity(0.8),
                Colors.blue.withOpacity(0.8)
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.lock, color: Colors.white),
              onPressed: _showChangePasswordDialog,
              tooltip: 'Сменить пароль'),
          IconButton(
            icon: const Icon(Icons.lock_open, color: Colors.white),
            onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const PasswordScreen())),
            tooltip: 'Сменить пользователя',
          ),
        ],
      ),
      body: Stack(children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            image: DecorationImage(
                image:
                    AssetImage('assets/images/user_selection_background.jpg'),
                fit: BoxFit.cover),
          ),
        ),
        Container(color: Colors.black.withOpacity(0.3)),
        _buildClickableArea('user1', 'Labooba', laboobaArea),
        _buildClickableArea('user2', 'Babula', babulaArea),
        Positioned(
          top: screenSize.height * 0.1,
          left: 0,
          right: 0,
          child: Column(children: [
            Text('КТО ВЫ?',
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                          blurRadius: 10,
                          color: Colors.purple,
                          offset: const Offset(0, 0)),
                      Shadow(
                          blurRadius: 20,
                          color: Colors.blue,
                          offset: const Offset(0, 0)),
                    ])),
            const SizedBox(height: 20),
            Text('Выберите своего персонажа для входа в чат',
                style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                    shadows: [
                      const Shadow(
                          blurRadius: 5,
                          color: Colors.black,
                          offset: Offset(1, 1))
                    ])),
          ]),
        ),
        Positioned(
          bottom: screenSize.height * 0.05,
          left: 0,
          right: 0,
          child: Column(children: [
            Text('Нажмите на персонажа для входа',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                    fontStyle: FontStyle.italic)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _buildCharacterHint('Labooba', Colors.purple),
              _buildCharacterHint('Babula', Colors.blue),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _buildCharacterHint(String name, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
          color: color.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(name,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String message;
  const ErrorApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(body: Center(child: Text(message))),
    );
  }
}

// ОСНОВНОЙ ЭКРАН ЧАТА С ИНТЕРФЕЙСОМ TELEGRAM
class ChatScreen extends StatefulWidget {
  final String currentUserId;
  final String friendId;

  const ChatScreen(
      {super.key, required this.currentUserId, required this.friendId});

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
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _isSending = false;
  bool _isUploadingImage = false;
  Timer? _backgroundTimer;
  bool _showEmojiKeyboard = false;

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
    _scrollController.dispose();
    _supabase.removeChannel(_messagesChannel);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _unsubscribeFromMessages();
      _startBackgroundTask();
    } else if (state == AppLifecycleState.resumed) {
      _stopBackgroundTask();
      _loadMessages();
      _subscribeToMessages();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      final double position = _scrollController.position.maxScrollExtent;
      if (position > 0) {
        _scrollController.animateTo(
          position,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } else {
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();
    const InitializationSettings settings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);
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
    const NotificationDetails details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _notificationsPlugin.show(0, title, body, details);
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
      await _loadCachedMessages();
      final response = await _supabase
          .from('messages')
          .select()
          .or('sender_id.eq.${widget.currentUserId},receiver_id.eq.${widget.currentUserId}')
          .order('created_at', ascending: true);

      setState(() {
        _messages = List<Map<String, dynamic>>.from(response);
      });
      await _saveMessagesLocally();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
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
              await _saveMessagesLocally();
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _scrollToBottom());
              if (newMessage['sender_id'] != widget.currentUserId) {
                final messageContent = newMessage['type'] == 'image'
                    ? '📷 Фото'
                    : newMessage['content'];
                _showNotification(
                    'Новое сообщение от ${users[newMessage['sender_id']]!['name']}',
                    messageContent);
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
        setState(() {
          _messages.addAll(List<Map<String, dynamic>>.from(response));
        });
        await _saveMessagesLocally();
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        _showNotification(
            'Новые сообщения', 'У вас ${response.length} новых сообщений');
      }
    } catch (e) {
      print('Ошибка проверки новых сообщений: $e');
    }
  }

  Future<void> _sendMessage() async {
    final String content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSending = true);

    try {
      await _supabase.from('messages').insert({
        'sender_id': widget.currentUserId,
        'receiver_id': widget.friendId,
        'content': content,
        'type': 'text',
      });
      _messageController.clear();
      setState(() => _showEmojiKeyboard = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка отправки: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
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
          SnackBar(content: Text('Ошибка отправки изображения: $e')));
    }
  }

  Future<String?> _uploadImage(XFile imageFile) async {
    try {
      setState(() => _isUploadingImage = true);
      final bytes = await imageFile.readAsBytes();
      final mimeType = lookupMimeType(imageFile.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = imageFile.path.split('.').last;
      final fileName = '${widget.currentUserId}_$timestamp.$fileExtension';

      await _supabase.storage.from('chat-images').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: mimeType ?? 'image/jpeg'),
          );

      final imageUrl =
          _supabase.storage.from('chat-images').getPublicUrl(fileName);
      return imageUrl;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки изображения: $e')));
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
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
        if (imageUrl != null) await _sendImageMessage(imageUrl);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора изображения: $e')));
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
        if (imageUrl != null) await _sendImageMessage(imageUrl);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка съемки фото: $e')));
    }
  }

  Future<void> _deleteMessage(int messageId) async {
    try {
      await _supabase.from('messages').delete().eq('id', messageId);
      setState(
          () => _messages.removeWhere((message) => message['id'] == messageId));
      await _saveMessagesLocally();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Сообщение удалено')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления сообщения: $e')));
    }
  }

  Future<void> _clearAllMessages() async {
    try {
      final List<int> messageIds = _messages
          .where((message) =>
              (message['sender_id'] == widget.currentUserId &&
                  message['receiver_id'] == widget.friendId) ||
              (message['sender_id'] == widget.friendId &&
                  message['receiver_id'] == widget.currentUserId))
          .map((message) => message['id'] as int)
          .toList();

      for (int id in messageIds) {
        await _supabase.from('messages').delete().eq('id', id);
      }
      setState(() => _messages.clear());
      await _saveMessagesLocally();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Весь чат очищен')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка очистки чата: $e')));
    }
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Очистить весь чат?'),
        content: const Text('Все сообщения будут удалены безвозвратно.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _clearAllMessages();
              },
              child: const Text('Очистить')),
        ],
      ),
    );
  }

  void _showDeleteMessageDialog(int messageId) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        content: const Text('Это сообщение будет удалено безвозвратно.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteMessage(messageId);
              },
              child: const Text('Удалить')),
        ],
      ),
    );
  }

  // Функция для группировки сообщений (Telegram-style)
  bool _shouldShowAvatar(int index) {
    if (index >= _messages.length - 1) return true;
    final currentMessage = _messages[index];
    final nextMessage = _messages[index + 1];
    return currentMessage['sender_id'] != nextMessage['sender_id'];
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, int index) {
    final isMe = message['sender_id'] == widget.currentUserId;
    final isImage = message['type'] == 'image';
    final userInfo = users[message['sender_id']] ??
        {
          'name': message['sender_id'],
          'avatarColor': Colors.grey,
          'avatarText': '?'
        };
    final showAvatar = !isMe && _shouldShowAvatar(index);

    if (isImage) {
      return TelegramImageMessageBubble(
        imageUrl: message['content'],
        isMe: isMe,
        time: DateFormat('HH:mm')
            .format(DateTime.parse(message['created_at']).toLocal()),
        userInfo: userInfo,
        showAvatar: showAvatar,
        onDelete: () => _showDeleteMessageDialog(message['id']),
        canDelete: isMe,
      );
    } else {
      return TelegramMessageBubble(
        message: message['content'],
        isMe: isMe,
        time: DateFormat('HH:mm')
            .format(DateTime.parse(message['created_at']).toLocal()),
        userInfo: userInfo,
        showAvatar: showAvatar,
        onDelete: () => _showDeleteMessageDialog(message['id']),
        canDelete: isMe,
      );
    }
  }

  Widget _buildEmojiKeyboard() {
    if (!_showEmojiKeyboard) return const SizedBox.shrink();

    return Container(
      height: 250,
      color: Colors.white,
      child: GridView.count(
        crossAxisCount: 8,
        children: List.generate(40, (index) {
          final emojis = [
            '😀',
            '😂',
            '🥰',
            '😎',
            '🤔',
            '🙄',
            '😴',
            '🥳',
            '😡',
            '🤯',
            '🤢',
            '👋',
            '👍',
            '👏',
            '🙏',
            '💪',
            '🐶',
            '🐱',
            '🐭',
            '🐹',
            '🐰',
            '🦊',
            '🐻',
            '🐼',
            '🎈',
            '🎉',
            '🎂',
            '🍕',
            '🍔',
            '🍟',
            '🌭',
            '🍿',
            '🥓',
            '🥩',
            '🍗',
            '🍖',
            '🍘',
            '🍙',
            '🍚',
            '🍛'
          ];
          return GestureDetector(
            onTap: () {
              _messageController.text += emojis[index];
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Text(emojis[index], style: const TextStyle(fontSize: 24)),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final friendInfo = users[widget.friendId] ??
        {
          'name': widget.friendId,
          'avatarColor': Colors.grey,
          'avatarText': '?'
        };

    return Scaffold(
      backgroundColor: telegramBackground,
      appBar: AppBar(
        title: Row(children: [
          CircleAvatar(
              backgroundColor: friendInfo['avatarColor'],
              child: Text(friendInfo['avatarText'],
                  style: const TextStyle(color: Colors.white))),
          const SizedBox(width: 12),
          Text('${friendInfo['name']}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w500)),
          const Spacer(),
          const Icon(Icons.circle, color: Colors.green, size: 12),
          const SizedBox(width: 4),
          const Text('online',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
        backgroundColor: telegramBlue,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (context) => const UserSelectionScreen())),
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.videocam, color: Colors.white),
              onPressed: () {},
              tooltip: 'Видеозвонок'),
          IconButton(
              icon: const Icon(Icons.call, color: Colors.white),
              onPressed: () {},
              tooltip: 'Аудиозвонок'),
          IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: () {},
              tooltip: 'Еще'),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            // Фоновый узор Telegram
            Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(
                      'assets/telegram_pattern.png'), // Добавьте текстуру Telegram
                  fit: BoxFit.cover,
                  opacity: 0.05,
                ),
              ),
            ),
            _messages.isEmpty
                ? const Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 80, color: telegramDarkGrey),
                          SizedBox(height: 16),
                          Text('Нет сообщений',
                              style: TextStyle(
                                  color: telegramDarkGrey, fontSize: 18)),
                          Text('Начните общение первым!',
                              style: TextStyle(color: telegramDarkGrey)),
                        ]),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        _buildMessageBubble(_messages[index], index),
                  ),
            if (_isUploadingImage)
              const Center(
                  child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(telegramBlue))),
          ]),
        ),
        _buildEmojiKeyboard(),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2))
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(children: [
            IconButton(
              icon: Icon(
                  _showEmojiKeyboard ? Icons.keyboard : Icons.emoji_emotions,
                  color: telegramBlue),
              onPressed: () =>
                  setState(() => _showEmojiKeyboard = !_showEmojiKeyboard),
              tooltip: 'Эмодзи',
            ),
            IconButton(
                icon: const Icon(Icons.photo_library, color: telegramBlue),
                onPressed: _pickImage,
                tooltip: 'Галерея'),
            IconButton(
                icon: const Icon(Icons.camera_alt, color: telegramBlue),
                onPressed: _takePhoto,
                tooltip: 'Камера'),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: telegramGrey,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Сообщение...',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.attach_file,
                          color: telegramDarkGrey),
                      onPressed: () {},
                      tooltip: 'Прикрепить файл',
                    ),
                  ),
                  maxLines: 5,
                  minLines: 1,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _isSending
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                          color: telegramBlue, shape: BoxShape.circle),
                      child:
                          const Icon(Icons.send, color: Colors.white, size: 20),
                    ),
                    onPressed: _sendMessage,
                    tooltip: 'Отправить',
                  ),
          ]),
        ),
      ]),
    );
  }
}

// СТИЛЬ СООБЩЕНИЙ TELEGRAM
class TelegramMessageBubble extends StatelessWidget {
  final String message;
  final bool isMe;
  final String time;
  final Map<String, dynamic> userInfo;
  final bool showAvatar;
  final VoidCallback onDelete;
  final bool canDelete;

  const TelegramMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.time,
    required this.userInfo,
    required this.showAvatar,
    required this.onDelete,
    required this.canDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe && showAvatar)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: CircleAvatar(
                backgroundColor: userInfo['avatarColor'],
                radius: 16,
                child: Text(userInfo['avatarText'],
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            )
          else if (!isMe)
            const SizedBox(width: 32),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe && showAvatar)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 2),
                    child: Text(userInfo['name'],
                        style: const TextStyle(
                            color: telegramDarkGrey,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ),
                GestureDetector(
                  onLongPress: canDelete ? onDelete : null,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMe ? telegramBlue : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: isMe
                            ? const Radius.circular(12)
                            : const Radius.circular(4),
                        bottomRight: isMe
                            ? const Radius.circular(4)
                            : const Radius.circular(12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message,
                            style: TextStyle(
                                color: isMe ? Colors.white : Colors.black,
                                fontSize: 16)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(time,
                                style: TextStyle(
                                    color: isMe
                                        ? Colors.white70
                                        : telegramDarkGrey,
                                    fontSize: 12)),
                            if (isMe) const SizedBox(width: 4),
                            if (isMe)
                              const Icon(Icons.done_all,
                                  color: Colors.white70, size: 14),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class TelegramImageMessageBubble extends StatelessWidget {
  final String imageUrl;
  final bool isMe;
  final String time;
  final Map<String, dynamic> userInfo;
  final bool showAvatar;
  final VoidCallback onDelete;
  final bool canDelete;

  const TelegramImageMessageBubble({
    super.key,
    required this.imageUrl,
    required this.isMe,
    required this.time,
    required this.userInfo,
    required this.showAvatar,
    required this.onDelete,
    required this.canDelete,
  });

  void _showFullScreenImage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (context) => FullScreenImageScreen(imageUrl: imageUrl)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe && showAvatar)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: CircleAvatar(
                backgroundColor: userInfo['avatarColor'],
                radius: 16,
                child: Text(userInfo['avatarText'],
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            )
          else if (!isMe)
            const SizedBox(width: 32),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe && showAvatar)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 2),
                    child: Text(userInfo['name'],
                        style: const TextStyle(
                            color: telegramDarkGrey,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ),
                GestureDetector(
                  onLongPress: canDelete ? onDelete : null,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 280),
                    decoration: BoxDecoration(
                      color: isMe ? telegramBlue : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: isMe
                            ? const Radius.circular(12)
                            : const Radius.circular(4),
                        bottomRight: isMe
                            ? const Radius.circular(4)
                            : const Radius.circular(12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => _showFullScreenImage(context),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                            child: Stack(
                              children: [
                                Container(
                                  width: 280,
                                  height: 200,
                                  color: telegramGrey,
                                  child: const Center(
                                      child: CircularProgressIndicator()),
                                ),
                                CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  width: 280,
                                  height: 200,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                      color: telegramGrey,
                                      child: const Center(
                                          child: CircularProgressIndicator())),
                                  errorWidget: (context, url, error) =>
                                      Container(
                                          color: telegramGrey,
                                          child: const Icon(Icons.error)),
                                ),
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        borderRadius: BorderRadius.circular(4)),
                                    child: const Icon(Icons.zoom_out_map,
                                        color: Colors.white, size: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(time,
                                  style: TextStyle(
                                      color: isMe
                                          ? Colors.white70
                                          : telegramDarkGrey,
                                      fontSize: 12)),
                              if (isMe) const SizedBox(width: 4),
                              if (isMe)
                                const Icon(Icons.done_all,
                                    color: Colors.white70, size: 14),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// Полноэкранный просмотр изображения (оставляем без изменений)
class FullScreenImageScreen extends StatefulWidget {
  final String imageUrl;
  const FullScreenImageScreen({super.key, required this.imageUrl});

  @override
  State<FullScreenImageScreen> createState() => _FullScreenImageScreenState();
}

class _FullScreenImageScreenState extends State<FullScreenImageScreen> {
  bool _isSaving = false;

  Future<void> _saveImage() async {
    setState(() => _isSaving = true);
    try {
      var status = await Permission.photos.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Необходимо разрешение для сохранения изображений')));
        return;
      }
      final response = await http.get(Uri.parse(widget.imageUrl));
      final result = await ImageGallerySaver.saveImage(
        Uint8List.fromList(response.bodyBytes),
        quality: 100,
        name: "chat_image_${DateTime.now().millisecondsSinceEpoch}",
      );
      if (result['isSuccess']) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Изображение сохранено в галерею')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось сохранить изображение')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          PhotoView(
            imageProvider: NetworkImage(widget.imageUrl),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 4,
            heroAttributes: PhotoViewHeroAttributes(tag: widget.imageUrl),
            loadingBuilder: (context, event) => Center(
                child: Container(
                    width: 100,
                    height: 100,
                    child: const CircularProgressIndicator())),
            errorBuilder: (context, error, stackTrace) => Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, color: Colors.white, size: 50),
                    const SizedBox(height: 16),
                    const Text('Не удалось загрузить изображение',
                        style: TextStyle(color: Colors.white)),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Назад',
                            style: TextStyle(color: Colors.white))),
                  ]),
            ),
          ),
          Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop())),
          Positioned(
            top: 16,
            right: 16,
            child: _isSaving
                ? const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
                : IconButton(
                    icon: const Icon(Icons.download, color: Colors.white),
                    onPressed: _saveImage),
          ),
        ]),
      ),
    );
  }
}
