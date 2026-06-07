/*
 * jvp (Jamy-chan Video Player)
 * Copyright (C) 2026 iwaxse
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../video_player_view_model.dart';
import 'file_browser_tab_widget.dart';
import 'playlist_tab_widget.dart';
import 'shader_settings_panel_widget.dart';

class RightSidebarPanelWidget extends StatefulWidget {
  final int initialTabIndex;
  final VoidCallback onClose;
  final ValueChanged<int> onTabChanged;

  const RightSidebarPanelWidget({
    super.key,
    required this.initialTabIndex,
    required this.onClose,
    required this.onTabChanged,
  });

  @override
  State<RightSidebarPanelWidget> createState() =>
      _RightSidebarPanelWidgetState();
}

class _RightSidebarPanelWidgetState extends State<RightSidebarPanelWidget>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        widget.onTabChanged(_tabController.index);
      }
    });
  }

  @override
  void didUpdateWidget(covariant RightSidebarPanelWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = widget.initialTabIndex.clamp(0, 2);
    if (_tabController.index != nextIndex) {
      _tabController.animateTo(nextIndex);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF141414),
          border: Border(left: BorderSide(color: Color(0xFF333333))),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Library',
                        style: TextStyle(
                          color: Color(0xFFEAEAEA),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(
                        Icons.close,
                        color: Color(0xFFB9B9B9),
                        size: 20,
                      ),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFFD4AF37),
                labelColor: const Color(0xFFD4AF37),
                unselectedLabelColor: const Color(0xFF8A8A8A),
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: 'Files'),
                  Tab(text: 'Playlist'),
                  Tab(text: 'Tuner'),
                ],
              ),
              const Divider(color: Color(0xFF333333), height: 1),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    FileBrowserTabWidget(onSettingsPressed: _openRootSettings),
                    const PlaylistTabWidget(),
                    const ShaderSettingsPanelWidget(embedded: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRootSettings() async {
    final viewModel = context.read<VideoPlayerViewModel>();
    final rootController = TextEditingController();
    final roots = List<String>.from(viewModel.mediaSearchRoots);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> addRoot() async {
              final value = rootController.text.trim();
              if (value.isEmpty) return;
              setState(() {
                if (!roots.contains(value)) {
                  roots.add(value);
                }
                rootController.clear();
              });
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF171717),
              title: const Text(
                'Media folders',
                style: TextStyle(color: Color(0xFFEFEFEF)),
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: rootController,
                      style: const TextStyle(color: Color(0xFFEFEFEF)),
                      decoration: InputDecoration(
                        hintText: 'Enter a folder path',
                        hintStyle: const TextStyle(color: Color(0xFF666666)),
                        filled: true,
                        fillColor: const Color(0xFF101010),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF333333),
                          ),
                        ),
                      ),
                      onSubmitted: (_) => addRoot(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 320,
                      child: ListView.separated(
                        itemCount: roots.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final root = roots[index];
                          return Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF101010),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF2F2F2F),
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                root,
                                style: const TextStyle(
                                  color: Color(0xFFEFEFEF),
                                  fontSize: 12,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Color(0xFFB56B6B),
                                ),
                                onPressed: () {
                                  setState(() {
                                    roots.removeAt(index);
                                  });
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(onPressed: addRoot, child: const Text('Add')),
                ElevatedButton(
                  onPressed: () async {
                    await viewModel.updateMediaSearchRoots(roots);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: const Color(0xFF101010),
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
