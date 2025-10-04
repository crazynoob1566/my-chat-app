import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

class TelegramService {
  // Замените на ваш токен бота (тот же, что в Render)
  static const String botToken =
      '7874269168:AAHEXfWcrscD0JVN1SPIjt5k8Du-ScRxwmc';

  // ДОБАВЬТЕ ЭТУ СТРОКУ - username вашего бота
  static const String botUsername =
      'my_chat_notifications_bot'; // Замените на реальный username

  // Отправка уведомления через Telegram
  static Future<bool> sendTelegramNotification({
    required String toUserId,
    required String fromUserId,
    required String fromUserName,
    required String messageText,
  }) async {
    try {
      print('📱 Отправка Telegram уведомления пользователю: $toUserId');

      // Получаем chat_id пользователя из базы
      final supabase = Supabase.instance.client;
      final userResponse = await supabase
          .from('users')
          .select('telegram_chat_id, name')
          .eq('id', toUserId)
          .single();

      if (userResponse['telegram_chat_id'] == null) {
        print('❌ У пользователя $toUserId нет привязанного Telegram');
        return false;
      }

      String chatId = userResponse['telegram_chat_id'];
      String userName = userResponse['name'] ?? 'Пользователь';

      print('📱 Отправляем сообщение в Telegram chat_id: $chatId');

      // Формируем красивое сообщение
      String telegramMessage = '''
💬 *Новое сообщение в чате*

*От:* $fromUserName
*Для:* $userName

*Сообщение:*
$messageText

---
_Отправлено из Мой Чат App_
''';

      // Отправляем через Telegram API
      final response = await http.post(
        Uri.parse('https://api.telegram.org/bot$botToken/sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'chat_id': chatId,
          'text': telegramMessage,
          'parse_mode': 'Markdown',
          'reply_markup': {
            'inline_keyboard': [
              [
                {
                  'text': '💌 Ответить',
                  'url':
                      'https://t.me/$botUsername' // Используем константу botUsername
                }
              ]
            ]
          }
        }),
      );

      print('📱 Ответ от Telegram API: ${response.statusCode}');

      if (response.statusCode == 200) {
        print('✅ Telegram уведомление отправлено!');
        return true;
      } else {
        final errorData = json.decode(response.body);
        print('❌ Ошибка Telegram: ${errorData['description']}');
        return false;
      }
    } catch (e) {
      print('❌ Ошибка отправки Telegram уведомления: $e');
      return false;
    }
  }

  // Генерация кода для привязки
  static String generateBindCode() {
    final random = Random();
    return 'CHAT${random.nextInt(9000) + 1000}'; // Генерирует CHAT1234
  }

  // Сохранение кода привязки в базу
  static Future<void> saveBindCode(String userId, String code) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('telegram_bind_codes').upsert({
        'user_id': userId,
        'bind_code': code,
        'created_at': DateTime.now().toIso8601String(),
        'expires_at':
            DateTime.now().add(Duration(minutes: 10)).toIso8601String(),
      });
      print('✅ Код привязки сохранен: $code для пользователя $userId');
    } catch (e) {
      print('❌ Ошибка сохранения кода привязки: $e');
    }
  }

  // Получение user_id по коду привязки
  static Future<String?> getUserIdByBindCode(String code) async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('telegram_bind_codes')
          .select('user_id')
          .eq('bind_code', code)
          .gt('expires_at', DateTime.now().toIso8601String())
          .single();

      return response['user_id'];
    } catch (e) {
      print('❌ Ошибка получения user_id по коду: $e');
      return null;
    }
  }

  // Проверка статуса привязки
  static Future<Map<String, dynamic>> getTelegramStatus(String userId) async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('users')
          .select('telegram_chat_id, name')
          .eq('id', userId)
          .single();

      final bool isBound = response['telegram_chat_id'] != null;

      return {
        'isBound': isBound,
        'chatId': response['telegram_chat_id'],
        'userName': response['name'],
      };
    } catch (e) {
      print('❌ Ошибка проверки статуса Telegram: $e');
      return {'isBound': false, 'chatId': null, 'userName': null};
    }
  }

  // Отправка тестового сообщения
  static Future<bool> sendTestMessage(String chatId) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.telegram.org/bot$botToken/sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'chat_id': chatId,
          'text':
              '✅ *Тестовое сообщение*\n\nВаш Telegram успешно привязан к чат приложению! Теперь вы будете получать уведомления о новых сообщениях.',
          'parse_mode': 'Markdown',
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('❌ Ошибка отправки тестового сообщения: $e');
      return false;
    }
  }
}
