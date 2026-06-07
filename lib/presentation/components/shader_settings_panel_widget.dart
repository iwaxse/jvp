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
import '../../application/app_event_bus.dart';
import '../../application/commands/set_effect_command.dart';
import '../video_player_view_model.dart';

class ShaderSettingsPanelWidget extends StatelessWidget {
  final VoidCallback? onClose;
  final bool embedded;

  const ShaderSettingsPanelWidget({
    super.key,
    this.onClose,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<VideoPlayerViewModel>();

    final body = SafeArea(
      child: Column(
        children: [
          if (!embedded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Engine Tuner',
                    style: TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: onClose,
                    ),
                ],
              ),
            ),
          if (!embedded) const Divider(color: Color(0xFF333333), height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  _buildSectionHeader('Detail Enhance'),
                  _buildSlider(
                    context,
                    viewModel,
                    id: 'super_res',
                    name: 'ULTRA RES (RCAS)',
                  ),
                  _buildSlider(
                    context,
                    viewModel,
                    id: 'deband',
                    name: 'DEBAND (DITHER)',
                  ),
                  _buildSlider(
                    context,
                    viewModel,
                    id: 'smooth',
                    name: 'SMOOTH SKIN',
                  ),
                  _buildSharpenWithSelector(context, viewModel),
                  _buildSlider(
                    context,
                    viewModel,
                    id: 'unsharp',
                    name: 'UNSHARP MASK',
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('Color & Toning'),
                  _buildSlider(
                    context,
                    viewModel,
                    id: 'hdr',
                    name: 'HDR DYNAMIC',
                  ),
                  _buildSlider(
                    context,
                    viewModel,
                    id: 'cleancinema',
                    name: 'CLEAN CINEMA',
                  ),
                  _buildSlider(
                    context,
                    viewModel,
                    id: 'vintage',
                    name: 'VINTAGE',
                  ),
                  _buildSlider(
                    context,
                    viewModel,
                    id: 'cyberpunk',
                    name: 'CYBERPUNK',
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('Atmosphere'),
                  _buildSlider(
                    context,
                    viewModel,
                    id: 'bloom',
                    name: 'BLOOM / GLOW',
                  ),
                  _buildSlider(context, viewModel, id: 'blur', name: 'BLUR'),
                  _buildSlider(
                    context,
                    viewModel,
                    id: 'vignette',
                    name: 'VIGNETTE',
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (embedded) {
      return Container(color: const Color(0xFF141414), child: body);
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(left: BorderSide(color: Color(0xFF333333))),
      ),
      child: body,
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFD4AF37),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 2.0,
        ),
      ),
    );
  }

  Widget _buildSlider(
    BuildContext context,
    VideoPlayerViewModel viewModel, {
    required String id,
    required String name,
  }) {
    final value = context.select<VideoPlayerViewModel, double>(
      (vm) => vm.getEffect(id),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
              ),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 11),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: const Color(0xFFD4AF37),
              inactiveTrackColor: const Color(0xFF333333),
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
              value: value,
              min: 0.0,
              max: 1.0,
              onChanged: (val) {
                context.read<AppEventBus>().publish(
                  SetEffectCommand(effect: id, intensity: val),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharpenWithSelector(
    BuildContext context,
    VideoPlayerViewModel viewModel,
  ) {
    final value = context.select<VideoPlayerViewModel, double>(
      (vm) => vm.getEffect('sharpen'),
    );
    final isLaplacian = context.select<VideoPlayerViewModel, bool>(
      (vm) => vm.getEffect('sharpen_type') > 0.5,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'SHARPEN',
                    style: TextStyle(color: Color(0xFF888888), fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<double>(
                    focusNode: FocusNode(
                      canRequestFocus: false,
                      skipTraversal: true,
                    ),
                    value: isLaplacian ? 1.0 : 0.0,
                    dropdownColor: const Color(0xFF141414),
                    underline: const SizedBox(),
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Color(0xFFD4AF37),
                      size: 16,
                    ),
                    style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 10,
                    ),
                    items: const [
                      DropdownMenuItem(value: 0.0, child: Text('CAS')),
                      DropdownMenuItem(value: 1.0, child: Text('LAP')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        context.read<AppEventBus>().publish(
                          SetEffectCommand(
                            effect: 'sharpen_type',
                            intensity: val,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 11),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: const Color(0xFFD4AF37),
              inactiveTrackColor: const Color(0xFF333333),
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
              value: value,
              min: 0.0,
              max: 1.0,
              onChanged: (val) {
                context.read<AppEventBus>().publish(
                  SetEffectCommand(effect: 'sharpen', intensity: val),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
