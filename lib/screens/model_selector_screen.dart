import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/model_info.dart';
import '../providers/model_provider.dart';
import '../providers/conversation_provider.dart';

class ModelSelectorScreen extends ConsumerStatefulWidget {
  const ModelSelectorScreen({super.key});

  @override
  ConsumerState<ModelSelectorScreen> createState() => _ModelSelectorScreenState();
}

class _ModelSelectorScreenState extends ConsumerState<ModelSelectorScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customModelController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  void _selectModel(ModelInfo model) {
    ref.read(modelProvider.notifier).selectModel(model);

    // Sync with active conversation if exists
    final activeConv = ref.read(conversationProvider).activeConversation;
    if (activeConv != null) {
      ref.read(conversationProvider.notifier).updateConversation(
        activeConv.copyWith(modelId: model.id),
      );
    }

    Navigator.pop(context);
  }

  void _handleAddCustomModel() {
    final customId = _customModelController.text.trim();
    if (customId.isEmpty) return;

    ref.read(modelProvider.notifier).addCustomModel(customId);
    
    // Auto select the newly added custom model
    final addedModel = ref.read(modelProvider).models.firstWhere((m) => m.id == customId);
    _selectModel(addedModel);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(modelProvider);
    final theme = Theme.of(context);

    // Filter models
    final filteredModels = state.models.where((model) {
      final nameMatches = model.modelName.toLowerCase().contains(_searchQuery);
      final idMatches = model.id.toLowerCase().contains(_searchQuery);
      final providerMatches = model.provider.toLowerCase().contains(_searchQuery);
      return nameMatches || idMatches || providerMatches;
    }).toList();

    // Group models by provider
    final Map<String, List<ModelInfo>> groupedModels = {};
    for (final model in filteredModels) {
      final provider = model.provider.toUpperCase();
      groupedModels.putIfAbsent(provider, () => []).add(model);
    }

    final providers = groupedModels.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Model'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(modelProvider.notifier).fetchModels(),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search Input
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search models...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                ),

                // Custom Model Register Input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customModelController,
                          decoration: InputDecoration(
                            hintText: 'Enter custom model ID (e.g. openai/gpt-4o)...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _handleAddCustomModel,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Model lists grouped by provider
                Expanded(
                  child: state.error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              state.error!,
                              style: TextStyle(color: theme.colorScheme.error),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : filteredModels.isEmpty
                          ? const Center(child: Text('No models found'))
                          : ListView.builder(
                              itemCount: providers.length,
                              itemBuilder: (context, providerIdx) {
                                final provider = providers[providerIdx];
                                final providerModels = groupedModels[provider]!;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Provider Header
                                    Container(
                                      width: double.infinity,
                                      color: theme.colorScheme.brightness == Brightness.light
                                          ? Colors.grey[200]
                                          : Colors.grey[900],
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      child: Text(
                                        provider,
                                        style: theme.textTheme.labelMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.outline,
                                        ),
                                      ),
                                    ),
                                    // Models in this provider
                                    ...providerModels.map((model) {
                                      final isSelected = state.selectedModel?.id == model.id;
                                      return ListTile(
                                        title: Text(
                                          model.modelName,
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                        subtitle: Text(
                                          model.id,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.outline,
                                          ),
                                        ),
                                        trailing: Wrap(
                                          spacing: 6,
                                          children: [
                                            if (model.supportsVision)
                                              const Chip(
                                                label: Text('Vision'),
                                                labelStyle: TextStyle(fontSize: 10),
                                                padding: EdgeInsets.zero,
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            if (model.supportsTools)
                                              const Chip(
                                                label: Text('Tools'),
                                                labelStyle: TextStyle(fontSize: 10),
                                                padding: EdgeInsets.zero,
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            if (isSelected)
                                              Icon(Icons.check, color: theme.colorScheme.primary),
                                          ],
                                        ),
                                        onTap: () => _selectModel(model),
                                      );
                                    }),
                                  ],
                                );
                              },
                            ),
                ),
              ],
            ),
    );
  }
}
