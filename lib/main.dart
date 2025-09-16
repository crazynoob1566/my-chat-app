import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load();

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Мой чат',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
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
                  builder: (context) =>
                      ChatScreen(currentUserId: 'user1', friendId: 'user2'),
                ),
              ),
              child: const Text('Я - User 1'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ChatScreen(currentUserId: 'user2', friendId: 'user1'),
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

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  late final SupabaseClient _supabase;
  late final RealtimeChannel _messagesChannel;

  List<Map<String, dynamic>> _messages = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    _messagesChannel = _supabase.channel('messages');
    _loadMessages();
    _subscribeToMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final response = await _supabase
          .from('messages')
          .select()
          .or(
            'sender_id.eq.${widget.currentUserId},receiver_id.eq.${widget.currentUserId}',
          )
          .order('created_at', ascending: true);

      setState(() {
        _messages = List<Map<String, dynamic>>.from(response);
      });
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
          callback: (payload) {
            final newMessage = payload.newRecord;
            if ((newMessage['sender_id'] == widget.currentUserId &&
                    newMessage['receiver_id'] == widget.friendId) ||
                (newMessage['sender_id'] == widget.friendId &&
                    newMessage['receiver_id'] == widget.currentUserId)) {
              setState(() {
                _messages.add(newMessage);
              });
            }
          },
        )
        .subscribe();
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
      print('Ошибка отправки сообщения: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка отправки: $e')));
    } finally {
      setState(() {
        _isSending = false;
      });
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
              builder: (context) => const UserSelectionScreen(),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('Нет сообщений'))
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

  @override
  void dispose() {
    _messageController.dispose();
    _supabase.removeChannel(_messagesChannel);
    super.dispose();
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
              style: TextStyle(color: isMe ? Colors.white : Colors.black),
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
