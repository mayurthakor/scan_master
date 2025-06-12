import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:scan_master/screens/pdf_viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UploadTask? _uploadTask;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  Future<void> _saveFileMetadata(String fileName, String storagePath, String userId) async {
    await FirebaseFirestore.instance.collection('files').add({
      'userId': userId,
      'originalFileName': fileName,
      'storagePath': storagePath,
      'uploadTimestamp': FieldValue.serverTimestamp(),
      'status': 'Uploaded',
    });
  }

  Future<void> _pickAndUploadImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null || currentUser == null) return;

    final String userId = currentUser!.uid;
    final String fileName = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
    final String path = 'uploads/$userId/$fileName';
    final Reference storageRef = FirebaseStorage.instance.ref().child(path);

    final uploadTask = storageRef.putFile(File(image.path));

    setState(() {
      _uploadTask = uploadTask;
    });

    try {
      await uploadTask;
      await _saveFileMetadata(image.name, path, userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload Complete!')),
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload Failed: ${e.message}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadTask = null;
        });
      }
    }
  }

  // In lib/screens/home_screen.dart

  // This function now opens our new in-app PDF viewer screen
  Future<void> _viewPdf(String documentId) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      HttpsCallable callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('get-download-url');
      final response = await callable.call<Map<String, dynamic>>({
        'documentId': documentId,
        'userId': currentUser!.uid,
      });

      Navigator.of(context).pop(); // Close loading indicator

      final String url = response.data['url'];

      // Navigate to the new screen, passing the URL
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PdfViewerScreen(url: url),
        ),
      );

    } on FirebaseFunctionsException catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error from server: ${e.message}')));
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An unexpected error occurred: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Files'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
        bottom: _uploadTask != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4.0),
                child: StreamBuilder<TaskSnapshot>(
                  stream: _uploadTask!.snapshotEvents,
                  builder: (context, snapshot) {
                    final progress = snapshot.hasData
                        ? snapshot.data!.bytesTransferred / snapshot.data!.totalBytes
                        : 0.0;
                    return LinearProgressIndicator(value: progress);
                  },
                ),
              )
            : null,
      ),
      body: _buildFilesList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _uploadTask != null ? null : _pickAndUploadImage,
        tooltip: 'Upload Image',
        child: _uploadTask != null
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : const Icon(Icons.add),
      ),
    );
  }

  Widget _buildFilesList() {
    if (currentUser == null) return const Center(child: Text('Please log in.'));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('files')
          .where('userId', isEqualTo: currentUser!.uid)
          .orderBy('uploadTimestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('DATABASE ERROR:\n\n${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'No files uploaded yet. Press + to begin.',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          );
        }

        final files = snapshot.data!.docs;

        return ListView.builder(
          itemCount: files.length,
          itemBuilder: (context, index) {
            final fileData = files[index].data() as Map<String, dynamic>;
            final String status = fileData['status'] ?? 'Unknown';
            final bool isCompleted = status == 'Completed';

            return ListTile(
              leading: Icon(
                isCompleted ? Icons.picture_as_pdf : Icons.image,
                color: isCompleted ? Colors.green : Colors.blue,
              ),
              title: Text(fileData['originalFileName'] ?? 'No filename', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('Status: $status'),
              onTap: isCompleted ? () => _viewPdf(files[index].id) : null,
              trailing: isCompleted ? const Icon(Icons.download_for_offline) : null,
            );
          },
        );
      },
    );
  }
}