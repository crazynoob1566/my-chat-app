import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'telegram_service.dart';

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
  final SupabaseClient _supabase = Supabase.instance.client;

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
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '❌ Привязка не обнаружена. Проверьте код и попробуйте снова.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _unbindTelegram() async {
    try {
      await _supabase
          .from('users')
          .update({'telegram_chat_id': null}).eq('id', widget.userId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Telegram отвязан'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadStatus();
      await _generateBindCode();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Ошибка: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('📋 Скопировано в буфер обмена')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Привязка Telegram'),
        backgroundColor: Colors.blue[700],
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
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
                    elevation: 4,
                    child: Container(
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
                            size: 32,
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _status['isBound'] == true
                                      ? '✅ Telegram привязан'
                                      : '🔗 Telegram не привязан',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_status['isBound'] == true) ...[
                                  SizedBox(height: 4),
                                  Text(
                                    'Вы будете получать уведомления о новых сообщениях',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24),

                  if (_status['isBound'] == true) ...[
                    // Уже привязан
                    Text(
                      'Настройки Telegram:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),

                    ListTile(
                      leading: Icon(Icons.person, color: Colors.blue),
                      title: Text('Привязанный аккаунт'),
                      subtitle: Text(_status['userName'] ?? 'Пользователь'),
                    ),

                    ListTile(
                      leading: Icon(Icons.chat, color: Colors.green),
                      title: Text('Chat ID'),
                      subtitle: Text(
                        _status['chatId'] ?? 'Не установлен',
                        style: TextStyle(fontFamily: 'Monospace'),
                      ),
                    ),

                    SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _unbindTelegram,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 50),
                      ),
                      child: Text('Отвязать Telegram'),
                    ),
                  ] else ...[
                    // Инструкция по привязке
                    Text(
                      'Как привязать Telegram:',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 20),

                    _buildStep(1, 'Откройте Telegram и найдите бота:'),
                    SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.telegram, color: Colors.blue),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '@${TelegramService.botUsername}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.content_copy),
                            onPressed: () => _copyToClipboard(
                                '@${TelegramService.botUsername}'),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 20),
                    _buildStep(2, 'Отправьте боту команду:'),
                    SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.code, color: Colors.green),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '/bind $_bindCode',
                              style: TextStyle(
                                fontFamily: 'Monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.content_copy),
                            onPressed: () =>
                                _copyToClipboard('/bind $_bindCode'),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 20),
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
                    Divider(),
                    SizedBox(height: 16),

                    Container(
                      padding: EdgeInsets.all(0), // УБРАН padding из Text
                      child: Text(
                        'Важная информация:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(0), // УБРАН padding из Text
                      child: Text(
                        '• Код действителен 10 минут\n• После привязки вы будете получать уведомления о новых сообщениях\n• Уведомления работают даже когда приложение закрыто',
                        style: TextStyle(
                          color: Colors.grey[600],
                        ),
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              '$number',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
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
