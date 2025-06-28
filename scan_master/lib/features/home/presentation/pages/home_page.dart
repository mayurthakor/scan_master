// lib/features/home/presentation/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection_container.dart' as di;
import '../bloc/home_bloc.dart';
import '../widgets/home_app_bar.dart';
import '../widgets/document_list_widget.dart';
import '../widgets/upload_fab_widget.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // Get HomeBloc from dependency injection
      create: (context) => di.sl<HomeBloc>()..add(HomeStarted()),
      child: const HomeView(),
    );
  }
}

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const HomeAppBar(),
      body: BlocConsumer<HomeBloc, HomeState>(
        listener: (context, state) {
          // Handle state changes that need user feedback
          if (state is HomeError) {
            if (state.message.contains('Upload limit reached')) {
              // Show subscription dialog for upload limit
              _showSubscriptionDialog(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
          
          if (state is DocumentDeleted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
          }
          
          if (state is UploadLimitReached) {
            _showSubscriptionDialog(context);
          }
        },
        builder: (context, state) {
          if (state is HomeLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          
          if (state is HomeLoaded) {
            return Column(
              children: [
                // Upload progress indicator
                if (state.uploadTask != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('Uploading...'),
                        const SizedBox(height: 8),
                        StreamBuilder(
                          stream: state.uploadTask!.snapshotEvents,
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              final progress = snapshot.data!.bytesTransferred / 
                                             snapshot.data!.totalBytes;
                              return LinearProgressIndicator(value: progress);
                            }
                            return const LinearProgressIndicator();
                          },
                        ),
                      ],
                    ),
                  ),
                
                // User stats
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('Uploads: ${state.uploadCount}/${state.uploadLimit}'),
                      Text(state.isSubscribed ? 'Subscribed ✅' : 'Free Account'),
                    ],
                  ),
                ),
                
                // Document list
                Expanded(
                  child: DocumentListWidget(
                    documents: state.documents,
                    preparingChat: state.preparingChat,
                  ),
                ),
              ],
            );
          }
          
          if (state is UploadLimitReached) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_upload, size: 64, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text(
                    'Upload Limit Reached',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You have reached your upload limit.\nSubscribe to get unlimited uploads!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      context.read<HomeBloc>().add(SubscriptionOrderRequested());
                    },
                    child: const Text('Subscribe Now'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      context.read<HomeBloc>().add(HomeStarted());
                    },
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }
          
          if (state is HomeError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(state.message),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context.read<HomeBloc>().add(HomeStarted());
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          
          // Default case - should not happen, but fallback to loading
          return const Center(child: CircularProgressIndicator());
        },
      ),
      floatingActionButton: const UploadFabWidget(),
    );
  }

  void _showSubscriptionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Upload Limit Reached'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload, size: 48, color: Colors.orange),
            SizedBox(height: 16),
            Text(
              'You have reached your upload limit of 5 documents.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Subscribe to get unlimited uploads and access to premium features!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // Use the original context that has access to HomeBloc
              context.read<HomeBloc>().add(SubscriptionOrderRequested());
            },
            child: const Text('Subscribe Now'),
          ),
        ],
      ),
    );
  }
}