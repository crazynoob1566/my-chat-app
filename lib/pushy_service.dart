import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushyService {
  static const String pushyApiKey =
      '71c1296829765c1250f2ff61f49225c393913d6a131e63719ff4726f3d0a5a70';

  // Инициализация Pushy (без SDK - используем HTTP подход)
  static Future<String?> initializePushy(String userId) async {
    try {
      print('🚀 Инициализация Pushy для пользователя: $userId');

      // Генерируем или получаем существующий токен
      final prefs = await SharedPreferences.getInstance();
      String? deviceToken = prefs.getString('pushy_token_$userId');

      if (deviceToken == null) {
        // Генерируем уникальный токен
        deviceToken = _generateDeviceToken(userId); // Передаем userId
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

  // Генерация уникального токена устройства - ИСПРАВЛЕННАЯ ВЕРСИЯ
  static String _generateDeviceToken(String userId) {
    // Добавляем параметр userId
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(1000000);
    return 'pushy_${userId}_${timestamp}_${random}';
  }

  // Сохранение токена в Supabase
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

  // Обработка входящих пуш-уведомлений
  static void handlePushNotification(Map<String, dynamic> data) {
    print('📨 Получено пуш-уведомление: $data');

    String title = data['title'] ?? 'Новое сообщение';
    String message = data['message'] ?? 'У вас новое сообщение в чате';

    // Здесь можно добавить дополнительную логику при получении уведомления
    print('🔔 Уведомление: $title - $message');
  }

  // Отправка пуш-уведомления другому пользователю
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
      final response = await supabase
          .from('user_tokens')
          .select('pushy_token')
          .eq('user_id', toUserId);

      if (response.isEmpty) {
        print('❌ У пользователя $toUserId нет pushy токена');
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
            'type': 'new_message'
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
}
