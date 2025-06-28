// lib/features/home/presentation/widgets/document_list_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../bloc/home_bloc.dart';

class DocumentListWidget extends StatelessWidget {
  final List<Map<String, dynamic>> documents;
  final Map<String, bool> preparingChat;

  const DocumentListWidget({
    super.key,
    required this.documents,
    this.preparingChat = const {},
  });

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No documents yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Upload your first document to get started',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final document = documents[index];
        return DocumentCard(
          document: document,
          isPreparingChat: preparingChat[document['id']] ?? false,
        );
      },
    );
  }
}

class DocumentCard extends StatelessWidget {
  final Map<String, dynamic> document;
  final bool isPreparingChat;

  const DocumentCard({
    super.key,
    required this.document,
    required this.isPreparingChat,
  });

  @override
  Widget build(BuildContext context) {
    final name = document['name'] as String? ?? 'Unknown';
    final type = document['type'] as String? ?? 'unknown';
    final uploadedAt = document['uploadedAt'] as DateTime? ?? DateTime.now();
    final size = document['size'] as int? ?? 0;
    final status = document['status'] as String? ?? 'completed';
    final url = document['url'] as String? ?? '';
    final thumbnailUrl = document['thumbnailUrl'] as String?;
    final chatPrepared = document['chatPrepared'] as bool? ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: _buildThumbnail(type, thumbnailUrl, status),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Uploaded: ${DateFormat('MMM dd, yyyy • HH:mm').format(uploadedAt)}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Size: ${_formatFileSize(size)} • Status: $status',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: _buildTrailingActions(context, document['id'], url, chatPrepared),
        onTap: status == 'completed' && url.isNotEmpty
            ? () => _downloadDocument(url, name)
            : null,
      ),
    );
  }

  Widget _buildThumbnail(String type, String? thumbnailUrl, String status) {
    const size = 50.0;
    
    if (status == 'completed' && thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      // Show thumbnail image
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: CachedNetworkImage(
            imageUrl: thumbnailUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => _buildLoadingThumbnail(),
            errorWidget: (context, url, error) => _buildIconThumbnail(type, status),
          ),
        ),
      );
    } else {
      return _buildIconThumbnail(type, status);
    }
  }

  Widget _buildLoadingThumbnail() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildIconThumbnail(String type, String status) {
    return CircleAvatar(
      backgroundColor: _getTypeColor(type),
      child: Icon(
        _getTypeIcon(type),
        color: Colors.white,
        size: 24,
      ),
    );
  }

  Widget _buildTrailingActions(BuildContext context, String documentId, String url, bool chatPrepared) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Download button
        if (url.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download',
            onPressed: () => _downloadDocument(url, document['name']),
          ),
        
        // Chat button
        IconButton(
          icon: isPreparingChat
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.chat_bubble_outline,
                  color: chatPrepared ? Colors.green : Colors.grey,
                ),
          tooltip: chatPrepared ? 'Chat with Document' : 'Prepare for Chat',
          onPressed: isPreparingChat
              ? null
              : () {
                  if (chatPrepared) {
                    _navigateToChat(context, documentId);
                  } else {
                    context.read<HomeBloc>().add(
                      ChatPreparationRequested(documentId),
                    );
                  }
                },
        ),
        
        // Delete button
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          tooltip: 'Delete',
          onPressed: () => _showDeleteConfirmation(context, documentId),
        ),
      ],
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'document':
        return Colors.blue;
      case 'image':
        return Colors.green;
      case 'text':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'document':
        return Icons.description;
      case 'image':
        return Icons.image;
      case 'text':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _downloadDocument(String url, String fileName) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      print('Error downloading document: $e');
    }
  }

  void _navigateToChat(BuildContext context, String documentId) {
    // TODO: Navigate to chat screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chat feature coming soon!'),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, String documentId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Document'),
        content: const Text(
          'Are you sure you want to delete this document? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // Use the original context that has access to HomeBloc
              context.read<HomeBloc>().add(
                DocumentDeleteRequested(documentId),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}