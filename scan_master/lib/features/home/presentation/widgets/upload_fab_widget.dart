// lib/features/home/presentation/widgets/upload_fab_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/home_bloc.dart';

class UploadFabWidget extends StatelessWidget {
  const UploadFabWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (context, state) {
        // Disable upload if already uploading
        final isUploading = state is HomeLoaded && state.uploadTask != null;
        
        return FloatingActionButton.extended(
          onPressed: isUploading ? null : () {
            _showUploadOptions(context);
          },
          icon: isUploading 
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.upload_file),
          label: Text(isUploading ? 'Uploading...' : 'Upload'),
        );
      },
    );
  }

  void _showUploadOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bottomSheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.file_upload),
                title: const Text('Upload from Files'),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  // Use the original context that has access to HomeBloc
                  context.read<HomeBloc>().add(UploadFileRequested());
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Scan Document'),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  // This would navigate to camera screen
                  // The camera screen would then trigger ScannedDocumentUpload event
                  _navigateToCamera(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _navigateToCamera(BuildContext context) {
    // This would navigate to your camera page
    // After scanning, the camera page would call:
    // context.read<HomeBloc>().add(ScannedDocumentUpload(imagePath));
    
    // For now, just show a placeholder
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Camera feature integration coming next!'),
      ),
    );
  }
}