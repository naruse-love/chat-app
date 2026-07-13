import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_service.dart';

class ChatInput extends StatefulWidget {
  final Function(String text, String? imagePath) onSend;
  final VoidCallback? onTyping;
  final ImageService? imageService;
  final bool supportsVision;

  const ChatInput({
    super.key,
    required this.onSend,
    this.onTyping,
    this.imageService,
    this.supportsVision = true,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _selectedImagePath;
  bool _isSending = false;
  late final ImageService _imageService;

  @override
  void initState() {
    super.initState();
    _imageService = widget.imageService ?? ImageService();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (widget.onTyping != null && _controller.text.isNotEmpty) {
      widget.onTyping!();
    }
    setState(() {}); // Rebuild to toggle send button state
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final path = await _imageService.pickImage(source: source);
      if (path != null) {
        setState(() {
          _selectedImagePath = path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选取图片出错: $e')),
        );
      }
    }
  }

  void _removeSelectedImage() {
    setState(() {
      _selectedImagePath = null;
    });
  }

  void _handleSend() {
    final text = _controller.text.trim();
    final imagePath = _selectedImagePath;
    
    if (text.isEmpty && imagePath == null) return;
    
    setState(() {
      _isSending = true;
    });
    
    widget.onSend(text, imagePath);
    
    _controller.clear();
    setState(() {
      _selectedImagePath = null;
      _isSending = false;
    });
    _focusNode.requestFocus();
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照 (相机)'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择 (相册)'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasInput = _controller.text.trim().isNotEmpty || _selectedImagePath != null;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4.0,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Selected Image Preview Panel
            if (_selectedImagePath != null)
              Container(
                height: 100,
                padding: const EdgeInsets.only(bottom: 8.0, left: 8.0, right: 8.0),
                alignment: Alignment.centerLeft,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Image.file(
                        File(_selectedImagePath!),
                        height: 90,
                        width: 90,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: _removeSelectedImage,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4.0),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            
            // Input Controls row
            Row(
              children: [
                // Media Picker Button (always active, validation occurs at send time)
                IconButton(
                  icon: Icon(
                    Icons.add_photo_alternate_outlined,
                    color: widget.supportsVision ? theme.colorScheme.primary : theme.colorScheme.outline,
                  ),
                  onPressed: () {
                    if (!widget.supportsVision) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('当前模型不支持图片输入，请选择支持 Vision 的模型。')),
                      );
                      return;
                    }
                    _showImagePickerOptions();
                  },
                  tooltip: '添加图片',
                ),
                
                // Text Area
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.brightness == Brightness.light
                          ? Colors.grey[200]
                          : Colors.grey[800],
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: '输入消息...',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10.0),
                      ),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
                
                const SizedBox(width: 8.0),
                
                // Send Button
                GestureDetector(
                  onTap: hasInput && !_isSending ? _handleSend : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: hasInput && !_isSending
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(10.0),
                    child: Icon(
                      Icons.send,
                      color: hasInput && !_isSending
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.outline,
                      size: 20.0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
