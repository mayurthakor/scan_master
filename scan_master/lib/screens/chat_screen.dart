// lib/screens/chat_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
// REMOVED: import 'package:scan_master/services/api_service.dart';
import 'package:share_plus/share_plus.dart';

class ChatScreen extends StatefulWidget {
  final String documentId;
  final String initialSummary;

  const ChatScreen({
    super.key,
    required this.documentId,
    required this.initialSummary,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // REMOVED: final ApiService _apiService = ApiService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _addInitialSummaryToChat();
  }

  Future<void> _addInitialSummaryToChat() async {
    final chatMessagesRef = FirebaseFirestore.instance
        .collection('files')
        .doc(widget.documentId)
        .collection('chat_messages');

    final existingMessages = await chatMessagesRef.limit(1).get();

    if (existingMessages.docs.isEmpty) {
      await chatMessagesRef.add({
        'text':
            "${widget.initialSummary}\n\nI am ready for your questions. Ask me anything.",
        'sender': 'ai',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  // --- MODIFIED FUNCTION ---
  void _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    _textController.clear();

    final messagesRef = FirebaseFirestore.instance
        .collection('files')
        .doc(widget.documentId)
        .collection('chat_messages');

    await messagesRef.add({
      'text': text,
      'sender': 'user',
      'timestamp': FieldValue.serverTimestamp(),
    });

    _scrollToBottom();

    try {
      // Direct call to Firebase Functions
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('chat-with-document');
      final response = await callable.call<Map<String, dynamic>>({
        'documentId': widget.documentId,
        'question': text,
      });
      final answer = response.data['answer'] as String?;

      if (answer == null) {
        throw Exception('Failed to get answer from response.');
      }

      await messagesRef.add({
        'text': answer,
        'sender': 'ai',
        'timestamp': FieldValue.serverTimestamp(),
        'feedback': null,
      });
    } catch (e) {
      await messagesRef.add({
        'text': "Sorry, I encountered an error. Please try again. ($e)",
        'sender': 'ai',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  // --- NEW FUNCTION ---
  Future<void> _saveFeedback(String messageId, String feedback) async {
    try {
      await FirebaseFirestore.instance
          .collection('files')
          .doc(widget.documentId)
          .collection('chat_messages')
          .doc(messageId)
          .update({'feedback': feedback});
    } catch (e) {
      print("Failed to save feedback: $e");
    }
  }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Chat Assistant'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('files')
                  .doc(widget.documentId)
                  .collection('chat_messages')
                  .orderBy('timestamp')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("Ask a question to begin."));
                }

                final messages = snapshot.data!.docs;
                _scrollToBottom();

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8.0),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final data = message.data() as Map<String, dynamic>;
                    final bool isUserMessage = data['sender'] == 'user';

                    return _buildMessageBubble(
                      messageId: message.id,
                      text: data['text'],
                      isUserMessage: isUserMessage,
                      feedback: data['feedback'],
                    );
                  },
                );
              },
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          _buildTextInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required String messageId,
    required String text,
    required bool isUserMessage,
    String? feedback,
  }) {
    final alignment =
        isUserMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = isUserMessage
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.secondaryContainer;
    final textColor = isUserMessage
        ? Colors.white
        : Theme.of(context).colorScheme.onSecondaryContainer;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(text, style: TextStyle(color: textColor)),
          ),
          if (!isUserMessage)
            Padding(
              padding: const EdgeInsets.only(top: 4.0, left: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share, size: 16),
                    onPressed: () => Share.share(text),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.thumb_up,
                      size: 16,
                      color: feedback == 'liked' ? Colors.blue : null,
                    ),
                    onPressed: feedback != null ? null : () =>
                      _saveFeedback(messageId, 'liked'), // MODIFIED
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.thumb_down,
                      size: 16,
                      color: feedback == 'disliked' ? Colors.red : null,
                    ),
                    onPressed: feedback != null ? null : () =>
                      _saveFeedback(messageId, 'disliked'), // MODIFIED
                  ),
                ],
              ),
            )
        ],
      ),
    );
  }

  Widget _buildTextInputArea() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                hintText: 'Ask a follow-up question...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _isLoading ? null : _sendMessage,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}