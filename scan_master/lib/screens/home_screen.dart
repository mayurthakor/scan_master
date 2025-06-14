import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:scan_master/screens/pdf_viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UploadTask? _uploadTask;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  // Saves metadata about the file to Firestore after a successful upload
  Future<void> _saveFileMetadata(String fileName, String storagePath, String userId) async {
    await FirebaseFirestore.instance.collection('files').add({
      'userId': userId,
      'originalFileName': fileName,
      'storagePath': storagePath,
      'uploadTimestamp': FieldValue.serverTimestamp(),
      'status': 'Uploaded',
    });
  }

  // Paste this function inside your _HomeScreenState class

  Future<void> _createSubscriptionOrder(BuildContext context) async {
    // Show a loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Note: It's good practice to specify the region, just like in your other functions.
      FirebaseFunctions functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      
      // Reference the callable function by its deployed name 
      final HttpsCallable callable = functions.httpsCallable('create-subscription-order');

      // Call the function
      final HttpsCallableResult result = await callable.call();

      // Close the loading dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Print the data from the backend to the debug console
      print("Successfully created Razorpay order: ${result.data}");
      
      // We will use this data in the next step to launch Razorpay checkout
      
    } on FirebaseFunctionsException catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
      print('Functions Error: ${e.code} - ${e.message}');
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('An unexpected error occurred.')));
      print('Generic Error: $e');
    }
  }
  // Handles picking an image from the gallery and starting the upload process
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

  // Calls the backend to get a signed URL and opens the PDF viewer screen
  Future<void> _viewPdf(String documentId) async {
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
      
      // Navigate to the new in-app viewer screen
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

  // Shows a confirmation dialog before deleting a file
  Future<bool> _showDeleteConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('Do you want to permanently delete this file? This action cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ?? false; // Return false if dialog is dismissed
  }

  // Calls the new backend function to delete the file
  Future<void> _deleteFile(String documentId) async {
    final bool confirmed = await _showDeleteConfirmationDialog();
    if (!confirmed || currentUser == null) return;

    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

    try {
      HttpsCallable callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('delete-file');
      // We pass the documentId. The backend will verify ownership using the auth token.
      await callable.call<Map<String, dynamic>>({
        'documentId': documentId,
      });
      
      // The StreamBuilder will automatically remove the item from the list.
      // We just need to close the dialog.
      Navigator.of(context).pop(); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File deleted successfully.')));

    } on FirebaseFunctionsException catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
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
            // Add this button
            ElevatedButton(
              onPressed: () {
                // We will call the function here
                _createSubscriptionOrder(context);
              },
              child: Text("Subscribe"),
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

  // In lib/screens/home_screen.dart
// Replace the entire _buildFilesList widget with this one.

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
            final String originalFileName = fileData['originalFileName'] ?? 'No filename';

            // --- NEW LOGIC for Display Name ---
            String displayName;
            if (isCompleted) {
              // If completed, show the base name with a .pdf extension
              final baseName = originalFileName.contains('.')
                  ? originalFileName.substring(0, originalFileName.lastIndexOf('.'))
                  : originalFileName;
              displayName = '$baseName.pdf';
            } else {
              // Otherwise, show the original filename
              displayName = originalFileName;
            }
            // --- END OF NEW LOGIC ---

            return ListTile(
              leading: Icon(
                isCompleted ? Icons.picture_as_pdf : Icons.image,
                color: isCompleted ? Colors.green : Colors.blue,
                size: 36, // Making the icon a little bigger
              ),
              title: Text(displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('Status: $status'),
              onTap: isCompleted ? () => _viewPdf(files[index].id) : null,
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                color: Theme.of(context).colorScheme.error,
                tooltip: 'Delete File',
                onPressed: () => _deleteFile(files[index].id),
              ),
            );
          },
        );
      },
    );
  }
}