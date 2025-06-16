import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:scan_master/screens/pdf_viewer_screen.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UploadTask? _uploadTask;
  late Razorpay _razorpay;

  Stream<DocumentSnapshot?>? _userStream;
  Stream<QuerySnapshot>? _filesStream;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userStream = FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
      _filesStream = FirebaseFirestore.instance
          .collection('files')
          .where('userId', isEqualTo: user.uid)
          .orderBy('uploadTimestamp', descending: true)
          .snapshots();
    }
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final data = {
        'order_id': response.orderId,
        'razorpay_payment_id': response.paymentId,
        'razorpay_signature': response.signature,
      };
      FirebaseFunctions functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final HttpsCallable callable = functions.httpsCallable('verify-payment');
      await callable.call(data);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subscription successfully activated!')),
      );
    } catch (e) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An error occurred during verification.')));
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Payment Failed: ${response.message}')));
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    print('EXTERNAL_WALLET: ${response.walletName}');
  }

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

  void _showLimitReachedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Weekly Limit Reached'),
        content: const Text(
            'You have reached your free weekly limit of 5 uploads. Please subscribe for unlimited uploads.'),
        actions: [
          TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop()),
          ElevatedButton(
              child: const Text('Subscribe'),
              onPressed: () {
                Navigator.of(context).pop();
                _createSubscriptionOrder();
              }),
        ],
      ),
    );
  }

  Future<void> _handleUploadAttempt() async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
    try {
      FirebaseFunctions functions =
          FirebaseFunctions.instanceFor(region: 'us-central1');
      final HttpsCallable callable =
          functions.httpsCallable('check-upload-allowance');
      final HttpsCallableResult result = await callable.call();
      if (!mounted) return;
      Navigator.of(context).pop();
      final bool isAllowed = result.data['allow'] ?? false;
      if (isAllowed) {
        _startImagePickerAndUpload();
      } else {
        _showLimitReachedDialog();
      }
    } catch (e) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('An unexpected error occurred.')));
    }
  }

  Future<void> _startImagePickerAndUpload() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final String userId = user.uid;
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
            const SnackBar(content: Text('Upload Complete! Processing...')));
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload Failed: ${e.message}')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadTask = null;
        });
      }
    }
  }

  Future<void> _createSubscriptionOrder() async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      FirebaseFunctions functions =
          FirebaseFunctions.instanceFor(region: 'us-central1');
      final HttpsCallable callable =
          functions.httpsCallable('create-subscription-order');
      final HttpsCallableResult result = await callable.call();
      if (!mounted) return;
      Navigator.of(context).pop();
      final orderData = Map<String, dynamic>.from(result.data);
      final user = FirebaseAuth.instance.currentUser;
      final options = {
        'key': orderData['razorpayKeyId'],
        'amount': orderData['amount'],
        'name': 'Scan Master',
        'order_id': orderData['orderId'],
        'description': 'Premium Subscription',
        'prefill': {'email': user?.email ?? ''}
      };
      _razorpay.open(options);
    } catch (e) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('An unexpected error occurred.')));
    }
  }

  Future<void> _viewPdf(String documentId) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      HttpsCallable callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('get-download-url');
      final response =
          await callable.call<Map<String, dynamic>>({'documentId': documentId});
      if (!mounted) return;
      Navigator.of(context).pop();
      final String url = response.data['url'];
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (context) => PdfViewerScreen(url: url)));
    } catch (e) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('An error occurred: $e')));
    }
  }

  Future<void> _deleteFile(String documentId) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Are you sure?'),
            content: const Text('Do you want to permanently delete this file?'),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel')),
              TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()));
    try {
      HttpsCallable callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('delete-file');
      await callable.call<Map<String, dynamic>>({'documentId': documentId});
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('File deleted successfully.')));
    } catch (e) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('An unexpected error occurred: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // This is the new, clean architecture. A single StreamBuilder wraps the UI.
    return StreamBuilder<DocumentSnapshot?>(
      stream: _userStream,
      builder: (context, userSnapshot) {
        // Handle the case where the stream is loading, which is important for new users.
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text("Loading...")),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // Once loaded, determine the subscription state from this single source of truth.
        bool isSubscribed = false;
        Timestamp? subEndDate;
        if (userSnapshot.hasData && userSnapshot.data?.exists == true) {
          final data = userSnapshot.data!.data() as Map<String, dynamic>?;
          isSubscribed = data?['isSubscribed'] == true;
          if (isSubscribed) {
            subEndDate = data?['subscriptionEndDate'] as Timestamp?;
          }
        }

        // Build the entire UI based on the definitive state.
        return Scaffold(
          appBar: AppBar(
            title: const Text('My Files'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: () => FirebaseAuth.instance.signOut(),
              ),
              if (isSubscribed)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.0),
                  child: Chip(
                    label: Text('Premium User',
                        style: TextStyle(color: Colors.white)),
                    backgroundColor: Colors.amber,
                    avatar: Icon(Icons.star, color: Colors.white),
                  ),
                )
              else
                TextButton(
                  onPressed: _createSubscriptionOrder,
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.blue.shade600),
                  child: const Text("Subscribe"),
                ),
              const SizedBox(width: 8),
            ],
            bottom: _uploadTask != null
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(4.0),
                    child: StreamBuilder<TaskSnapshot>(
                      stream: _uploadTask!.snapshotEvents,
                      builder: (context, progressSnapshot) {
                        final progress = progressSnapshot.hasData
                            ? progressSnapshot.data!.bytesTransferred /
                                progressSnapshot.data!.totalBytes
                            : null;
                        return LinearProgressIndicator(value: progress);
                      },
                    ),
                  )
                : null,
          ),
          body: Column(
            children: [
              if (isSubscribed && subEndDate != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Subscription active until: ${DateFormat.yMMMd().format(subEndDate.toDate())}',
                    style: TextStyle(
                        color: Colors.green.shade700, fontWeight: FontWeight.bold),
                  ),
                ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _filesStream,
                  builder: (context, filesSnapshot) {
                    if (filesSnapshot.connectionState == ConnectionState.waiting &&
                        !filesSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (filesSnapshot.hasError) {
                      return Center(
                          child: Text('DATABASE ERROR:\n\n${filesSnapshot.error}'));
                    }
                    if (!filesSnapshot.hasData || filesSnapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text('No files uploaded yet. Press + to begin.',
                            style: TextStyle(fontSize: 18, color: Colors.grey)),
                      );
                    }
                    final files = filesSnapshot.data!.docs;
                    return ListView.builder(
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final fileData = files[index].data() as Map<String, dynamic>;
                        final status = fileData['status'] ?? 'Unknown';
                        final isCompleted = status == 'Completed';
                        final originalFileName =
                            fileData['originalFileName'] ?? 'No filename';
                        String displayName;
                        if (isCompleted) {
                          final baseName = originalFileName.contains('.')
                              ? originalFileName.substring(
                                  0, originalFileName.lastIndexOf('.'))
                              : originalFileName;
                          displayName = '$baseName.pdf';
                        } else {
                          displayName = originalFileName;
                        }
                        return ListTile(
                          leading: Icon(
                              isCompleted ? Icons.picture_as_pdf : Icons.image,
                              color: isCompleted ? Colors.green : Colors.blue,
                              size: 36),
                          title: Text(displayName,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
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
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _uploadTask != null ? null : _handleUploadAttempt,
            tooltip: 'Upload Image',
            child: _uploadTask != null
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 3))
                : const Icon(Icons.add),
          ),
        );
      },
    );
  }
}