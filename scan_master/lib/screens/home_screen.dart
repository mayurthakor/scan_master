import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:scan_master/screens/pdf_viewer_screen.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:intl/intl.dart'; // We'll use this for date formatting

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UploadTask? _uploadTask;
  final User? currentUser = FirebaseAuth.instance.currentUser;
  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    print('Razorpay Success Response: ${response.paymentId}');
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
      final HttpsCallableResult result = await callable.call(data);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.data?['message'] ?? 'Subscription successfully activated!')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backend Verification Error: ${e.message}')));
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('An unexpected error occurred during verification.')));
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    print('ERROR: ${response.code} - ${response.message}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Payment Failed: ${response.message}')),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    print('EXTERNAL_WALLET: ${response.walletName}');
  }

  // --- NEW FUNCTION TO SHOW LIMIT DIALOG ---
  void _showLimitReachedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Weekly Limit Reached'),
        content: const Text('You have reached your free weekly limit of 5 uploads. Please subscribe for unlimited uploads.'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: const Text('Subscribe'),
            onPressed: () {
              Navigator.of(context).pop();
              _createSubscriptionOrder(context);
            },
          ),
        ],
      ),
    );
  }

  // --- MODIFIED: This function now acts as a gatekeeper ---
  Future<void> _handleUploadAttempt() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );

    try {
      FirebaseFunctions functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final HttpsCallable callable = functions.httpsCallable('check-upload-allowance');
      final HttpsCallableResult result = await callable.call();

      Navigator.of(context).pop(); // Close loading dialog

      final bool isAllowed = result.data['allow'] ?? false;
      if (isAllowed) {
        _startImagePickerAndUpload(); // Proceed with upload
      } else {
        _showLimitReachedDialog(); // Show the limit reached popup
      }
    } on FirebaseFunctionsException catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('An unexpected error occurred.')));
    }
  }

  // --- NEW: Contains the original upload logic ---
  Future<void> _startImagePickerAndUpload() async {
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
      // We no longer need _saveFileMetadata, the backend handles this logic implicitly
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

  Future<void> _createSubscriptionOrder(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      FirebaseFunctions functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final HttpsCallable callable = functions.httpsCallable('create-subscription-order');
      final HttpsCallableResult result = await callable.call();
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      final orderData = Map<String, dynamic>.from(result.data);
      final options = {
        'key': orderData['razorpayKeyId'],
        'amount': orderData['amount'],
        'name': 'Scan Master',
        'order_id': orderData['orderId'],
        'description': 'Premium Subscription',
        'prefill': {'email': currentUser?.email ?? ''}
      };
      _razorpay.open(options);
    } on FirebaseFunctionsException catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('An unexpected error occurred.')));
    }
  }

  Future<void> _viewPdf(String documentId) async {
    // This function remains the same
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      HttpsCallable callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('get-download-url');
      final response = await callable.call<Map<String, dynamic>>({'documentId': documentId});
      Navigator.of(context).pop();
      final String url = response.data['url'];
      Navigator.of(context).push(MaterialPageRoute(builder: (context) => PdfViewerScreen(url: url)));
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An error occurred: $e')));
    }
  }

  Future<void> _deleteFile(String documentId) async {
    // This function remains the same
    final bool confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('Do you want to permanently delete this file? This action cannot be undone.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(style: TextButton.styleFrom(foregroundColor: Colors.red), onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    ) ?? false;
    if (!confirmed) return;
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
    try {
      HttpsCallable callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('delete-file');
      await callable.call<Map<String, dynamic>>({'documentId': documentId});
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File deleted successfully.')));
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An unexpected error occurred: $e')));
    }
  }

  // --- MODIFIED WIDGET: This now wraps the UI in a StreamBuilder to get user status ---
  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Not logged in.')));
    }
    return StreamBuilder<DocumentSnapshot>(
      // Listen to the current user's document in the 'users' collection
      stream: FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).snapshots(),
      builder: (context, snapshot) {
        final bool isSubscribed = snapshot.hasData && snapshot.data!.exists && (snapshot.data!.data() as Map<String, dynamic>)['isSubscribed'] == true;
        Timestamp? endDate = (snapshot.hasData && snapshot.data!.exists) ? (snapshot.data!.data() as Map<String, dynamic>)['subscriptionEndDate'] : null;

        return Scaffold(
          appBar: AppBar(
            title: const Text('My Files'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: () => FirebaseAuth.instance.signOut(),
              ),
              // --- Conditionally render UI based on subscription status ---
              if (isSubscribed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Chip(
                    label: const Text('Premium User', style: TextStyle(color: Colors.white)),
                    backgroundColor: Colors.amber,
                    avatar: const Icon(Icons.star, color: Colors.white),
                  ),
                )
              else
                TextButton(
                  onPressed: () => _createSubscriptionOrder(context),
                  style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.blue.shade600),
                  child: const Text("Subscribe"),
                ),
              const SizedBox(width: 8),
            ],
            bottom: _uploadTask != null
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(4.0),
                    child: StreamBuilder<TaskSnapshot>(
                      stream: _uploadTask!.snapshotEvents,
                      builder: (context, snapshot) {
                        final progress = snapshot.hasData ? snapshot.data!.bytesTransferred / snapshot.data!.totalBytes : 0.0;
                        return LinearProgressIndicator(value: progress);
                      },
                    ),
                  )
                : null,
          ),
          body: _buildFilesList(isSubscribed, endDate), // Pass status to the list builder
          floatingActionButton: FloatingActionButton(
            onPressed: _uploadTask != null ? null : _handleUploadAttempt,
            tooltip: 'Upload Image',
            child: _uploadTask != null
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                : const Icon(Icons.add),
          ),
        );
      },
    );
  }

  // --- MODIFIED WIDGET: It now receives subscription status ---
  Widget _buildFilesList(bool isSubscribed, Timestamp? endDate) {
    return Column(
      children: [
        if (isSubscribed && endDate != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Subscription active until: ${DateFormat.yMMMd().format(endDate.toDate())}',
              style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold),
            ),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
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

                  String displayName;
                  if (isCompleted) {
                    final baseName = originalFileName.contains('.') ? originalFileName.substring(0, originalFileName.lastIndexOf('.')) : originalFileName;
                    displayName = '$baseName.pdf';
                  } else {
                    displayName = originalFileName;
                  }

                  return ListTile(
                    leading: Icon(isCompleted ? Icons.picture_as_pdf : Icons.image, color: isCompleted ? Colors.green : Colors.blue, size: 36),
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
          ),
        ),
      ],
    );
  }
}