import 'package:flutter/material.dart';
import 'package:supabase/supabase.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
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
import 'package:flutter/services.dart';
import 'telegram_bind_screen.dart'; // Добавьте эту строку в импорты

// ==================== PUSHY SERVICE (HTTP-ONLY) ====================
import 'dart:math';
import 'telegram_service.dart';

class PushyService {
  // ЗАМЕНИТЕ НА ВАШ SECRET API KEY ИЗ PUSHY DASHBOARD
  static const String pushyApiKey =
      '71c1296829765c1250f2ff61f49225c393913d6a131e63719ff4726f3d0a5a70';

  // Генерируем уникальный токен устройства
  static String _generateDeviceToken() {
    final random = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(64, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  static Future<String?> initializePushy(String userId) async {
    try {
      print('🚀 Инициализация Pushy для пользователя: $userId');

      // Генерируем или получаем существующий токен
      final prefs = await SharedPreferences.getInstance();
      String? deviceToken = prefs.getString('pushy_token_$userId');

      if (deviceToken == null) {
        deviceToken = _generateDeviceToken();
        await prefs.setString('pushy_token_$userId', deviceToken);
        print('✅ Сгенерирован новый токен устройства: $deviceToken');
      } else {
        print('✅ Используем существующий токен: $deviceToken');
      }

      // Сохраняем токен в Supabase
      await _savePushyTokenToSupabase(userId, deviceToken);

      return deviceToken;
    } catch (e) {
      print('❌ Ошибка инициализации Pushy: $e');
      return null;
    }
  }

  static Future<void> _savePushyTokenToSupabase(
      String userId, String token) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('user_tokens').upsert({
        'user_id': userId,
        'pushy_token': token,
        'updated_at': DateTime.now().toIso8601String(),
      });
      print('✅ Токен сохранен в Supabase');
    } catch (e) {
      print('❌ Ошибка сохранения токена в Supabase: $e');
    }
  }

  static Future<bool> sendPushNotification({
    required String toUserId,
    required String fromUserId,
    required String fromUserName,
    required String messageText,
  }) async {
    try {
      print('📤 Отправка пуш-уведомления пользователю: $toUserId');

      // Получаем токен получателя из Supabase
      final supabase = Supabase.instance.client;

      // ИСПРАВЛЕНИЕ: Убираем .execute()
      final response = await supabase
          .from('user_tokens')
          .select('pushy_token')
          .eq('user_id', toUserId);

      if (response.isEmpty) {
        print('❌ Пользователь $toUserId не найден в таблице токенов');
        return false;
      }

      String recipientToken = response.first['pushy_token'];
      print('📱 Токен получателя: $recipientToken');

      // Подготавливаем текст уведомления
      String notificationBody = messageText.length > 50
          ? '${messageText.substring(0, 50)}...'
          : messageText;

      // Отправляем пуш через Pushy API
      final pushResponse = await http.post(
        Uri.parse('https://api.pushy.me/push?api_key=$pushyApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'to': recipientToken,
          'data': {
            'title': '💬 Новое сообщение',
            'message': '$fromUserName: $messageText',
            'from_user_id': fromUserId,
            'to_user_id': toUserId,
            'type': 'new_message',
            'timestamp': DateTime.now().toIso8601String(),
          },
          'notification': {
            'title': '💬 $fromUserName',
            'body': notificationBody,
            'badge': 1,
            'sound': 'default'
          },
          'time_to_live': 3600, // 1 час
        }),
      );

      print('📤 Ответ от Pushy API: ${pushResponse.statusCode}');

      if (pushResponse.statusCode == 200) {
        print('✅ Пуш-уведомление успешно отправлено');
        return true;
      } else {
        print(
            '❌ Ошибка отправки пуша: ${pushResponse.statusCode} - ${pushResponse.body}');
        return false;
      }
    } catch (e) {
      print('❌ Ошибка отправки пуш-уведомления: $e');
      return false;
    }
  }

  // Метод для обработки входящих уведомлений (если нужно)
  static void handleIncomingNotification(Map<String, dynamic> data) {
    print('📨 Получено пуш-уведомление: $data');

    String title = data['title'] ?? 'Новое сообщение';
    String message = data['message'] ?? 'У вас новое сообщение в чате';

    // Показываем локальное уведомление
    _showLocalNotification(title, message);
  }

  static Future<void> _showLocalNotification(
      String title, String message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'pushy_channel',
      'Pushy Notifications',
      channelDescription: 'Канал для push-уведомлений от Pushy',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const DarwinNotificationDetails iosPlatformChannelSpecifics =
        DarwinNotificationDetails();

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iosPlatformChannelSpecifics,
    );

    await notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      message,
      platformChannelSpecifics,
    );
  }
}

// ==================== КОНЕЦ PUSHY SERVICE ====================

// Глобальная переменная для уведомлений
FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Конфигурационные константы
const String _defaultSupabaseUrl = 'https://tpwjupuaflpswdvudexi.supabase.co';
const String _defaultSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRwd2p1cHVhZmxwc3dkdnVkZXhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgwMzk2NDAsImV4cCI6MjA3MzYxNTY0MH0.hKSB7GHtUWS1Jyyo5pGiCe2wX2OBvyywbbG7kjo62fo';

// Цвета
const Color blue700 = Color(0xFF1976D2);
const Color blue800 = Color(0xFF1565C0);
const Color green500 = Color(0xFF4CAF50);
const Color grey200 = Color(0xFFEEEEEE);
const Color grey600 = Color(0xFF757575);

// Пароль для доступа к приложению
const String _defaultPassword = '1234';

// Информация о пользователях
final Map<String, Map<String, dynamic>> users = {
  'user1': {
    'name': 'Labooba',
    'avatarColor': Colors.purple,
    'avatarText': 'L',
    'imageAsset': 'assets/images/user1_avatar.png',
  },
  'user2': {
    'name': 'Babula',
    'avatarColor': const Color.fromARGB(255, 6, 33, 59),
    'avatarText': 'B',
    'imageAsset': 'assets/images/user2_avatar.png',
  },
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация уведомлений
  await _initializeNotifications();

  String supabaseUrl = _defaultSupabaseUrl;
  String supabaseAnonKey = _defaultSupabaseAnonKey;

  try {
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

Future<void> _initializeNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );

  await notificationsPlugin.initialize(initSettings);
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
      home: const PasswordScreen(),
    );
  }
}

// Экран привязки Telegram
class TelegramBindScreen extends StatefulWidget {
  final String userId;

  const TelegramBindScreen({super.key, required this.userId});

  @override
  State<TelegramBindScreen> createState() => _TelegramBindScreenState();
}

class _TelegramBindScreenState extends State<TelegramBindScreen> {
  String _bindCode = '';
  bool _isLoading = true;
  Map<String, dynamic> _status = {};

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _generateBindCode();
  }

  Future<void> _loadStatus() async {
    final status = await TelegramService.getTelegramStatus(widget.userId);
    setState(() {
      _status = status;
      _isLoading = false;
    });
  }

  Future<void> _generateBindCode() async {
    final code = TelegramService.generateBindCode();
    setState(() {
      _bindCode = code;
    });
    await TelegramService.saveBindCode(widget.userId, code);
  }

  Future<void> _checkBinding() async {
    setState(() {
      _isLoading = true;
    });

    // Даем время боту обработать команду
    await Future.delayed(Duration(seconds: 3));

    await _loadStatus();

    if (_status['isBound'] == true) {
      // Отправляем тестовое сообщение
      await TelegramService.sendTestMessage(_status['chatId']);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Telegram успешно привязан!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _unbindTelegram() async {
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('users')
          .update({'telegram_chat_id': null}).eq('id', widget.userId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Telegram отвязан')),
      );

      await _loadStatus();
      await _generateBindCode();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Ошибка: $e')),
      );
    }
  }

  void _copyToClipboard(String text) {
    // Импортируйте package:flutter/services.dart
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('📋 Код скопирован')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Привязка Telegram'),
        backgroundColor: blue700,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Статус
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(
                            _status['isBound'] == true
                                ? Icons.check_circle
                                : Icons.link_off,
                            color: _status['isBound'] == true
                                ? Colors.green
                                : Colors.orange,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _status['isBound'] == true
                                  ? '✅ Telegram привязан'
                                  : '🔗 Telegram не привязан',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 20),

                  if (_status['isBound'] == true) ...[
                    // Уже привязан
                    Text(
                      'Ваш Telegram успешно привязан!',
                      style: TextStyle(fontSize: 16),
                    ),
                    SizedBox(height: 10),
                    Container(
                      // ИСПРАВЛЕННЫЙ ВИДЖЕТ
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Chat ID: ${_status['chatId']}',
                        style: TextStyle(
                          fontFamily: 'Monospace',
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _unbindTelegram,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: Text('Отвязать Telegram'),
                    ),
                  ] else ...[
                    // остальной код без изменений...
                    // Инструкция по привязке
                    Text(
                      'Чтобы привязать Telegram:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),

                    _buildStep(1, 'Откройте Telegram и найдите бота:'),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '@${TelegramService.botUsername}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Spacer(),
                          IconButton(
                            icon: Icon(Icons.content_copy),
                            onPressed: () => _copyToClipboard(
                                '@${TelegramService.botUsername}'),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 16),
                    _buildStep(2, 'Отправьте боту команду:'),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '/bind $_bindCode',
                            style: TextStyle(
                              fontFamily: 'Monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Spacer(),
                          IconButton(
                            icon: Icon(Icons.content_copy),
                            onPressed: () =>
                                _copyToClipboard('/bind $_bindCode'),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 16),
                    _buildStep(3, 'Нажмите кнопку проверки:'),
                    SizedBox(height: 16),

                    ElevatedButton.icon(
                      onPressed: _checkBinding,
                      icon: Icon(Icons.refresh),
                      label: Text('Проверить привязку'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 50),
                      ),
                    ),

                    SizedBox(height: 20),
                    Text(
                      'Код действителен 10 минут',
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStep(int number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              '$number',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }
}

// Экран ввода пароля
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
              Color(0xFFf093fb),
              Color(0xFFf5576c),
            ],
            stops: [0.1, 0.4, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Декоративные элементы фона
            Positioned(
              top: -50,
              right: -30,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -80,
              left: -40,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              top: 100,
              left: 20,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),

            Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Анимированная иконка
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.lock_outline_rounded,
                          size: 60,
                          color: Color(0xFF667eea),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Заголовок
                      Text(
                        _isFirstLaunch
                            ? 'Создайте пароль'
                            : '𝕊𝕒𝕝𝕒𝕞 𝕡𝕠𝕡𝕠𝕝𝕒𝕞',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        _isFirstLaunch ? 'Для защиты ваших сообщений' : '',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Поле ввода пароля
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.black87,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter your password',
                            hintStyle: TextStyle(
                              color: Colors.grey[600],
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                            prefixIcon: Icon(
                              Icons.lock_outline_rounded,
                              color: Colors.grey[600],
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: Colors.grey[600],
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          onSubmitted: (_) => _checkPassword(),
                        ),
                      ),

                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 30),

                      // Кнопка входа
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _checkPassword,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF667eea),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 18,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 5,
                            shadowColor: Colors.black.withOpacity(0.3),
                          ),
                          child: Text(
                            _isFirstLaunch ? 'Создать пароль' : '𝕃𝕠𝕘 𝕚𝕟',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Дополнительная информация
                      Text(
                        _isFirstLaunch
                            ? 'Пароль будет храниться локально на устройстве'
                            : '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UserSelectionScreen extends StatefulWidget {
  const UserSelectionScreen({super.key});

  @override
  State<UserSelectionScreen> createState() => _UserSelectionScreenState();
}

class _UserSelectionScreenState extends State<UserSelectionScreen> {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final TextEditingController currentPasswordController =
            TextEditingController();
        final TextEditingController newPasswordController =
            TextEditingController();

        return AlertDialog(
          title: const Text('Сменить пароль'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Текущий пароль',
                ),
              ),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Новый пароль',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () async {
                final SharedPreferences prefs = await _prefs;
                final String storedPassword =
                    prefs.getString('app_password') ?? '';

                if (currentPasswordController.text == storedPassword) {
                  if (newPasswordController.text.length >= 4) {
                    await prefs.setString(
                        'app_password', newPasswordController.text);
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Пароль успешно изменен')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Новый пароль должен содержать не менее 4 символов')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Неверный текущий пароль')),
                  );
                }
              },
              child: const Text('Сменить'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Выберите пользователя',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.lock, color: Colors.white),
            onPressed: _showChangePasswordDialog,
            tooltip: 'Сменить пароль',
          ),
          IconButton(
            icon: const Icon(Icons.lock_open, color: Colors.white),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const PasswordScreen()),
              );
            },
            tooltip: 'Сменить пользователя',
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Фоновое изображение с фигурками
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image:
                    AssetImage('assets/images/user_selection_background.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),

          // Затемнение для лучшей видимости текста
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.black.withOpacity(0.5),
                ],
              ),
            ),
          ),

          // Кнопка для Labooba (синяя фигурка) - левая сторона
          Positioned(
            left: MediaQuery.of(context).size.width * 0.084,
            top: MediaQuery.of(context).size.height * 0.4,
            child: GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      currentUserId: 'user1',
                      friendId: 'user2',
                    ),
                  ),
                );
              },
              child: Container(
                width: 150,
                height: 247,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.8),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.6),
                      blurRadius: 15,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Container(
                    color: Colors.transparent, // Прозрачная область для нажатия
                  ),
                ),
              ),
            ),
          ),

          // Кнопка для Babula (розовая фигурка) - правая сторона
          Positioned(
            right: MediaQuery.of(context).size.width * 0.065,
            top: MediaQuery.of(context).size.height * 0.4,
            child: GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      currentUserId: 'user2',
                      friendId: 'user1',
                    ),
                  ),
                );
              },
              child: Container(
                width: 156,
                height: 247,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.8),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.pink.withOpacity(0.6),
                      blurRadius: 15,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Container(
                    color: Colors.transparent, // Прозрачная область для нажатия
                  ),
                ),
              ),
            ),
          ),

          // Подсказки для пользователя
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.15,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const Text(
                  'Нажмите на вашу фигурку',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        blurRadius: 10,
                        color: Colors.black,
                        offset: Offset(2, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Labooba',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.pink,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Babula',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  final ImagePicker _imagePicker = ImagePicker();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _isSending = false;
  bool _isUploadingImage = false;

  // Переменные для индикатора набора сообщения
  bool _isFriendTyping = false;
  Timer? _typingTimer;
  Timer? _typingDebounceTimer;
  DateTime _lastTypingTime = DateTime.now();
  bool _isTypingFeatureAvailable = true;

  // Переменные для ответов на сообщения
  Map<String, dynamic>? _replyingToMessage;
  final FocusNode _messageFocusNode = FocusNode();

  // Polling таймеры
  Timer? _pollingTimer;
  int _lastUpdateTime = DateTime.now().millisecondsSinceEpoch;

  // PUSHY переменные
  String? _pushyToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _supabase = Supabase.instance.client;

    print('🚀 Чат инициализирован для пользователя: ${widget.currentUserId}');

    // Инициализируем Pushy
    _initializePushy();

    _loadMessages();
    _startPolling();
    _startMessageStatusChecker();
  }

  Future<void> _initializePushy() async {
    try {
      String? token = await PushyService.initializePushy(widget.currentUserId);

      if (token != null) {
        setState(() {
          _pushyToken = token;
        });

        print('✅ Pushy успешно инициализирован. Токен: $token');
      } else {
        print('❌ Не удалось инициализировать Pushy');
      }
    } catch (e) {
      print('❌ Ошибка инициализации Pushy: $e');
    }
  }

  Future<void> _savePushyToken(String token) async {
    try {
      await _supabase.from('user_tokens').upsert({
        'user_id': widget.currentUserId,
        'pushy_token': token,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('❌ Ошибка сохранения pushy токена: $e');
    }
  }

  Future<void> _sendPushToFriend(String messageText) async {
    try {
      bool success = await PushyService.sendPushNotification(
        toUserId: widget.friendId,
        fromUserId: widget.currentUserId,
        fromUserName: users[widget.currentUserId]?['name'] ?? 'Пользователь',
        messageText: messageText,
      );

      if (success) {
        print('✅ Пуш-уведомление отправлено другу');
      } else {
        print('❌ Не удалось отправить пуш-уведомление');
      }
    } catch (e) {
      print('❌ Ошибка отправки пуша: $e');
    }
  }

  // ==================== ОСНОВНЫЕ МЕТОДЫ ЧАТА ====================

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        print('⏰ Таймер остановлен (widget не mounted)');
        timer.cancel();
        return;
      }

      await _checkForNewMessages();
    });
  }

  Future<void> _checkForNewMessages() async {
    try {
      final response = await _supabase
          .from('messages')
          .select()
          .order('created_at', ascending: false)
          .limit(20);

      final newMessages = response
          .where((serverMsg) =>
              !_messages.any((localMsg) => localMsg['id'] == serverMsg['id']))
          .toList();

      if (newMessages.isNotEmpty) {
        setState(() {
          _messages.addAll(newMessages);
          _messages.sort((a, b) => a['created_at'].compareTo(b['created_at']));
        });

        await _saveMessagesLocally();
        _scrollToBottom();
        await _markNewMessagesAsRead(newMessages);
      }

      await _updateMessageStatuses();
    } catch (e) {
      print('❌ Ошибка проверки новых сообщений: $e');
    }
  }

  Future<void> _sendTypingEvent(bool isTyping) async {
    if (!_isTypingFeatureAvailable) return;

    try {
      await _supabase.from('typing_indicators').upsert({
        'user_id': widget.currentUserId,
        'friend_id': widget.friendId,
        'is_typing': isTyping,
        'last_updated': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Ошибка отправки события набора: $e');
    }
  }

  void _startTyping() {
    _lastTypingTime = DateTime.now();
    _sendTypingEvent(true);
  }

  void _stopTyping() {
    _sendTypingEvent(false);
  }

  void _handleTyping() {
    _lastTypingTime = DateTime.now();

    _typingDebounceTimer?.cancel();
    _typingDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _startTyping();
    });

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (DateTime.now().difference(_lastTypingTime).inSeconds >= 2) {
        _stopTyping();
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _stopTyping();
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _typingDebounceTimer?.cancel();
    _messageFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _stopTyping();
    } else if (state == AppLifecycleState.resumed) {
      _checkForNewMessages();
      _updateMessageStatuses();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      final double position = _scrollController.position.maxScrollExtent;
      if (position > 0) {
        _scrollController.jumpTo(position);
      }
    }
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

      print('Загружено ${response.length} сообщений с сервера');

      if (response.isNotEmpty) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(response);
        });
      }

      await _saveMessagesLocally();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });

      final unreadIds = _getUnreadMessageIds();
      if (unreadIds.isNotEmpty) {
        await _markMessagesAsRead(unreadIds);
      }
    } catch (e) {
      print('Ошибка загрузки сообщений: $e');
    }
  }

  // Метод отправки сообщения с PUSHY
  Future<void> _sendMessage() async {
    final String content = _messageController.text.trim();
    if (content.isEmpty) return;

    _stopTyping();
    _typingDebounceTimer?.cancel();
    _typingTimer?.cancel();

    final tempMessage = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'sender_id': widget.currentUserId,
      'receiver_id': widget.friendId,
      'content': content,
      'type': 'text',
      'created_at': DateTime.now().toIso8601String(),
      'delivered_at': null,
      'read_at': null,
    };

    setState(() {
      _messages.add(tempMessage);
      _isSending = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    try {
      final messageData = {
        'sender_id': widget.currentUserId,
        'receiver_id': widget.friendId,
        'content': content,
        'type': 'text',
        'delivered_at': null,
        'read_at': null,
      };

      if (_replyingToMessage != null) {
        messageData['parent_message_id'] = _replyingToMessage!['id'];
        messageData['parent_message_content'] = _replyingToMessage!['content'];
        messageData['parent_sender_id'] = _replyingToMessage!['sender_id'];
      }

      final response =
          await _supabase.from('messages').insert(messageData).select();

      if (response != null && response.isNotEmpty) {
        final serverMessage = response.first;

        setState(() {
          final index =
              _messages.indexWhere((msg) => msg['id'] == tempMessage['id']);
          if (index != -1) {
            _messages[index] = serverMessage;
          }
        });

        _messageController.clear();
        _cancelReply();
        await _saveMessagesLocally();

        // ✅ ОТПРАВКА TELEGRAM УВЕДОМЛЕНИЯ
        print('📱 Отправка Telegram уведомления...');
        final telegramSent = await TelegramService.sendTelegramNotification(
          toUserId: widget.friendId,
          fromUserId: widget.currentUserId,
          fromUserName: users[widget.currentUserId]?['name'] ?? 'Пользователь',
          messageText: content,
        );

        if (telegramSent) {
          print('✅ Telegram уведомление отправлено!');
        } else {
          print('❌ Не удалось отправить Telegram уведомление');
        }

        print('💬 Сообщение отправлено + Telegram статус: $telegramSent');
      }
    } catch (e) {
      print('Ошибка отправки: $e');
      if (!mounted) return;

      setState(() {
        final index =
            _messages.indexWhere((msg) => msg['id'] == tempMessage['id']);
        if (index != -1) {
          _messages[index]['error'] = true;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // Метод отправки изображения с PUSHY
  Future<void> _sendImageMessage(String imageUrl) async {
    final tempMessage = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'sender_id': widget.currentUserId,
      'receiver_id': widget.friendId,
      'content': imageUrl,
      'type': 'image',
      'created_at': DateTime.now().toIso8601String(),
      'delivered_at': null,
      'read_at': null,
    };

    setState(() {
      _messages.add(tempMessage);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    try {
      final messageData = {
        'sender_id': widget.currentUserId,
        'receiver_id': widget.friendId,
        'content': imageUrl,
        'type': 'image',
        'delivered_at': null,
        'read_at': null,
      };

      if (_replyingToMessage != null) {
        messageData['parent_message_id'] = _replyingToMessage!['id'];
        messageData['parent_message_content'] = _replyingToMessage!['content'];
        messageData['parent_sender_id'] = _replyingToMessage!['sender_id'];
      }

      final response =
          await _supabase.from('messages').insert(messageData).select();

      if (response != null && response.isNotEmpty) {
        final serverMessage = response.first;

        setState(() {
          final index =
              _messages.indexWhere((msg) => msg['id'] == tempMessage['id']);
          if (index != -1) {
            _messages[index] = serverMessage;
          }
        });

        _cancelReply();
        await _saveMessagesLocally();

        // ОТПРАВЛЯЕМ PUSH УВЕДОМЛЕНИЕ ДРУГУ
        await _sendPushToFriend('📷 Фото');

        print('Изображение отправлено + пуш отправлен');
      }
    } catch (e) {
      print('Ошибка отправки изображения: $e');
      setState(() {
        final index =
            _messages.indexWhere((msg) => msg['id'] == tempMessage['id']);
        if (index != -1) {
          _messages[index]['error'] = true;
        }
      });
    }
  }

  Future<String?> _uploadImage(XFile imageFile) async {
    try {
      setState(() {
        _isUploadingImage = true;
      });

      final bytes = await imageFile.readAsBytes();
      final mimeType = lookupMimeType(imageFile.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = imageFile.path.split('.').last;
      final fileName = '${widget.currentUserId}_$timestamp.$fileExtension';

      await _supabase.storage.from('chat-images').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: mimeType ?? 'image/jpeg',
            ),
          );

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

  // Функция удаления отдельного сообщения
  Future<void> _deleteMessage(int messageId) async {
    try {
      await _supabase.from('messages').delete().eq('id', messageId);

      setState(() {
        _messages.removeWhere((message) => message['id'] == messageId);
      });

      await _saveMessagesLocally();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сообщение удалено')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка удаления сообщения: $e')),
      );
    }
  }

  // Функция очистки всего чата
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

      setState(() {
        _messages.clear();
      });

      await _saveMessagesLocally();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Весь чат очищен')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка очистки чата: $e')),
      );
    }
  }

  // Диалог подтверждения удаления всего чата
  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Очистить весь чат?'),
          content: const Text('Все сообщения будут удалены безвозвратно.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _clearAllMessages();
              },
              child: const Text('Очистить'),
            ),
          ],
        );
      },
    );
  }

  // Диалог подтверждения удаления отдельного сообщения
  void _showDeleteMessageDialog(int messageId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Удалить сообщение?'),
          content: const Text('Это сообщение будет удалено безвозвратно.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteMessage(messageId);
              },
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _markMessagesAsRead(List<int> messageIds) async {
    if (messageIds.isEmpty) return;

    try {
      for (int id in messageIds) {
        await _supabase.from('messages').update({
          'read_at': DateTime.now().toIso8601String(),
        }).eq('id', id);
      }
    } catch (e) {
      print('Ошибка отметки прочтения: $e');
    }
  }

  Future<void> _markNewMessagesAsRead(
      List<Map<String, dynamic>> newMessages) async {
    try {
      final unreadFromFriend = newMessages
          .where((msg) =>
              msg['sender_id'] == widget.friendId &&
              msg['receiver_id'] == widget.currentUserId &&
              msg['read_at'] == null)
          .toList();

      if (unreadFromFriend.isNotEmpty) {
        final unreadIds =
            unreadFromFriend.map((msg) => msg['id'] as int).toList();

        await _markMessagesAsRead(unreadIds);

        for (int id in unreadIds) {
          final index = _messages.indexWhere((msg) => msg['id'] == id);
          if (index != -1) {
            setState(() {
              _messages[index]['read_at'] = DateTime.now().toIso8601String();
            });
          }
        }

        await _saveMessagesLocally();
      }
    } catch (e) {
      print('❌ Ошибка автоматической отметки прочтения: $e');
    }
  }

  // Метод проверки непрочитанных сообщений
  List<int> _getUnreadMessageIds() {
    return _messages
        .where((message) {
          return message['sender_id'] == widget.friendId &&
              message['receiver_id'] == widget.currentUserId &&
              message['read_at'] == null;
        })
        .map((message) => message['id'] as int)
        .toList();
  }

  // Упрощенная проверка статусов через polling
  Future<void> _updateMessageStatuses() async {
    try {
      final myUndeliveredMessages = _messages
          .where((msg) =>
              msg['sender_id'] == widget.currentUserId &&
              msg['delivered_at'] == null)
          .toList();

      if (myUndeliveredMessages.isEmpty) return;

      final messageIds =
          myUndeliveredMessages.map((msg) => msg['id'] as int).toList();

      final response = await _supabase
          .from('messages')
          .select('id, delivered_at, read_at')
          .inFilter('id', messageIds);

      bool hasUpdates = false;

      for (var serverMsg in response) {
        final localIndex =
            _messages.indexWhere((msg) => msg['id'] == serverMsg['id']);
        if (localIndex != -1) {
          final localMsg = _messages[localIndex];

          if (localMsg['delivered_at'] != serverMsg['delivered_at'] ||
              localMsg['read_at'] != serverMsg['read_at']) {
            setState(() {
              _messages[localIndex] = {
                ...localMsg,
                'delivered_at': serverMsg['delivered_at'],
                'read_at': serverMsg['read_at'],
              };
            });
            hasUpdates = true;
          }
        }
      }

      if (hasUpdates) {
        await _saveMessagesLocally();
      }
    } catch (e) {
      print('❌ Ошибка обновления статусов: $e');
    }
  }

  // Метод для периодической проверки статуса сообщений
  void _startMessageStatusChecker() {
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        await _updateMessageStatuses();
      } catch (e) {
        print('❌ Ошибка в таймере статусов: $e');
      }
    });
  }

  // Функция ответа на сообщение
  void _replyToMessage(Map<String, dynamic> message) {
    setState(() {
      _replyingToMessage = {
        'id': message['id'].toString(),
        'content': message['content']?.toString() ?? '',
        'sender_id': message['sender_id']?.toString() ?? '',
        'type': message['type']?.toString() ?? 'text',
      };
    });
    _messageFocusNode.requestFocus();
    _scrollToBottom();
  }

  // Метод отмены ответа на сообщение
  void _cancelReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isMe = message['sender_id'] == widget.currentUserId;
    final isImage = message['type'] == 'image';
    final userInfo = users[message['sender_id']] ??
        {
          'name': message['sender_id'],
          'avatarColor': Colors.grey,
          'avatarText': '?'
        };

    final hasParentMessage = message['parent_message_id'] != null;
    final deliveredAt = message['delivered_at'] != null
        ? DateTime.parse(message['delivered_at']).toLocal()
        : null;
    final readAt = message['read_at'] != null
        ? DateTime.parse(message['read_at']).toLocal()
        : null;

    return MessageBubble(
      message: message['content'] ?? '',
      isMe: isMe,
      time: DateFormat('HH:mm')
          .format(DateTime.parse(message['created_at']).toLocal()),
      userInfo: userInfo,
      onDelete: () => _showDeleteMessageDialog(message['id']),
      canDelete: isMe,
      onReply: () => _replyToMessage(message),
      isImage: isImage,
      parentMessage: hasParentMessage
          ? {
              'parent_message_id': message['parent_message_id'],
              'parent_message_content': message['parent_message_content'],
              'parent_sender_id': message['parent_sender_id'],
            }
          : null,
      users: users,
      deliveredAt: deliveredAt,
      readAt: readAt,
    );
  }

  Widget _buildTypingIndicator() {
    if (!_isTypingFeatureAvailable) return const SizedBox.shrink();
    if (!_isFriendTyping) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor:
                users[widget.friendId]?['avatarColor'] ?? Colors.grey,
            radius: 12,
            child: Text(
              users[widget.friendId]?['avatarText'] ?? '?',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _TypingDots(),
                const SizedBox(width: 4),
                Text(
                  '${users[widget.friendId]?['name'] ?? 'Собеседник'} печатает...',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    final isReplyingToMe =
        _replyingToMessage!['sender_id'] == widget.currentUserId;
    final replyUserInfo = users[_replyingToMessage!['sender_id']] ??
        {
          'name': _replyingToMessage!['sender_id'],
          'avatarColor': Colors.grey,
        };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.3),
        border: const Border(left: BorderSide(color: Colors.blue, width: 4)),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, color: Colors.blue[800], size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ответ на сообщение ${isReplyingToMe ? 'вам' : replyUserInfo['name']}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[900],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _replyingToMessage!['type'] == 'image'
                        ? '📷 Фото'
                        : (_replyingToMessage!['content'] ?? ''),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: Colors.blue[800]),
            onPressed: _cancelReply,
          ),
        ],
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
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: friendInfo['avatarColor'],
              child: Text(
                friendInfo['avatarText'],
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Чат с ${friendInfo['name']}',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        backgroundColor: blue700,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) => const UserSelectionScreen()),
          ),
        ),
        actions: [
          FutureBuilder<Map<String, dynamic>>(
            future: TelegramService.getTelegramStatus(widget.currentUserId),
            builder: (context, snapshot) {
              final isBound = snapshot.data?['isBound'] ?? false;
              return IconButton(
                icon: Icon(
                  Icons.telegram,
                  color: isBound ? Colors.blue[100] : Colors.grey[300],
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          TelegramBindScreen(userId: widget.currentUserId),
                    ),
                  );
                },
                tooltip: isBound ? 'Telegram привязан' : 'Привязать Telegram',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.white),
            onPressed: _showClearChatDialog,
            tooltip: 'Очистить чат',
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isTypingFeatureAvailable)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: Colors.orange.withOpacity(0.3),
              child: const Center(
                child: Text(
                  'Функция "печатает..." временно недоступна',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/chat_background.jpg'),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.black.withOpacity(0.8),
                        BlendMode.darken,
                      ),
                    ),
                  ),
                ),
                _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Нет сообщений',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(8),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message = _messages[index];
                                return _buildMessageBubble(message);
                              },
                            ),
                          ),
                          _buildTypingIndicator(),
                        ],
                      ),
              ],
            ),
          ),
          if (_isUploadingImage)
            const LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          _buildReplyPreview(),
          Container(
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.8)),
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo_library, color: Colors.blue),
                  onPressed: _pickImage,
                  tooltip: 'Галерея',
                ),
                IconButton(
                  icon: const Icon(Icons.camera_alt, color: Colors.blue),
                  onPressed: _takePhoto,
                  tooltip: 'Камера',
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _messageController,
                      focusNode: _messageFocusNode,
                      decoration: const InputDecoration(
                        hintText: 'Введите сообщение...',
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: (text) {
                        if (text.isNotEmpty) {
                          _handleTyping();
                        } else {
                          _stopTyping();
                          _typingDebounceTimer?.cancel();
                        }
                      },
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _isSending
                    ? const CircularProgressIndicator()
                    : IconButton(
                        icon: const Icon(Icons.send, color: Colors.blue),
                        onPressed: _sendMessage,
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
  final Map<String, dynamic> userInfo;
  final VoidCallback onDelete;
  final VoidCallback onReply;
  final bool canDelete;
  final bool isImage;
  final Map<String, dynamic>? parentMessage;
  final Map<String, Map<String, dynamic>> users;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.time,
    required this.userInfo,
    required this.onDelete,
    required this.onReply,
    required this.canDelete,
    this.isImage = false,
    this.parentMessage,
    required this.users,
    this.deliveredAt,
    this.readAt,
  });

  void _showMessageMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Ответить'),
                onTap: () {
                  Navigator.pop(context);
                  onReply();
                },
              ),
              if (canDelete)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Удалить',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    onDelete();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImagePreview(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FullScreenImageScreen(imageUrl: message),
          ),
        );
      },
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 200,
          maxHeight: 200,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[100],
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: message,
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey[300],
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey[300],
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, color: Colors.red),
                      SizedBox(height: 8),
                      Text('Ошибка загрузки', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.zoom_in,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParentMessagePreview() {
    if (parentMessage == null) return const SizedBox.shrink();

    final isParentMe = parentMessage!['parent_sender_id'] == userInfo['name'];
    final parentUserInfo = users[parentMessage!['parent_sender_id']] ??
        {
          'name': parentMessage!['parent_sender_id'],
          'avatarColor': Colors.grey,
        };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (isMe ? Colors.white : Colors.blue[50])!.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isMe ? Colors.grey[400]! : Colors.blue[300]!),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.reply,
                  size: 14, color: isMe ? Colors.grey[700] : Colors.blue[700]),
              const SizedBox(width: 6),
              Text(
                isParentMe ? 'Вы' : parentUserInfo['name'],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isMe ? Colors.grey[800] : Colors.blue[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            parentMessage!['parent_message_content'] ?? '',
            style: TextStyle(
              fontSize: 12,
              color: isMe ? Colors.grey[800] : Colors.blue[900],
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageStatus() {
    if (!isMe) return const SizedBox.shrink();

    final hasRead = readAt != null;
    final hasDelivered = deliveredAt != null || hasRead;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Время сообщения
        Text(
          time,
          style: TextStyle(
            fontSize: 10,
            color: isMe ? Colors.white.withOpacity(0.9) : Colors.grey[800],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 4),

        // Статус сообщения
        Icon(
          hasRead ? Icons.done_all : Icons.done,
          size: 12,
          color: hasRead ? Colors.blue[200] : Colors.white.withOpacity(0.7),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showMessageMenu(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CircleAvatar(
                  backgroundColor: userInfo['avatarColor'],
                  child: Text(
                    userInfo['avatarText'],
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            Flexible(
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, left: 12),
                      child: Text(
                        userInfo['name'],
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              blurRadius: 3.0,
                              color: Colors.black,
                              offset: Offset(1.0, 1.0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.blue.withOpacity(0.9)
                          : Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildParentMessagePreview(),
                        if (isImage) _buildImagePreview(context),
                        if (!isImage)
                          Text(
                            message,
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black,
                              fontSize: 16,
                            ),
                          ),
                        const SizedBox(height: 4),
                        // Заменяем старый виджет времени на новый с статусами
                        _buildMessageStatus(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isMe)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: CircleAvatar(
                  backgroundColor: Colors.blue,
                  radius: 12,
                  child: Text(
                    userInfo['avatarText'],
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
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
  final Map<String, dynamic> userInfo;
  final VoidCallback onDelete;
  final bool canDelete;

  const ImageMessageBubble({
    super.key,
    required this.imageUrl,
    required this.isMe,
    required this.time,
    required this.userInfo,
    required this.onDelete,
    required this.canDelete,
  });

  void _showFullScreenImage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullScreenImageScreen(imageUrl: imageUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                backgroundColor: userInfo['avatarColor'],
                child: Text(
                  userInfo['avatarText'],
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 12),
                    child: Text(
                      userInfo['name'],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            blurRadius: 3.0,
                            color: Colors.black,
                            offset: Offset(1.0, 1.0),
                          ),
                        ],
                      ),
                    ),
                  ),
                GestureDetector(
                  onLongPress: canDelete ? onDelete : null,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 250),
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.blue.withOpacity(0.9)
                          : Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () => _showFullScreenImage(context),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              children: [
                                Container(
                                  width: 200,
                                  height: 200,
                                  color: Colors.grey[200],
                                  child: const Center(
                                      child: CircularProgressIndicator()),
                                ),
                                CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  placeholder: (context, url) => Container(
                                    width: 200,
                                    height: 200,
                                    color: Colors.grey[200],
                                    child: const Center(
                                        child: CircularProgressIndicator()),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      Container(
                                    width: 200,
                                    height: 200,
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.error),
                                  ),
                                  fit: BoxFit.cover,
                                  width: 200,
                                  height: 200,
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.fullscreen,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
                ),
              ],
            ),
          ),
          if (isMe)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: CircleAvatar(
                backgroundColor: Colors.blue,
                radius: 12,
                child: Text(
                  userInfo['avatarText'],
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FullScreenImageScreen extends StatefulWidget {
  final String imageUrl;

  const FullScreenImageScreen({super.key, required this.imageUrl});

  @override
  State<FullScreenImageScreen> createState() => _FullScreenImageScreenState();
}

class _FullScreenImageScreenState extends State<FullScreenImageScreen> {
  bool _isSaving = false;

  Future<void> _saveImage() async {
    setState(() {
      _isSaving = true;
    });

    try {
      var status = await Permission.photos.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Необходимо разрешение для сохранения изображений')),
        );
        return;
      }

      final response = await http.get(Uri.parse(widget.imageUrl));
      final bytes = response.bodyBytes;

      final result = await ImageGallerySaver.saveImage(
        Uint8List.fromList(bytes),
        quality: 100,
        name: "chat_image_${DateTime.now().millisecondsSinceEpoch}",
      );

      if (result['isSuccess']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Изображение сохранено в галерею')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить изображение')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $e')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PhotoView(
              imageProvider: NetworkImage(widget.imageUrl),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4,
              heroAttributes: PhotoViewHeroAttributes(tag: widget.imageUrl),
              loadingBuilder: (context, event) => Center(
                child: Container(
                  width: 100,
                  height: 100,
                  child: const CircularProgressIndicator(),
                ),
              ),
              errorBuilder: (context, error, stackTrace) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, color: Colors.white, size: 50),
                    const SizedBox(height: 16),
                    const Text(
                      'Не удалось загрузить изображение',
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Назад',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: _isSaving
                  ? const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
                  : IconButton(
                      icon: const Icon(Icons.download, color: Colors.white),
                      onPressed: _saveImage,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingDots extends StatelessWidget {
  const _TypingDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: const BoxDecoration(
            color: Colors.black87,
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: const BoxDecoration(
            color: Colors.black87,
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: const BoxDecoration(
            color: Colors.black87,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}
