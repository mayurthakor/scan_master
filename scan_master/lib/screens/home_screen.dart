// lib/screens/home_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:scan_master/screens/chat_screen.dart';
import 'package:scan_master/services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';

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

  final ApiService _apiService = ApiService();
  final Map<String, bool> _isPreparingChat = {};

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userStream =
          FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
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

  Future<void> _initiateChatPreparation(String documentId) async {
    setState(() {
      _isPreparingChat[documentId] = true;
    });

    await FirebaseFirestore.instance
        .collection('files')
        .doc(documentId)
        .update({'chatStatus': 'preparing'});

    _apiService.prepareChatSession(documentId).catchError((e) {
      print("Error preparing chat in background: $e");
      // The backend function will set the status to 'failed' on its own
    }).whenComplete(() {
      if (mounted) {
        setState(() {
          _isPreparingChat.remove(documentId);
        });
      }
    });
  }

  Future<void> _navigateToChat(String documentId) async {
     final doc = await FirebaseFirestore.instance.collection('files').doc(documentId).get();
     final summary = doc.data()?['summary'] ?? "Summary not found.";

     if (!mounted) return;
     Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            documentId: documentId,
            initialSummary: summary,
          ),
        ),
      );
  }

  Widget _buildTrailingWidget(Map<String, dynamic> fileData, String documentId) {
    final status = fileData['status'] ?? 'Unknown';
    if (status != 'Completed') {
      return IconButton(
        icon: const Icon(Icons.delete),
        color: Theme.of(context).colorScheme.error,
        onPressed: () => _deleteFile(documentId),
      );
    }
    
    final chatStatus = fileData['chatStatus'] as String?;
    final isLocallyPreparing = _isPreparingChat[documentId] ?? false;

    if (chatStatus == 'preparing' || isLocallyPreparing) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text("Preparing...")
        ],
      );
    }

    if (chatStatus == 'failed') {
      return IconButton(
        icon: const Icon(Icons.error, color: Colors.red),
        tooltip: 'Failed to prepare. Tap to retry.',
        onPressed: () => _initiateChatPreparation(documentId),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline),
          color: Colors.purple,
          tooltip: 'Chat with AI',
          onPressed: () {
            final isChatReady = fileData['isChatReady'] ?? false;
            if (isChatReady) {
              _navigateToChat(documentId);
            } else {
              _initiateChatPreparation(documentId);
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          color: Theme.of(context).colorScheme.error,
          onPressed: () => _deleteFile(documentId),
        ),
      ],
    );
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

  IconData _getIconForFile(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'txt':
        return Icons.text_snippet;
      case 'docx':
        return Icons.description;
      case 'csv':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
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
        _startFilePickerAndUpload();
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

  Future<void> _startFilePickerAndUpload() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'txt', 'docx', 'csv', 'xlsx', 'pptx'],
    );
    if (result == null) return;

    final PlatformFile pickedFile = result.files.first;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final DocumentReference docRef = FirebaseFirestore.instance.collection('files').doc();
    
    final String fileName = '${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}';
    final String storagePath = 'uploads/${user.uid}/$fileName';
    
    final SettableMetadata metadata = SettableMetadata(
      customMetadata: <String, String>{
        'firestoreDocId': docRef.id,
      },
    );

    final Reference storageRef = FirebaseStorage.instance.ref().child(storagePath);
    final fileToUpload = File(pickedFile.path!);
    final uploadTask = storageRef.putFile(fileToUpload, metadata);

    setState(() {
      _uploadTask = uploadTask;
    });

    try {
      await docRef.set({
        'userId': user.uid,
        'originalFileName': pickedFile.name,
        'storagePath': storagePath,
        'uploadTimestamp': FieldValue.serverTimestamp(),
        'status': 'Uploaded',
      });

      await uploadTask;

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
      final Uri uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $url';
      }

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
    return StreamBuilder<DocumentSnapshot?>(
      stream: _userStream,
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text("Loading...")),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        bool isSubscribed = false;
        Timestamp? subEndDate;
        if (userSnapshot.hasData && userSnapshot.data?.exists == true) {
          final data = userSnapshot.data!.data() as Map<String, dynamic>?;
          isSubscribed = data?['isSubscribed'] == true;
          if (isSubscribed) {
            subEndDate = data?['subscriptionEndDate'] as Timestamp?;
          }
        }

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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: const Chip(
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
                        final fileDoc = files[index];
                        final fileData = fileDoc.data() as Map<String, dynamic>;
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
                            isCompleted
                                ? Icons.picture_as_pdf
                                : _getIconForFile(originalFileName),
                            color: isCompleted ? Colors.green : Colors.blue,
                            size: 36,
                          ),
                          title: Text(displayName,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text('Status: $status'),
                          onTap: isCompleted && (fileData['pdfPath'] != null) ? () => _viewPdf(fileDoc.id) : null,
                          trailing: _buildTrailingWidget(fileData, fileDoc.id),
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