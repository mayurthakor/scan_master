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
import 'package:scan_master/screens/document_preview_screen.dart';
import 'package:scan_master/services/api_service.dart';
import 'package:scan_master/services/camera_service.dart';
import 'package:scan_master/screens/realtime_camera_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:scan_master/config/api_config.dart';

class UpdatedHomeScreen extends StatefulWidget {
  final VoidCallback? onSignOut;
  
  const UpdatedHomeScreen({super.key, this.onSignOut});
  
  @override
  State<UpdatedHomeScreen> createState() => _UpdatedHomeScreenState();
}

class _UpdatedHomeScreenState extends State<UpdatedHomeScreen> {
  UploadTask? _uploadTask;
  late Razorpay _razorpay;

  Stream<DocumentSnapshot?>? _userStream;
  Stream<QuerySnapshot>? _filesStream;

  final ApiService _apiService = ApiService.instance;
  final Map<String, bool> _isPreparingChat = {};

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _setupStreams();
  }

  Future<void> _initializeServices() async {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    // Initialize camera service
    try {
      await CameraService.instance.initialize();
    } catch (e) {
      print('Camera initialization failed: $e');
      // Camera not available - show appropriate UI
    }

    // Cleanup old temporary files
    CameraService.instance.cleanupTempFiles();
  }

  void _setupStreams() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userStream = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots();
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
    CameraService.instance.disposeController();
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
      FirebaseFunctions functions =
          FirebaseFunctions.instanceFor(region: 'us-central1');
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
        const SnackBar(content: Text('An error occurred during verification.')),
      );
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Payment Failed: ${response.message}')),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    print('EXTERNAL_WALLET: ${response.walletName}');
  }

  Future<void> _showUploadOptions() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Add Document',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildUploadOption(
                icon: Icons.camera_alt,
                title: 'Scan Document',
                subtitle: 'Use camera to scan a document',
                onTap: () {
                  Navigator.of(context).pop();
                  _openDocumentScanner();
                },
              ),
              _buildUploadOption(
                icon: Icons.upload_file,
                title: 'Upload File',
                subtitle: 'Choose from device storage',
                onTap: () {
                  Navigator.of(context).pop();
                  _handleUploadAttempt();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: Colors.blue,
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  Future<void> _openDocumentScanner() async {
    try {
      // Check camera permissions and availability
      if (!await _checkCameraAvailability()) {
        return;
      }

      if (!mounted) return;
      
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RealtimeCameraScreen(
            onImageCaptured: _handleCameraCapture,
            enableAutoCapture: true,
          ),
          fullscreenDialog: true,
        ),
      );
    } catch (e) {
      _showErrorDialog('Camera not available: $e');
    }
  }

  Future<bool> _checkCameraAvailability() async {
    try {
      final cameras = CameraService.instance.cameras;
      if (cameras == null || cameras.isEmpty) {
        _showErrorDialog(
          'No camera available on this device. Please use the file upload option instead.',
        );
        return false;
      }
      return true;
    } catch (e) {
      _showErrorDialog(
        'Camera access denied. Please enable camera permissions in settings.',
      );
      return false;
    }
  }

  Future<void> _handleCameraCapture(String imagePath) async {
    if (!mounted) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EnhancedDocumentPreviewScreen(
          imagePath: imagePath,
          onDocumentProcessed: _handleProcessedDocument,
        ),
      ),
    );
  }

  Future<void> _handleProcessedDocument(String processedImagePath) async {
    try {
      await _uploadScannedDocument(processedImagePath);
    } catch (e) {
      _showErrorDialog('Failed to upload scanned document: $e');
    }
  }

  Future<void> _uploadScannedDocument(String imagePath) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Check upload allowance first
    final bool isAllowed = await _checkUploadAllowance();
    if (!isAllowed) {
      _showLimitReachedDialog();
      return;
    }

    final DocumentReference docRef =
        FirebaseFirestore.instance.collection('files').doc();
    
    final String fileName = 
        'scanned_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final String storagePath = 'uploads/${user.uid}/$fileName';
    
    final SettableMetadata metadata = SettableMetadata(
      customMetadata: <String, String>{
        'firestoreDocId': docRef.id,
        'source': 'scanner',
      },
    );

    final Reference storageRef =
        FirebaseStorage.instance.ref().child(storagePath);
    final fileToUpload = File(imagePath);
    final uploadTask = storageRef.putFile(fileToUpload, metadata);

    setState(() {
      _uploadTask = uploadTask;
    });

    try {
      await docRef.set({
        'userId': user.uid,
        'originalFileName': fileName,
        'storagePath': storagePath,
        'uploadTimestamp': FieldValue.serverTimestamp(),
        'status': 'Uploaded',
        'source': 'scanner',
        'documentType': 'scanned',
      });

      await uploadTask;

      // Clean up temporary file
      try {
        await File(imagePath).delete();
      } catch (e) {
        print('Failed to delete temporary file: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document scanned and uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
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

  Future<bool> _checkUploadAllowance() async {
    try {
      if (ApiConfig.enableDebugLogs) {
        print('🔍 Checking upload allowance...');
      }
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final result = await ApiService.instance.checkUploadAllowance(user.uid);
          
      final isAllowed = result;
      
      if (ApiConfig.enableDebugLogs) {
        print('📋 Upload allowance result: ${isAllowed ? "✅ Allowed" : "❌ Denied"}');
      }
      
      return isAllowed;
      
    } catch (e) {
      if (ApiConfig.enableDebugLogs) {
        print('🚨 Upload allowance check failed: $e');
      }
      
      print('⚠️ Upload allowance check failed, allowing upload: $e');
      return true;
    }
  }

  void _showLimitReachedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Weekly Limit Reached'),
        content: const Text(
          'You have reached your free weekly limit of 5 uploads. Please subscribe for unlimited uploads.',
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: const Text('Subscribe'),
            onPressed: () {
              Navigator.of(context).pop();
              _createSubscriptionOrder();
            },
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUploadAttempt() async {
    final bool isAllowed = await _checkUploadAllowance();
    if (isAllowed) {
      _startFilePickerAndUpload();
    } else {
      _showLimitReachedDialog();
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

    final DocumentReference docRef =
        FirebaseFirestore.instance.collection('files').doc();
    
    final String fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}';
    final String storagePath = 'uploads/${user.uid}/$fileName';
    
    final SettableMetadata metadata = SettableMetadata(
      customMetadata: <String, String>{
        'firestoreDocId': docRef.id,
      },
    );

    final Reference storageRef =
        FirebaseStorage.instance.ref().child(storagePath);
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
        'source': 'upload',
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

  Future<void> _initiateChatPreparation(String documentId) async {
    setState(() {
      _isPreparingChat[documentId] = true;
    });

    await FirebaseFirestore.instance
        .collection('files')
        .doc(documentId)
        .update({'chatStatus': 'preparing'});

    try {
      final summary = await _apiService.prepareChatSession(documentId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document is ready for chat!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      print("Chat preparation successful. Summary length: ${summary.length} characters");
    } catch (e) {
      print("Error preparing chat: $e");
      
      try {
        await FirebaseFirestore.instance
            .collection('files')
            .doc(documentId)
            .update({'chatStatus': 'failed'});
      } catch (updateError) {
        print("Failed to update document status: $updateError");
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to prepare document for chat: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingChat.remove(documentId);
        });
      }
    }
  }

  Future<void> _navigateToChat(String documentId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('files')
          .doc(documentId)
          .get();
      
      if (!doc.exists) {
        throw Exception('Document not found');
      }
      
      final data = doc.data()!;
      final summary = data['summary'] ?? "Summary not found.";
      final fileName = data['originalFileName'] ?? "Unknown file";

      if (!mounted) return;
      
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            documentId: documentId,
            fileName: fileName,
            initialSummary: summary,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open chat: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final result = await ApiService.instance.createSubscriptionOrder(user.uid);
      
      if (!mounted) return;
      Navigator.of(context).pop();
      
      final orderData = Map<String, dynamic>.from(result);
      final options = {
        'key': orderData['razorpayKeyId'],
        'amount': orderData['amount'],
        'name': 'Scan Master',
        'order_id': orderData['orderId'],
        'description': 'Premium Subscription',
        'prefill': {'email': user.email ?? ''}
      };
      _razorpay.open(options);
    } catch (e) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An unexpected error occurred.')),
      );
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
      final String url = await ApiService.instance.getDownloadUrl(documentId);
      
      if (!mounted) return;
      Navigator.of(context).pop(); 

      final Uri uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred: $e')),
      );
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
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await ApiService.instance.deleteFile(documentId);
      
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File deleted successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred: $e')),
      );
    }
  }

  IconData _getIconForFile(String fileName, String? source) {
    // Show scanner icon for scanned documents
    if (source == 'scanner') {
      return Icons.document_scanner;
    }
    
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
    final isChatReady = fileData['isChatReady'] ?? false;

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
          icon: Icon(
            Icons.chat_bubble_outline,
            color: isChatReady ? Colors.green : Colors.purple,
          ),
          tooltip: isChatReady ? 'Chat with AI' : 'Prepare for chat',
          onPressed: () {
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
            title: const Text('My Documents'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: widget.onSignOut ?? () => FirebaseAuth.instance.signOut(),
              ),
              if (isSubscribed)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.0),
                  child: Chip(
                    label: Text(
                      'Premium User',
                      style: TextStyle(color: Colors.white),
                    ),
                    backgroundColor: Colors.amber,
                    avatar: Icon(Icons.star, color: Colors.white),
                  ),
                )
              else
                TextButton(
                  onPressed: _createSubscriptionOrder,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.blue.shade600,
                  ),
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
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.bold,
                    ),
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
                        child: Text('DATABASE ERROR:\n\n${filesSnapshot.error}'),
                      );
                    }
                    if (!filesSnapshot.hasData || filesSnapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.document_scanner,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No documents yet',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Scan or upload your first document to get started',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }
                    final files = filesSnapshot.data!.docs;
                    return ListView.builder(
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final fileDoc = files[index];
                        final fileData = fileDoc.data() as Map<String, dynamic>;
                        final status = fileData['status'] ?? 'Unknown';
                        final source = fileData['source'] as String?;
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
                        
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isCompleted 
                                    ? Colors.green.shade50 
                                    : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                isCompleted
                                    ? Icons.picture_as_pdf
                                    : _getIconForFile(originalFileName, source),
                                color: isCompleted ? Colors.green : Colors.blue,
                                size: 28,
                              ),
                            ),
                            title: Text(
                              displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Status: $status'),
                                if (source == 'scanner')
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Scanned Document',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.purple.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            onTap: isCompleted && (fileData['pdfPath'] != null)
                                ? () => _viewPdf(fileDoc.id)
                                : null,
                            trailing: _buildTrailingWidget(fileData, fileDoc.id),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _uploadTask != null ? null : _showUploadOptions,
            tooltip: 'Add Document',
            icon: _uploadTask != null
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : const Icon(Icons.add),
            label: const Text('Add Document'),
          ),
        );
      },
    );
  }
}