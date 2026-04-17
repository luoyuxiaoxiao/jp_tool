library;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/websocket_service.dart';
import '../utils/shortcut_utils.dart';

class ShortcutConfigScreen extends StatefulWidget {
  const ShortcutConfigScreen({super.key});

  @override
  State<ShortcutConfigScreen> createState() => _ShortcutConfigScreenState();
}

class _ShortcutConfigScreenState extends State<ShortcutConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _captureFocusNode = FocusNode();

  late final TextEditingController _toggleClipboardCtrl;
  late final TextEditingController _toggleGrammarAutoLearnCtrl;
  late final TextEditingController _toggleAutoFollowLunaCtrl;
  late final TextEditingController _submitAnalyzeCtrl;
  late final TextEditingController _focusInputCtrl;

  bool _loading = true;
  bool _saving = false;
  String? _recordingField;

  static const _defaults = ShortcutConfig();

  @override
  void initState() {
    super.initState();
    _toggleClipboardCtrl = TextEditingController();
    _toggleGrammarAutoLearnCtrl = TextEditingController();
    _toggleAutoFollowLunaCtrl = TextEditingController();
    _submitAnalyzeCtrl = TextEditingController();
    _focusInputCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _captureFocusNode.dispose();
    _toggleClipboardCtrl.dispose();
    _toggleGrammarAutoLearnCtrl.dispose();
    _toggleAutoFollowLunaCtrl.dispose();
    _submitAnalyzeCtrl.dispose();
    _focusInputCtrl.dispose();
    super.dispose();
  }

  TextEditingController _controllerForField(String fieldKey) {
    switch (fieldKey) {
      case 'toggleClipboard':
        return _toggleClipboardCtrl;
      case 'toggleGrammarAutoLearn':
        return _toggleGrammarAutoLearnCtrl;
      case 'toggleAutoFollowLuna':
        return _toggleAutoFollowLunaCtrl;
      case 'submitAnalyze':
        return _submitAnalyzeCtrl;
      case 'focusInput':
        return _focusInputCtrl;
      default:
        return _toggleClipboardCtrl;
    }
  }

  void _startRecording(String fieldKey) {
    setState(() => _recordingField = fieldKey);
    _captureFocusNode.requestFocus();
  }

  KeyEventResult _onCaptureKey(FocusNode node, KeyEvent event) {
    final fieldKey = _recordingField;
    if (fieldKey == null) {
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _recordingField = null);
      return KeyEventResult.handled;
    }

    if ((event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete) &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isShiftPressed) {
      final controller = _controllerForField(fieldKey);
      setState(() {
        controller.clear();
        _recordingField = null;
      });
      return KeyEventResult.handled;
    }

    final captured = buildShortcutFromKeyEvent(event);
    if (captured == null || !isValidShortcut(captured)) {
      return KeyEventResult.handled;
    }

    final controller = _controllerForField(fieldKey);
    setState(() {
      controller.text = captured;
      _recordingField = null;
    });

    return KeyEventResult.handled;
  }

  Future<void> _load() async {
    final ws = context.read<WebSocketService>();
    final config = await ws.getShortcutConfig();
    final current = config ?? ws.shortcutConfig;

    if (!mounted) return;
    setState(() {
      _toggleClipboardCtrl.text = current.toggleClipboard;
      _toggleGrammarAutoLearnCtrl.text = current.toggleGrammarAutoLearn;
      _toggleAutoFollowLunaCtrl.text = current.toggleAutoFollowLuna;
      _submitAnalyzeCtrl.text = current.submitAnalyze;
      _focusInputCtrl.text = current.focusInput;
      _loading = false;
    });
  }

  String? _validateShortcut(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '不能为空';
    if (!isValidShortcut(raw)) {
      return '格式无效，例如：ctrl+shift+b 或 ctrl+enter';
    }
    return null;
  }

  ShortcutConfig _buildConfig() {
    return ShortcutConfig(
      toggleClipboard: normalizeShortcutText(_toggleClipboardCtrl.text),
      toggleGrammarAutoLearn:
          normalizeShortcutText(_toggleGrammarAutoLearnCtrl.text),
      toggleAutoFollowLuna:
          normalizeShortcutText(_toggleAutoFollowLunaCtrl.text),
      submitAnalyze: normalizeShortcutText(_submitAnalyzeCtrl.text),
      focusInput: normalizeShortcutText(_focusInputCtrl.text),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final ws = context.read<WebSocketService>();
    final ok = await ws.saveShortcutConfig(_buildConfig());

    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '快捷键保存成功' : '保存失败，请检查后端连接'),
      ),
    );
  }

  void _restoreDefaults() {
    setState(() {
      _toggleClipboardCtrl.text = _defaults.toggleClipboard;
      _toggleGrammarAutoLearnCtrl.text = _defaults.toggleGrammarAutoLearn;
      _toggleAutoFollowLunaCtrl.text = _defaults.toggleAutoFollowLuna;
      _submitAnalyzeCtrl.text = _defaults.submitAnalyze;
      _focusInputCtrl.text = _defaults.focusInput;
    });
  }

  Widget _buildShortcutField({
    required String fieldKey,
    required String title,
    required String hint,
    required TextEditingController controller,
    required String description,
  }) {
    final recording = _recordingField == fieldKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: controller,
                readOnly: true,
                validator: _validateShortcut,
                onTap: () => _startRecording(fieldKey),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: hint,
                  helperText: recording
                      ? '正在录制：请按组合键，Esc取消，Delete清空'
                      : '当前: ${shortcutDisplayText(controller.text)}',
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _startRecording(fieldKey),
              icon: Icon(recording ? Icons.keyboard_hide : Icons.keyboard),
              label: Text(recording ? '录制中' : '录制'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(description,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('快捷键管理')),
      body: Focus(
        focusNode: _captureFocusNode,
        autofocus: true,
        onKeyEvent: _onCaptureKey,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      '点击“录制”后直接按键组合，不建议手动输入，避免格式错误。',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    _buildShortcutField(
                      fieldKey: 'toggleClipboard',
                      title: '切换剪贴板监听',
                      hint: 'ctrl+shift+b',
                      controller: _toggleClipboardCtrl,
                      description: '快速开关后端剪贴板监听。',
                    ),
                    const SizedBox(height: 14),
                    _buildShortcutField(
                      fieldKey: 'toggleGrammarAutoLearn',
                      title: '切换语法自动学习',
                      hint: 'ctrl+shift+g',
                      controller: _toggleGrammarAutoLearnCtrl,
                      description: '快速开关 LLM 语法自动学习并持久化。',
                    ),
                    const SizedBox(height: 14),
                    _buildShortcutField(
                      fieldKey: 'toggleAutoFollowLuna',
                      title: '切换自动跟随Luna',
                      hint: 'ctrl+shift+f',
                      controller: _toggleAutoFollowLunaCtrl,
                      description: '同时开关跟随模式与 Luna 预取。',
                    ),
                    const SizedBox(height: 14),
                    _buildShortcutField(
                      fieldKey: 'submitAnalyze',
                      title: '提交当前输入进行解析',
                      hint: 'ctrl+enter',
                      controller: _submitAnalyzeCtrl,
                      description: '触发主界面输入框提交。',
                    ),
                    const SizedBox(height: 14),
                    _buildShortcutField(
                      fieldKey: 'focusInput',
                      title: '聚焦输入框',
                      hint: 'ctrl+l',
                      controller: _focusInputCtrl,
                      description: '把光标快速移动到输入框。',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _restoreDefaults,
                          icon: const Icon(Icons.refresh),
                          label: const Text('恢复默认'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save),
                          label: Text(_saving ? '保存中...' : '保存快捷键'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
