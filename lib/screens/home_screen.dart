import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // We'll hold the upload task in our state to monitor it.
  UploadTask? _uploadTask;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  Future<void> _saveFileMetadata(
      String fileName, String storagePath, String userId) async {
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

    // Create the upload task
    final uploadTask = storageRef.putFile(File(image.path));

    // Call setState ONCE to start showing the progress bar
    setState(() {
      _uploadTask = uploadTask;
    });

    try {
      // Await the task to complete
      await uploadTask;

      // Save metadata after successful upload
      await _saveFileMetadata(image.name, path, userId);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload Complete!')),
      );

    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload Failed: ${e.message}')),
      );
    } finally {
      // Call setState ONCE to hide the progress bar
      setState(() {
        _uploadTask = null;
      });
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
        // We'll show a LinearProgressIndicator at the bottom of the AppBar during upload
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
        // Disable the button during an upload
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

  // In lib/screens/home_screen.dart

Widget _buildFilesList() {
    if (currentUser == null) return const Center(child: Text('Please log in.'));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('files')
          .where('userId', isEqualTo: currentUser!.uid)
          .orderBy('uploadTimestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _uploadTask == null) {
          return const Center(child: CircularProgressIndicator());
        }
        
        // THIS IS THE IMPORTANT CHANGE
        if (snapshot.hasError) {
          // Explicitly print the error to the debug console
          print("!!! FIRESTORE QUERY ERROR: ${snapshot.error}"); 
          
          // Also display the error directly on the screen
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'DATABASE ERROR:\n\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'No files uploaded yet.',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          );
        }

        final files = snapshot.data!.docs;

        return ListView.builder(
          itemCount: files.length,
          itemBuilder: (context, index) {
            final fileData = files[index].data() as Map<String, dynamic>;
            return ListTile(
              leading: const Icon(Icons.image, color: Colors.blue),
              title: Text(fileData['originalFileName'] ?? 'No filename', maxLines: 1, overflow: TextOverflow.ellipsis,),
              subtitle: Text('Status: ${fileData['status'] ?? 'Unknown'}'),
            );
          },
        );
      },
    );
  }
}