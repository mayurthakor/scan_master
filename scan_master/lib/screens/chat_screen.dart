// lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scan_master/services/api_service.dart';
import 'package:share_plus/share_plus.dart';

class ChatScreen extends StatefulWidget {
  final String documentId;
  final String fileName;
  final String initialSummary;

  const ChatScreen({
    super.key,
    required this.documentId,
    required this.fileName,
    required this.initialSummary,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasInitialMessage = false;

  @override
  void initState() {
    super.initState();
    _addInitialSummaryMessage();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _addInitialSummaryMessage() async {
    try {
      final chatMessagesRef = FirebaseFirestore.instance
          .collection('files')
          .doc(widget.documentId)
          .collection('chat_messages');

      // Check if we already have messages
      final existingMessages = await chatMessagesRef.limit(1).get();

      if (existingMessages.docs.isEmpty) {
        // Add initial AI message with summary
        await chatMessagesRef.add({
          'text': "📄 **Document Summary:**\n\n${widget.initialSummary}\n\n---\n\n💬 I'm ready to answer questions about this document. What would you like to know?",
          'sender': 'ai',
          'timestamp': FieldValue.serverTimestamp(),
          'isInitial': true,
        });
        
        setState(() {
          _hasInitialMessage = true;
        });
      }
    } catch (e) {
      print("Error adding initial message: $e");
    }
  }

  void _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isLoading) return;

    setState(() {
      _isLoading = true;
    });

    _textController.clear();

    final messagesRef = FirebaseFirestore.instance
        .collection('files')
        .doc(widget.documentId)
        .collection('chat_messages');

    try {
      // Add user's message
      await messagesRef.add({
        'text': text,
        'sender': 'user',
        'timestamp': FieldValue.serverTimestamp(),
      });

      _scrollToBottom();

      // Get AI response
      print("Asking question: $text");
      final answer = await _apiService.askQuestion(widget.documentId, text);
      print("Got answer: ${answer.substring(0, 50)}...");

      // Add AI response
      await messagesRef.add({
        'text': answer,
        'sender': 'ai',
        'timestamp': FieldValue.serverTimestamp(),
        'feedback': null,
      });

    } catch (e) {
      print("Error in chat: $e");
      // Add error message
      await messagesRef.add({
        'text': "Sorry, I encountered an error while processing your question. Please try again.\n\nError: ${e.toString()}",
        'sender': 'ai',
        'timestamp': FieldValue.serverTimestamp(),
        'isError': true,
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
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

  void _saveFeedback(String messageId, String feedback) async {
    try {
      await _apiService.saveFeedback(widget.documentId, messageId, feedback);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Thank you for your feedback!'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print("Error saving feedback: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chat with AI'),
            Text(
              widget.fileName,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') {
                _showClearChatDialog();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.clear_all),
                    SizedBox(width: 8),
                    Text('Clear Chat'),
                  ],
                ),
              ),
            ],
          ),
        ],
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
                if (snapshot.connectionState == ConnectionState.waiting && 
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text('Error loading chat: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, 
                               size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No messages yet.\nAsk a question to begin!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final messages = snapshot.data!.docs;
                
                // Auto-scroll when new messages arrive
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16.0),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final data = message.data() as Map<String, dynamic>;
                    final bool isUserMessage = data['sender'] == 'user';
                    final bool isInitial = data['isInitial'] ?? false;
                    final bool isError = data['isError'] ?? false;

                    return _buildMessageBubble(
                      messageId: message.id,
                      text: data['text'] ?? '',
                      isUserMessage: isUserMessage,
                      feedback: data['feedback'],
                      isInitial: isInitial,
                      isError: isError,
                    );
                  },
                );
              },
            ),
          ),
          if (_isLoading) 
            Container(
              padding: const EdgeInsets.all(16),
              child: const Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('AI is thinking...'),
                ],
              ),
            ),
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
    bool isInitial = false,
    bool isError = false,
  }) {
    final alignment = isUserMessage 
        ? CrossAxisAlignment.end 
        : CrossAxisAlignment.start;
    
    Color bubbleColor;
    Color textColor;
    
    if (isUserMessage) {
      bubbleColor = Theme.of(context).colorScheme.primary;
      textColor = Colors.white;
    } else if (isError) {
      bubbleColor = Colors.red.shade100;
      textColor = Colors.red.shade800;
    } else if (isInitial) {
      bubbleColor = Colors.blue.shade50;
      textColor = Colors.blue.shade800;
    } else {
      bubbleColor = Theme.of(context).colorScheme.secondaryContainer;
      textColor = Theme.of(context).colorScheme.onSecondaryContainer;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: 16,
              ),
            ),
          ),
          if (!isUserMessage && !isInitial) // Show actions only for AI responses
            Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share, size: 18),
                    onPressed: () => Share.share(text),
                    tooltip: 'Share this response',
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.thumb_up,
                      size: 18,
                      color: feedback == 'liked' ? Colors.green : Colors.grey,
                    ),
                    onPressed: feedback != null ? null : () =>
                        _saveFeedback(messageId, 'liked'),
                    tooltip: 'Good response',
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.thumb_down,
                      size: 18,
                      color: feedback == 'disliked' ? Colors.red : Colors.grey,
                    ),
                    onPressed: feedback != null ? null : () =>
                        _saveFeedback(messageId, 'disliked'),
                    tooltip: 'Poor response',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextInputArea() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: Colors.grey.shade300,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              enabled: !_isLoading,
              decoration: InputDecoration(
                hintText: 'Ask a question about this document...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                suffixIcon: _textController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _textController.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _sendMessage(),
              onChanged: (value) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _isLoading || _textController.text.trim().isEmpty 
                  ? null 
                  : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat History'),
        content: const Text(
          'This will delete all messages in this chat. The document summary will need to be regenerated if you want to chat again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _clearChatHistory();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearChatHistory() async {
    try {
      // Delete all chat messages
      final messagesRef = FirebaseFirestore.instance
          .collection('files')
          .doc(widget.documentId)
          .collection('chat_messages');
      
      final messages = await messagesRef.get();
      for (final doc in messages.docs) {
        await doc.reference.delete();
      }

      // Reset chat status in main document
      await FirebaseFirestore.instance
          .collection('files')
          .doc(widget.documentId)
          .update({
        'isChatReady': false,
        'chatStatus': null,
        'summary': FieldValue.delete(),
      });

      if (mounted) {
        Navigator.of(context).pop(); // Go back to home screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat history cleared')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing chat: $e')),
        );
      }
    }
  }
}