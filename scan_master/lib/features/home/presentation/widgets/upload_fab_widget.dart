import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../bloc/home_bloc.dart';
import '../../../camera/presentation/pages/camera_page.dart';

class UploadFabWidget extends StatelessWidget {
  const UploadFabWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _showUploadOptions(context),
      tooltip: 'Add Document',
      icon: const Icon(Icons.add),
      label: const Text('Add'),
    );
  }

  void _showUploadOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera Scanner'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => CameraPage(
                        onImageCaptured: (imagePath) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Image captured: $imagePath')),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_upload),
                title: const Text('Upload File'),
                onTap: () {
                  Navigator.pop(context);
                  _uploadFile(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat),
                title: const Text('Chat with AI'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Navigate to chat screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Chat feature - to be implemented')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _uploadFile(BuildContext context) async {
    try {
      // Pick file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name;
        
        // Show upload started message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploading $fileName...')),
        );

        // Trigger upload via BLoC
        context.read<HomeBloc>().add(UploadFileRequested());
        
        // TODO: Implement actual file upload logic
        // For now, just show success message
        await Future.delayed(const Duration(seconds: 2));
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$fileName uploaded successfully!')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }
}