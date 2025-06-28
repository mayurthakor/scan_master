// lib/features/home/presentation/widgets/document_list_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/home_bloc.dart';

class DocumentListWidget extends StatelessWidget {
  const DocumentListWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (context, state) {
        if (state is HomeLoading) {
          return const Center(child: CircularProgressIndicator());
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
        
        if (state is HomeLoaded) {
          if (state.documents.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.description, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No documents yet'),
                  SizedBox(height: 8),
                  Text('Tap + to add your first document'),
                ],
              ),
            );
          }
          
          return ListView.builder(
            itemCount: state.documents.length,
            itemBuilder: (context, index) {
              final document = state.documents[index];
              return ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: Text(document['name'] ?? 'Untitled'),
                subtitle: Text(document['status'] ?? 'Unknown'),
                onTap: () {
                  // TODO: Navigate to document detail
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    context.read<HomeBloc>().add(
                      DocumentDeleteRequested(document['id'] ?? ''),
                    );
                  },
                ),
              );
            },
          );
        }
        
        return const SizedBox.shrink();
      },
    );
  }
}