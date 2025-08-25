
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cadmo/vars/theme.dart';
import 'package:go_router/go_router.dart';
import 'package:cadmo/services/database_service.dart';
import 'package:cadmo/services/llm_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;


// --- SERVICES ---

class FileService {
  Future<String> getModelsDirectory() async {
    final docDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(docDir.path, 'Cadmo', 'Models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir.path;
  }

  Future<bool> modelExists(String fileName) async {
    final modelsPath = await getModelsDirectory();
    final filePath = p.join(modelsPath, fileName);
    return File(filePath).exists();
  }

  Future<void> deleteModel(String fileName) async {
    try {
      final modelsPath = await getModelsDirectory();
      final file = File(p.join(modelsPath, fileName));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Handle or log error
    }
  }
}

class DownloadService {
  // final Dio _dio = Dio(); // Removed as it's unused for now
  // Placeholder for download logic
}

// --- MAIN APP ---

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService().initDb();
  runApp(const MyApp());
}

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => ChatScreen(chatUuid: state.extra as String?),
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      title: 'Cadmo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: primaryColor,
        scaffoldBackgroundColor: primaryColor,
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
        useMaterial3: true,
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String? chatUuid;
  const ChatScreen({super.key, this.chatUuid});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final LLMManager _llmService = LLMManager();
  final DatabaseService _dbService = DatabaseService();
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  

  @override
  void initState() {
    super.initState();
    _loadDefaultModel(); // Call to load default model
    if (widget.chatUuid != null) {
      // Load existing chat messages here
    }
  }

  @override
  void dispose() {
    _llmService.dispose_model(); // Call the new dispose method
    super.dispose();
  }

  // New method to load default model
  void _loadDefaultModel() async {
    const defaultModelName = 'Balanced'; // Or retrieve from preferences
    final modelFileName = _SettingsDialogState.modelDetails[defaultModelName]!['file']!;
    final fileService = FileService();
    final modelExists = await fileService.modelExists(modelFileName);

    if (modelExists) {
      try {
        await _llmService.initModel(modelFileName);
        // Optionally, add a message to the chat indicating model loaded
        // setState(() {
        //   _messages.add(ChatMessage(isUserService: false, message: 'Model "$defaultModelName" loaded.'));
        // });
      } catch (e) {
        // Handle error during model loading
        setState(() {
          _messages.add(ChatMessage(isUserMessage: false, message: 'Error loading model: $e'));
        });
      }
    } else {
      // Inform user that default model is not downloaded
      setState(() {
        _messages.add(ChatMessage(isUserMessage: false, message: 'Default model "$defaultModelName" not found. Please download it from settings.'));
      });
    }
  }

  void _handleSendPressed() async {
    final text = _textController.text;
    if (text.isEmpty || widget.chatUuid == null) return;

    _textController.clear();
    final userMessage = ChatMessage(isUserMessage: true, message: text);
    final aiMessage = ChatMessage(isUserMessage: false, message: ''); // Placeholder for AI response

    setState(() {
      _messages.add(userMessage);
      _messages.add(aiMessage); // Add placeholder for AI response
      _isTyping = true;
    });

    await _dbService.addInteraction({
      'chat_uuid': widget.chatUuid,
      'role': 'user',
      'content': text,
      'sender': 'user'
    });

    final List<Map<String, String>> conversation = _messages.map((msg) {
      return {
        'role': msg.isUserMessage ? 'user' : 'assistant',
        'content': msg.message,
      };
    }).toList();

    // Use the new streaming method
    try {
      await for (final token in _llmService.ai_interact_stream(conversation)) {
        setState(() {
          if (_messages.isNotEmpty && !_messages.last.isUserMessage) {
            final updatedMessage = _messages.last.message + token;
            _messages[_messages.length - 1] = ChatMessage(isUserMessage: false, message: updatedMessage);
          } else {
            // This case should ideally not happen if _isTyping is true and an AI message was added.
            // Add a new AI message if for some reason it's missing.
            _messages.add(ChatMessage(isUserMessage: false, message: token));
          }
        });
      }
      // On done
      setState(() {
        _isTyping = false;
      });
      if (_messages.isNotEmpty && !_messages.last.isUserMessage) {
        await _dbService.addInteraction({
          'chat_uuid': widget.chatUuid,
          'role': 'assistant',
          'content': _messages.last.message,
          'sender': 'assistant'
        });
      }
    } catch (error) {
      // On error
      setState(() {
        _isTyping = false;
        _messages.add(ChatMessage(isUserMessage: false, message: 'Error: $error'));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: Builder(
          builder: (context) => Tooltip(
            message: 'Open menu',
            child: IconButton(
              icon: const Icon(Icons.menu, color: Colors.black),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
          ),
        ),
        title: Image.asset('assets/images/name.png', height: 24),
        centerTitle: true,
        actions: const [],
      ),
      drawer: const AppDrawer(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isLargeScreen = constraints.maxWidth > 600;
          return Center(
            child: Container(
              width: isLargeScreen ? constraints.maxWidth * 0.5 : constraints.maxWidth,
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) => _messages[index],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _textController,
                          decoration: InputDecoration(
                            hintText: 'Type your message...',
                            border: OutlineInputBorder(
                              borderRadius: const BorderRadius.all(Radius.circular(20.0)),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: const BorderRadius.all(Radius.circular(20.0)),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: const BorderRadius.all(Radius.circular(20.0)),
                              borderSide: BorderSide(color: accentColor),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16.0),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Tooltip(
                                  message: 'Settings',
                                  child: IconButton(
                                    icon: const Icon(Icons.settings_outlined),
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => const SettingsDialog(),
                                      );
                                    },
                                  ),
                                ),
                                Tooltip(
                                  message: 'Add',
                                  child: IconButton(icon: const Icon(Icons.add), onPressed: () {}),
                                ),
                              ],
                            ),
                            Tooltip(
                              message: 'Send',
                              child: Container(
                                decoration: const BoxDecoration(color: Color(0xFF7DA5A3), shape: BoxShape.circle),
                                child: IconButton(
                                  icon: const Icon(Icons.arrow_upward, color: Colors.white),
                                  onPressed: _isTyping ? null : _handleSendPressed,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final FileService _fileService = FileService();
  final LLMManager _llmService = LLMManager();
  String _selectedModel = 'Balanced';
  bool? _isModelDownloaded;
  bool _isDeleting = false;
  bool _isLoadingModel = false;
  double _shortTermMemory = 10;
  double _longTermMemory = 5;

  static const Map<String, Map<String, String>> modelDetails = {
    'Lightning': {'size': '792.2 MB', 'file': 'DeepSeek-R1-Distill-Qwen-1.5B-UD-IQ2_M.gguf'},
    'Fast': {'size': '924.5 MB', 'file': 'DeepSeek-R1-Distill-Qwen-1.5B-Q3_K_M.gguf'},
    'Balanced': {'size': '1.12 GB', 'file': 'DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf'},
    'Smart': {'size': '5.03 GB', 'file': 'DeepSeek-R1-0528-Qwen3-8B-Q4_K_M.gguf'},
    'Expert': {'size': '7.49 GB', 'file': 'DeepSeek-R1-0528-Qwen3-8B-UD-Q6_K_XL.gguf'},
    'Genius': {'size': '10.82 GB', 'file': 'DeepSeek-R1-0528-Qwen3-8B-UD-Q8_K_XL.gguf'},
  };

  @override
  void initState() {
    super.initState();
    _checkModelStatus(_selectedModel);
  }

  void _checkModelStatus(String modelName) async {
    setState(() {
      _isModelDownloaded = null;
    });
    final fileName = modelDetails[modelName]!['file']!;
    final exists = await _fileService.modelExists(fileName);
    setState(() {
      _isModelDownloaded = exists;
    });
  }

  void _deleteSelectedModel() async {
    setState(() {
      _isDeleting = true;
    });
    final fileName = modelDetails[_selectedModel]!['file']!;
    await _fileService.deleteModel(fileName);
    setState(() {
      _isModelDownloaded = false;
      _isDeleting = false;
    });
  }

  void _handleAccept() async {
    final modelFileName = modelDetails[_selectedModel]!['file']!;
    if (_isModelDownloaded == true) {
      setState(() { _isLoadingModel = true; });
      try {
        await _llmService.initModel(modelFileName);
      } catch (e) {
        // Handle error
      }
      setState(() { _isLoadingModel = false; });
      Navigator.of(context).pop();
    } else {
      // Start download logic here
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width > 600;
    final currentModelDetails = modelDetails[_selectedModel]!;

    return Dialog(
      child: AbsorbPointer(
        absorbing: _isLoadingModel,
        child: Container(
          width: isLargeScreen ? MediaQuery.of(context).size.width * 0.5 : null,
          padding: const EdgeInsets.all(24.0),
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _selectedModel,
                      decoration: const InputDecoration(labelText: 'Model'),
                      items: modelDetails.keys.map((label) => DropdownMenuItem(value: label, child: Text(label))).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedModel = value;
                          });
                          _checkModelStatus(value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildStatusRow(currentModelDetails),
                    const SizedBox(height: 24),
                    const TextField(decoration: InputDecoration(labelText: 'System Prompt', border: OutlineInputBorder()), maxLines: 3),
                    const SizedBox(height: 24),
                    Text('Short-Term Memory Interactions: ${_shortTermMemory.toInt()}'),
                    Slider(value: _shortTermMemory, min: 0, max: 20, divisions: 20, label: _shortTermMemory.round().toString(), onChanged: (v) => setState(() => _shortTermMemory = v)),
                    const SizedBox(height: 16),
                    Text('Long-Term Memory Recalls: ${_longTermMemory.toInt()}'),
                    Slider(value: _longTermMemory, min: 0, max: 10, divisions: 10, label: _longTermMemory.round().toString(), onChanged: (v) => setState(() => _longTermMemory = v)),
                    const SizedBox(height: 24),
                    const Text('All processing is done privately and securely on your device, not in the cloud.', style: TextStyle(fontSize: 12, color: Colors.black), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    const Text('Powered by DeepSeek R1 Distill Qwen and Mixedbread Embedding open source models.', style: TextStyle(fontSize: 12, color: Colors.black), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Center(child: TextButton(onPressed: () => showLicensePage(context: context), child: const Text('View Project Licenses'))),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                        const SizedBox(width: 8),
                        ElevatedButton(onPressed: _handleAccept, child: const Text('Accept')),
                      ],
                    )
                  ],
                ),
              ),
              if (_isLoadingModel)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [CircularProgressIndicator(), SizedBox(height: 8), Text('Loading Model...')],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow(Map<String, String> details) {
    if (_isModelDownloaded == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('${details['size']} - ${_isModelDownloaded! ? "Downloaded" : "Not Downloaded"}'),
        if (_isModelDownloaded!)
          _isDeleting
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
              : IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deleteSelectedModel, tooltip: 'Delete Model'),
      ],
    );
  }
}

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  late Future<List<Map<String, dynamic>>> _chatsFuture;

  @override
  void initState() {
    super.initState();
    _chatsFuture = _loadChats();
  }

  Future<List<Map<String, dynamic>>> _loadChats() {
    return DatabaseService().getChats();
  }

  void _refreshChats() {
    setState(() {
      _chatsFuture = _loadChats();
    });
  }

  void _showNewChatDialog(BuildContext context) {
    final TextEditingController titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Chat'),
          content: TextField(
            controller: titleController,
            decoration: const InputDecoration(hintText: "Enter chat title"),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isNotEmpty) {
                  await DatabaseService().createNewChat(titleController.text);
                  _refreshChats();
                  if (!mounted) return;
        Navigator.of(context).pop();
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 40.0, 16.0, 16.0),
            child: Row(
              children: [
                Image.asset('assets/images/name.png', height: 24),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: TextButton.icon(
              onPressed: () => _showNewChatDialog(context),
              icon: Container(
                padding: const EdgeInsets.all(8.0),
                decoration: const BoxDecoration(
                  color: Color(0xFF7DA5A2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 18),
              ),
              label: const Text('New Chat', style: TextStyle(color: Colors.black)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.all(12.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent Chats', style: TextStyle(fontWeight: FontWeight.bold)),
                Tooltip(
                  message: 'Refresh',
                  child: IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _refreshChats,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _chatsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Error loading chats'));
                }
                final chats = snapshot.data ?? [];
                if (chats.isEmpty) {
                  return const Center(child: Text('No recent chats'));
                }
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return ListTile(
                      title: Text(chat['title']),
                      onTap: () {
                        context.go('/', extra: chat['uuid']);
                        if (!mounted) return;
        Navigator.of(context).pop(); // Close drawer
                      },
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7DA5A2),
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: () {
                _showDevicesBottomSheet(context);
              },
              icon: const Icon(Icons.devices),
              label: const Text('This Device'),
            ),
          ),
        ],
      ),
    );
  }

  void _showDevicesBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.phone_iphone),
                title: const Text('iPhone 15 Pro'),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.desktop_mac),
                title: const Text('Macbook Pro'),
                onTap: () {},
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Add Device'),
                onTap: () {},
              ),
            ],
          ),
        );
      },
    );
  }
}

class ChatMessage extends StatelessWidget {
  final bool isUserMessage;
  final String message; // Made final

  const ChatMessage({ // Made const
    super.key,
    required this.isUserMessage,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(12.0),
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        decoration: BoxDecoration(
          color: isUserMessage ? accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Text(
          message,
          style: const TextStyle(color: Colors.black),
        ),
      ),
    );
  }
}
