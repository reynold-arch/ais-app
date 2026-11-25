import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:highlight/languages/all.dart' show allLanguages;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const AisApp());
}

// ---------------- Theme wrapper ----------------

class AisApp extends StatefulWidget {
  const AisApp({super.key});
  @override
  State<AisApp> createState() => _AisAppState();
}

class _AisAppState extends State<AisApp> {
  bool isDark = true;

  void toggleTheme(bool dark) {
    setState(() => isDark = dark);
  }

  ThemeData _buildTheme(bool dark) {
    final primary = dark ? const Color(0xFF6DB89F) : const Color(0xFF2F6B57);
    final onPrimary = dark ? const Color(0xFF10231C) : const Color(0xFFFFFFFF);
    final secondary = dark ? const Color(0xFF3A352B) : const Color(0xFFE9E1CF);
    final accent = dark ? const Color(0xFFE0765C) : const Color(0xFFC4553B);
    final bg = dark ? const Color(0xFF1B1A17) : const Color(0xFFF3F0E8);
    final surface = dark ? const Color(0xFF24221E) : const Color(0xFFFFFFFF);
    final text = dark ? const Color(0xFFF1ECE0) : const Color(0xFF1E1C18);
    final muted = dark ? const Color(0xFFA39D8E) : const Color(0xFF6B665C);
    final border = dark ? const Color(0xFF3A372F) : const Color(0xFFDDD6C6);
    final brightness = dark ? Brightness.dark : Brightness.light;
    final base = ThemeData(brightness: brightness);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: secondary,
      onSecondary: text,
      tertiary: accent,
      onTertiary: onPrimary,
      error: accent,
      onError: onPrimary,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: muted,
      outline: border,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      primaryColor: primary,
      dividerColor: border,
      hintColor: muted,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      textTheme: GoogleFonts.instrumentSansTextTheme(base.textTheme)
          .apply(bodyColor: text, displayColor: text),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? surface : secondary,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineWidth: const WidgetStatePropertyAll(1.5),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? primary : border),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? primary : surface),
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? onPrimary : muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(48, 48),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AIS',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(isDark),
      home: ChatScreen(isDark: isDark, onToggleTheme: toggleTheme),
    );
  }
}

// ---------------- Data models ----------------

class ChatMessage {
  final String role; // "user", "assistant", "system"
  String content;
  String? modelLabel;
  String? modelId;
  double? costEstimate;
  bool isStreaming;

  ChatMessage({
    required this.role,
    required this.content,
    this.modelLabel,
    this.modelId,
    this.costEstimate,
    this.isStreaming = false,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'modelLabel': modelLabel,
        'modelId': modelId,
        'costEstimate': costEstimate,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: j['role'] as String,
        content: j['content'] as String,
        modelLabel: j['modelLabel'] as String?,
        modelId: j['modelId'] as String?,
        costEstimate: (j['costEstimate'] as num?)?.toDouble(),
      );
}

class RouteInfo {
  final String model;
  final String label;
  final double inputRatePerM;
  final double outputRatePerM;
  RouteInfo(this.model, this.label, this.inputRatePerM, this.outputRatePerM);
}

// ---------------- Chat screen ----------------

class ChatScreen extends StatefulWidget {
  final bool isDark;
  final Function(bool) onToggleTheme;
  const ChatScreen({super.key, required this.isDark, required this.onToggleTheme});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _storage = const FlutterSecureStorage();
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  String _apiKey = '';
  bool _isSending = false;
  bool _modelsFailed = false;
  http.Client? _client;
  bool _stopped = false;
  bool _showJumpDown = false;
  String? _hoveredChat;
  String _selectedOverride = 'Free (Auto)';
  String _chatQuery = '';
  bool _freeOnly = false;
  List<Map<String, dynamic>> _allModels = [];
  final Map<String, DateTime> _busyUntil = {};

  List<Map<String, dynamic>> _chats = [];
  String _currentChatId = '';
  StreamSubscription<Uri>? _linkSub;
  static const String _callback = 'https://reynold-arch.github.io/ais-auth/';
  int _historyLimit = 12;

  final Map<String, RouteInfo> _manualModels = {
    'Free (Auto)': RouteInfo('openrouter/free', 'Free (Auto)', 0.0, 0.0),
  };

  // ---------- helpers ----------

  bool _isBusy(String modelId) {
    final t = _busyUntil[modelId];
    return t != null && DateTime.now().isBefore(t);
  }

  void _markBusy(String modelId) {
    _busyUntil[modelId] = DateTime.now().add(const Duration(minutes: 10));
  }

  Color _providerColor(String id) {
    const palette = [
      Color(0xFF7FA69C), Color(0xFFC97D5D), Color(0xFFD4A344),
      Color(0xFF8FA876), Color(0xFF6B9BD1), Color(0xFFB08968),
      Color(0xFFA68BB5), Color(0xFFC9A0A0),
    ];
    var h = 0;
    for (final c in id.split('/').first.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }

  String _shortLabel(String raw) => raw.split('/').last.replaceAll(':free', '');

  String _chipLabel() {
    if (_selectedOverride == 'Auto' || _manualModels.containsKey(_selectedOverride)) {
      return _selectedOverride;
    }
    return _shortLabel(_selectedOverride);
  }

  String _stripTag(String s) {
    final t = s.trimLeft();
    if (!t.startsWith('[')) return s;
    final end = t.indexOf(']');
    if (end == -1) return '';
    if (end > 80) return s;
    return t.substring(end + 1).replaceFirst(RegExp(r'^:?\s*'), '');
  }

  String _friendlyModelName(String raw) {
    final r = raw.toLowerCase();
    if (r.startsWith('deepseek/')) return 'DeepSeek';
    if (r.startsWith('anthropic/')) return 'Claude';
    if (r.startsWith('openai/gpt-4o')) return 'GPT-4o';
    if (r.startsWith('google/gemini')) return 'Gemini';
    return _shortLabel(raw);
  }

  String _priceText(Map<String, dynamic> m) => m['free'] == true
      ? 'FREE'
      : '\$${(m['inPrice'] as double).toStringAsFixed(2)} / \$${(m['outPrice'] as double).toStringAsFixed(2)} per 1M';

  List<ChatMessage> get _recentMessages {
    final all = _messages.where((m) => m.role != 'system' && !m.isStreaming).toList();
    return all.length > _historyLimit ? all.sublist(all.length - _historyLimit) : all;
  }

  // ---------- lifecycle ----------

  @override
  void initState() {
    super.initState();
    _loadApiKey();
    final links = AppLinks();
    links.getInitialLink().then((u) {
      if (u != null) _handleAuthLink(u);
    });
    _linkSub = links.uriLinkStream.listen(_handleAuthLink);
    _loadHistory();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final away =
          _scrollController.position.maxScrollExtent - _scrollController.offset > 200;
      if (away != _showJumpDown) setState(() => _showJumpDown = away);
    });
    _fetchModels();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------- chat storage ----------

  String _newId() => DateTime.now().millisecondsSinceEpoch.toString();

  Future<void> _saveChatsIndex() async {
    await _storage.write(key: 'chats_index', value: jsonEncode(_chats));
  }

  Future<void> _saveHistory() async {
    final all = _messages.where((m) => m.role != 'system' && !m.isStreaming).toList();
    if (all.isEmpty) return;
    if (_currentChatId.isEmpty) _currentChatId = _newId();
    await _storage.write(
      key: 'chat_$_currentChatId',
      value: jsonEncode(all.map((m) => m.toJson()).toList()),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final i = _chats.indexWhere((c) => c['id'] == _currentChatId);
    if (i == -1) {
      final first = all.firstWhere((m) => m.role == 'user', orElse: () => all.first);
      var title = first.content.replaceAll('\n', ' ').trim();
      if (title.length > 40) title = '${title.substring(0, 40)}...';
      _chats.insert(0, {'id': _currentChatId, 'title': title, 'updated': now});
    } else {
      _chats[i]['updated'] = now;
      final c = _chats.removeAt(i);
      _chats.insert(0, c);
    }
    await _saveChatsIndex();
    if (mounted) setState(() {});
  }

  Future<void> _openChat(String id) async {
    final raw = await _storage.read(key: 'chat_$id');
    final list = raw == null
        ? <ChatMessage>[]
        : (jsonDecode(raw) as List)
            .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
            .toList();
    if (!mounted) return;
    setState(() {
      _currentChatId = id;
      _messages
        ..clear()
        ..addAll(list);
    });
    _jumpToBottom();
  }

  Future<void> _renameChat(String id) async {
    final start = _chats.indexWhere((c) => c['id'] == id);
    if (start == -1) return;
    final controller = TextEditingController(text: _chats[start]['title'] as String);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(controller: controller, autofocus: true, maxLength: 60),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final i = _chats.indexWhere((c) => c['id'] == id);
    if (i == -1) return;
    setState(() => _chats[i]['title'] = name);
    await _saveChatsIndex();
  }

  Future<void> _removeChat(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove chat?'),
        content: const Text('This chat will be deleted from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await _storage.delete(key: 'chat_$id');
    setState(() => _chats.removeWhere((c) => c['id'] == id));
    await _saveChatsIndex();
    if (id == _currentChatId) _newChat();
  }

  Future<void> _togglePin(String id) async {
    final i = _chats.indexWhere((c) => c['id'] == id);
    if (i == -1) return;
    setState(() => _chats[i]['pinned'] = !(_chats[i]['pinned'] == true));
    await _saveChatsIndex();
  }

  void _newChat() {
    setState(() {
      _currentChatId = '';
      _messages.clear();
    });
  }

  Future<void> _loadHistory() async {
    try {
      final rawIdx = await _storage.read(key: 'chats_index');
      if (rawIdx != null) {
        _chats = (jsonDecode(rawIdx) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
        final old = await _storage.read(key: 'chat_history');
        if (old != null) {
          final id = _newId();
          await _storage.write(key: 'chat_$id', value: old);
          _chats = [
            {
              'id': id,
              'title': 'Previous chat',
              'updated': DateTime.now().millisecondsSinceEpoch
            }
          ];
          await _saveChatsIndex();
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  // ---------- models ----------

  Future<void> _fetchModels([VoidCallback? onDone]) async {
    try {
      final res = await http
          .get(Uri.parse('https://openrouter.ai/api/v1/models'))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        if (mounted) setState(() => _modelsFailed = true);
        onDone?.call();
        return;
      }
      final data = (jsonDecode(res.body)['data'] as List);
      final list = data.where((m) {
        final id = '${m['id']}'.toLowerCase();
        final name = '${m['name']}'.toLowerCase();
        final arch = (m['architecture'] ?? {}) as Map;
        final inn = (arch['input_modalities'] as List?) ?? ['text'];
        final out = (arch['output_modalities'] as List?) ?? ['text'];
        if (!inn.contains('text') || !out.contains('text')) return false;
        if (id.endsWith(':batch')) return false;
        const skip = [
          'safety', 'guard', 'rerank', 'embed', 'moderat',
          'asr', 'tts', 'whisper', 'classif'
        ];
        return !skip.any((w) => id.contains(w) || name.contains(w));
      }).map<Map<String, dynamic>>((m) {
                final p = (m['pricing'] ?? {}) as Map;
        final inP = (double.tryParse('${p['prompt']}') ?? 0) * 1000000;
        final outP = (double.tryParse('${p['completion']}') ?? 0) * 1000000;
        final arch = (m['architecture'] ?? {}) as Map;
        final top = (m['top_provider'] ?? {}) as Map;
        final params = (m['supported_parameters'] as List?) ?? [];
        return {
          'id': m['id'] as String,
          'name': (m['name'] ?? m['id']) as String,
          'free': inP == 0 && outP == 0,
          'inPrice': inP,
          'outPrice': outP,
          'context': m['context_length'],
          'maxOut': top['max_completion_tokens'],
          'inputs': ((arch['input_modalities'] as List?) ?? ['text']).join(', '),
          'tools': params.contains('tools'),
          'reasoning': params.contains('reasoning'),
          'structured': params.contains('structured_outputs'),
          'created': m['created'],
          'desc': (m['description'] ?? '') as String,
        };
      }).toList();
      if (!mounted) return;
      String? droppedName;
      final sel = _selectedOverride;
      final selId = _manualModels[sel]?.model ?? sel;
      final alwaysOk = sel == 'Auto' || selId.startsWith('openrouter/');
      if (!alwaysOk && !list.any((x) => x['id'] == selId)) droppedName = sel;
      setState(() {
        _allModels = list;
        _modelsFailed = false;
        if (droppedName != null) _selectedOverride = 'Free (Auto)';
      });
      if (droppedName != null) {
        _addSystemMessage('$droppedName is no longer available on OpenRouter. Switched to Free (Auto).');
      }
      onDone?.call();
    } catch (_) {
      if (mounted) setState(() => _modelsFailed = true);
      onDone?.call();
    }
  }

  RouteInfo _classifyIntent(String prompt) {
    if (_selectedOverride != 'Auto') {
      if (_selectedOverride == 'Free (Auto)') return _pickFreeModel(prompt);
      final fixed = _manualModels[_selectedOverride];
      if (fixed != null) return fixed;
      final m = _allModels.firstWhere(
        (x) => x['id'] == _selectedOverride,
        orElse: () => <String, dynamic>{},
      );
      return RouteInfo(
        _selectedOverride,
        m['name'] ?? _selectedOverride,
        (m['inPrice'] ?? 0.0) as double,
        (m['outPrice'] ?? 0.0) as double,
      );
    }
    return RouteInfo('openrouter/auto', 'Auto', 1.0, 3.0);
  }

  RouteInfo _pickFreeModel(String prompt) {
    final lower = prompt.toLowerCase();
    final isCode = RegExp(
            r'\b(code|coding|function|python|dart|flutter|javascript|java|bug|error|debug|script|html|css|sql|api|compile)\b')
        .hasMatch(lower);
    final free = _allModels
        .where((m) => m['free'] == true && !_isBusy(m['id'] as String))
        .toList();
    if (free.isEmpty) return _manualModels['Free (Auto)']!;
    double score(Map<String, dynamic> m) {
      final id = (m['id'] as String).toLowerCase();
      double s = 0;
      final size = RegExp(r'(\d+)b(?![a-z])').firstMatch(id);
      if (size != null) {
        final b = double.parse(size.group(1)!);
        s += (b >= 20 && b <= 120) ? 200 - (b - 70).abs() : (b > 120 ? 50 : b);
      }
      if (isCode && id.contains('code')) s += 1000;
      return s;
    }

    free.sort((a, b) => score(b).compareTo(score(a)));
    final best = free.first;
    return RouteInfo(best['id'] as String, best['name'] as String, 0.0, 0.0);
  }

  double _estimateCost(RouteInfo route, String prompt, String response) {
    final inputTokens = (prompt.length / 4).ceil();
    final outputTokens = (response.length / 4).ceil();
    return (inputTokens / 1000000 * route.inputRatePerM) +
        (outputTokens / 1000000 * route.outputRatePerM);
  }

  // ---------- login ----------

  String _randomVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List.generate(64, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _startLogin() async {
    final verifier = _randomVerifier();
    await _storage.write(key: 'pkce_verifier', value: verifier);
    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    final url = Uri.https('openrouter.ai', '/auth', {
      'callback_url': _callback,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) _addSystemMessage('Could not open the browser.');
  }

  Future<void> _handleAuthLink(Uri uri) async {
    if (uri.scheme != 'ais' || uri.host != 'auth') return;
    final code = uri.queryParameters['code'];
    final verifier = await _storage.read(key: 'pkce_verifier');
    if (code == null || verifier == null) return;
    try {
      final res = await http
          .post(
            Uri.parse('https://openrouter.ai/api/v1/auth/keys'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'code_verifier': verifier,
              'code_challenge_method': 'S256',
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final key = jsonDecode(res.body)['key'] as String;
        await _storage.write(key: 'openrouter_api_key', value: key);
        await _storage.delete(key: 'pkce_verifier');
        if (!mounted) return;
        setState(() => _apiKey = key);
        Navigator.of(context).popUntil((r) => r.isFirst);
        _addSystemMessage('Connected to OpenRouter. You can start chatting.');
      } else {
        _addSystemMessage(
            'Login failed (code ${res.statusCode}). Try again or paste a key in Settings.');
      }
    } catch (_) {
      if (mounted) _addSystemMessage('Login failed. Check your connection and try again.');
    }
  }

  Future<void> _loadApiKey() async {
    final saved = await _storage.read(key: 'openrouter_api_key');
    final lim = int.tryParse(await _storage.read(key: 'history_limit') ?? '');
    if (!mounted) return;
    setState(() {
      if (saved != null) _apiKey = saved;
      if (lim != null) _historyLimit = lim.clamp(2, 50);
    });
  }

  Future<void> _removeKey() async {
    await _storage.delete(key: 'openrouter_api_key');
    if (mounted) setState(() => _apiKey = '');
  }

  Future<void> _deleteAllData() async {
    await _storage.deleteAll();
    if (!mounted) return;
    setState(() {
      _apiKey = '';
      _chats = [];
      _currentChatId = '';
      _messages.clear();
      _selectedOverride = 'Free (Auto)';
    });
  }

  // ---------- scrolling ----------

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _goBottom({bool animate = true}) async {
    for (var i = 0; i < 4; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (animate && i == 0) {
        await _scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(max);
      }
    }
  }

  void _jumpToBottom() => _goBottom(animate: false);

  void _followStream() {
    if (!_scrollController.hasClients) return;
    final p = _scrollController.position;
    if (p.maxScrollExtent - p.pixels > 150) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _addSystemMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(role: 'system', content: text));
    });
    _scrollToBottom();
  }

  // ---------- message actions ----------

  Future<void> _editMessage(int index) async {
    if (_isSending || index < 0 || index >= _messages.length) return;
    final controller = TextEditingController(text: _messages[index].content);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 8,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Send')),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _messages.removeRange(index, _messages.length);
      _promptController.text = text;
    });
    _sendMessage();
  }

  void _regenerate() {
    if (_isSending || _messages.isEmpty) return;
    if (_messages.last.role != 'assistant') return;
    final ui = _messages.lastIndexWhere((m) => m.role == 'user');
    if (ui == -1) return;
    final prompt = _messages[ui].content;
    setState(() {
      _messages.removeRange(ui, _messages.length);
      _promptController.text = prompt;
    });
    _sendMessage();
  }

  void _stopReply() {
    _stopped = true;
    _client?.close();
  }
    String _errorDetail(String body) {
    try {
      final e = jsonDecode(body)['error'];
      var msg = '${e['message'] ?? ''}'.trim();
      final meta = e['metadata'];
      if (meta is Map) {
        final reasons = meta['reasons'];
        if (reasons is List && reasons.isNotEmpty) {
          msg += ' (${reasons.join(', ')})';
        }
        final raw = meta['raw'];
        if (raw != null && '$raw'.trim().isNotEmpty) {
          final r = '$raw'.trim();
          msg += ' ${r.length > 200 ? r.substring(0, 200) : r}';
        }
      }
        var out = msg
        .replaceAll(RegExp(r'sk-[A-Za-z0-9_\-\.\*…]+'), '[hidden]')
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
      if (out.length > 120) out = '${out.substring(0, 120)}...';
      return out;
    } catch (_) {
      return '';
    }
  }
  String _friendlyError(int code, String body, String label) {
    final b = body.toLowerCase();
    if (b.contains('key limit exceeded')) {
      return "This key's spending limit is reached. Raise it at openrouter.ai/settings/keys.";
    }
    if (code == 401) {
      return "Your OpenRouter key isn't working. Open Settings and tap Connect with OpenRouter again.";
    }
    if (code == 402) {
      return "You're out of credits. Top up on the OpenRouter website (openrouter.ai/settings/credits), or pick a free model.";
    }
    if (code == 429) {
      return '$label is busy right now (free models have daily limits). Try another model.';
    }
    if (code == 404) {
      if (b.contains('data policy') || b.contains('privacy')) {
        return 'Free models need a privacy setting. On openrouter.ai open Settings, then Privacy, and allow free endpoints. Or pick a paid model.';
      }
      return '$label is not available right now. It may have been removed. Pick another model.';
    }
    if (code == 400) {
      return "The model couldn't take this message (it may be too long or unsupported). Try a shorter message or another model.";
    }
    if (code == 403) {
      return 'This model blocked the request. Try rephrasing, or pick another model.';
    }
    if (code >= 500) {
      return 'OpenRouter or the model had a server problem (code $code). Try again or pick another model.';
    }
    return 'Something went wrong (code $code). Try again or pick another model.';
  }

  Future<void> _sendMessage() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    if (_apiKey.trim().isEmpty) {
      _addSystemMessage("Your OpenRouter key isn't set. Open Settings to add one.");
      return;
    }

    var route = _classifyIntent(prompt);

    setState(() {
      _messages.add(ChatMessage(role: 'user', content: prompt));
      _promptController.clear();
      _isSending = true;
      _messages.add(ChatMessage(
        role: 'assistant',
        content: '',
        modelLabel: route.label,
        isStreaming: true,
      ));
    });
    _scrollToBottom();

    try {
          var client = http.Client();
      _client = client;
      _stopped = false;
      final canRetry =
          _selectedOverride == 'Auto' || _selectedOverride == 'Free (Auto)';
      final maxTries = canRetry ? 3 : 1;
      http.StreamedResponse? streamedResponse;
      var code = 0;
      var errBody = '';
      int? tokenCap;
      for (var attempt = 1; attempt <= maxTries; attempt++) {
        if (_stopped) throw Exception('stopped');
        final request = http.Request(
          'POST',
          Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        );
        request.headers.addAll({
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        });
        request.body = jsonEncode({
          'model': route.model,
          'messages': [
            {
              'role': 'system',
              'content':
                  'This is a group chat between one user and several different AI models. Earlier AI replies start with a tag like [DeepSeek]: so you can tell who said what. You are one of those models and did not write the replies from other models. You may agree, disagree, correct or build on them. IMPORTANT: the tag is only for reading. Never start your reply with a tag, a name in brackets, or your own model name.',
            },
            ..._recentMessages.map((m) => {
                  'role': m.role,
                  'content': (m.role == 'assistant' && m.modelLabel != null)
                      ? '[${_shortLabel(m.modelLabel!)}]: ${_stripTag(m.content)}'
                      : m.content,
                }),
          ],
          'stream': true,
          if (tokenCap != null) 'max_tokens': tokenCap,
          'usage': {'include': true},
          if (route.model == 'openrouter/auto')
            'plugins': [
              {'id': 'auto-router', 'cost_tier': 'medium'}
            ],
        });
        try {
          final r = await client
              .send(request)
              .timeout(Duration(seconds: canRetry ? 30 : 60));
          if (r.statusCode == 200) {
            streamedResponse = r;
            break;
          }
          code = r.statusCode;
          errBody = await r.stream.bytesToString();
          if (code == 402 && tokenCap == null) {
            final m = RegExp(r'can only afford ([\d,]+)').firstMatch(errBody);
            final n = int.tryParse((m?.group(1) ?? '').replaceAll(',', ''));
            if (n != null && n >= 200) {
              tokenCap = (n * 0.9).floor();
              attempt--;
              continue;
            }
          }
        } on TimeoutException {
          code = 408;
          errBody = '';
        }
        final retryable = code != 401 && code != 402;
        if (!canRetry || !retryable || attempt == maxTries) break;
        if (_selectedOverride == 'Free (Auto)') {
          _markBusy(route.model);
          route = _pickFreeModel(prompt);
          setState(() => _messages.last.modelLabel = route.label);
        }
        client.close();
        client = http.Client();
        _client = client;
      }
      if (streamedResponse == null) {
        client.close();
        if (code == 404 || code == 429) _markBusy(route.model);
        setState(() {
          _messages.removeLast();
          if (_messages.isNotEmpty && _messages.last.role == 'user') {
            _messages.removeLast();
          }
          _promptController.text = prompt;
          _isSending = false;
        });
        final detail = (code == 401 ||
                code == 402 ||
                errBody.toLowerCase().contains('key limit'))
            ? ''
            : _errorDetail(errBody);
        _addSystemMessage(
      '${_friendlyError(code, errBody, route.label)}${detail.isEmpty ? '' : '\n\nDetails: $detail'}');
        if (code == 404) _fetchModels();
        return;
      }
      final buffer = StringBuffer();
      double? realCost;
      String pending = '';
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        pending += chunk;
        final parts = pending.split('\n');
        pending = parts.removeLast();
        for (final line in parts) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          if (data == '[DONE]') continue;
          if (data.isEmpty) continue;
          try {
            final json = jsonDecode(data);
            final usage = json['usage'];
            if (usage != null && usage['cost'] != null) {
              realCost = (usage['cost'] as num).toDouble();
            }
            final delta = json['choices']?[0]?['delta']?['content'];
            final actualModel = json['model'];
            if (actualModel != null) {
              _messages.last.modelLabel = _friendlyModelName(actualModel);
              _messages.last.modelId = actualModel as String;
            }
            if (delta != null) {
              buffer.write(delta);
              setState(() {
                _messages.last.content = buffer.toString();
              });
              _followStream();
            }
          } catch (_) {}
        }
      }
      client.close();

      final cost = realCost ?? _estimateCost(route, prompt, buffer.toString());
      setState(() {
        _messages.last.isStreaming = false;
        _messages.last.costEstimate = cost;
        _isSending = false;
      });
      _saveHistory();
    } catch (e) {
      setState(() {
        if (_messages.isNotEmpty && _messages.last.isStreaming) {
          if (_messages.last.content.isEmpty) {
            _messages.removeLast();
          } else {
            _messages.last.isStreaming = false;
          }
        }
        _isSending = false;
      });
      if (_stopped) {
        setState(() {
          final hasPartial = _messages.isNotEmpty &&
              _messages.last.role == 'assistant' &&
              _messages.last.content.isNotEmpty;
          if (!hasPartial) {
            if (_messages.isNotEmpty && _messages.last.role == 'user') {
              _messages.removeLast();
            }
            _promptController.text = prompt;
          }
        });
        _saveHistory();
        return;
      }
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        setState(() {
          if (_messages.isNotEmpty && _messages.last.role == 'user') {
            _messages.removeLast();
          }
          _promptController.text = prompt;
        });
        _addSystemMessage(
            "No connection. Your message is back in the box. Send it again when you're online.");
      } else if (e.toString().contains('Connection closed') ||
          e.toString().contains('ClientException')) {
        _saveHistory();
        _addSystemMessage(
            'Connection dropped while the reply was coming in. Send again to retry.');
      } else if (e.toString().contains('TimeoutException')) {
        _addSystemMessage('Request timed out. Try again.');
      } else {
        _addSystemMessage(
            'Something unexpected went wrong. Your message is back in the box. Try again, or pick another model.');
        setState(() {
          if (_messages.isNotEmpty && _messages.last.role == 'user') {
            _messages.removeLast();
          }
          _promptController.text = prompt;
        });
      }
    }
  }

  void _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          currentKey: _apiKey,
          historyLimit: _historyLimit,
          onHistoryLimit: (n) async {
            setState(() => _historyLimit = n);
            await _storage.write(key: 'history_limit', value: '$n');
          },
          isDark: widget.isDark,
          onToggleTheme: widget.onToggleTheme,
          onConnect: _startLogin,
          onDeleteAll: _deleteAllData,
          onRemoveKey: _removeKey,
          onKeySaved: (key) async {
            await _storage.write(key: 'openrouter_api_key', value: key);
            setState(() => _apiKey = key);
          },
        ),
      ),
    );
  }

  // ---------- model picker ----------

  Future<void> _openPicker() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod('TextInput.hide');
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    _showModelPicker(context);
  }

  String _pinnedSubtitle(String key) {
    if (key == 'Free (Auto)') return 'Picks the best available free model';
    return 'Lets OpenRouter pick the best model';
  }

  void _showModelPicker(BuildContext context) {
    String query = '';
    bool freeOnly = _freeOnly;
    bool refreshed = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final cs = Theme.of(ctx).colorScheme;
            final subStyle = TextStyle(color: cs.onSurfaceVariant, fontSize: 12);
            final q = query.toLowerCase();
            if (!refreshed) {
              refreshed = true;
              _fetchModels(() {
                if (ctx.mounted) setSheet(() {});
              });
            }
            final pinned = ['Auto', ..._manualModels.keys].where((m) {
              if (!m.toLowerCase().contains(q)) return false;
              if (!freeOnly) return true;
              return m == 'Free (Auto)';
            }).toList();
            if (pinned.remove(_selectedOverride)) pinned.insert(0, _selectedOverride);
            final pinnedIds = _manualModels.values.map((r) => r.model).toSet();
            final others = _allModels.where((m) {
              if (pinnedIds.contains(m['id'])) return false;
              if (freeOnly && m['free'] != true) return false;
              return (m['name'] as String).toLowerCase().contains(q) ||
                  (m['id'] as String).toLowerCase().contains(q);
            }).take(100).toList();
            others.sort((a, b) =>
                (_isBusy(a['id'] as String) ? 1 : 0) -
                (_isBusy(b['id'] as String) ? 1 : 0));
            final selectedOther =
                _allModels.where((m) => m['id'] == _selectedOverride).toList();

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search models...',
                          prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                        ),
                        onChanged: (v) => setSheet(() => query = v),
                      ),
                    ),
                    if (_modelsFailed && _allModels.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                "Couldn't load the full model list. Check your connection.",
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _fetchModels(() {
                                if (ctx.mounted) setSheet(() {});
                              }),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    SwitchListTile(
                      title: const Text('Free only'),
                      value: freeOnly,
                      onChanged: (v) {
                        _freeOnly = v;
                        setSheet(() => freeOnly = v);
                      },
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          ...selectedOther.map((m) => ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _providerColor(m['id'] as String),
                                  radius: 8,
                                ),
                                title: Text(m['name'] as String),
                                subtitle: Text('${m['id']} · ${_priceText(m)}', style: subStyle),
                                trailing: Icon(Icons.check_circle, color: cs.primary),
                                onTap: () => Navigator.pop(ctx),
                              )),
                          ...pinned.map((m) => ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: cs.tertiary,
                                  radius: 8,
                                ),
                                title: Text(m),
                                subtitle: Text(_pinnedSubtitle(m), style: subStyle),
                                trailing: m == _selectedOverride
                                    ? Icon(Icons.check_circle, color: cs.primary)
                                    : null,
                                onTap: () {
                                  setState(() => _selectedOverride = m);
                                  Navigator.pop(ctx);
                                },
                              )),
                          ...others
                              .where((m) => m['id'] != _selectedOverride)
                              .map((m) {
                            final id = m['id'] as String;
                            final busy = _isBusy(id);
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    busy ? cs.outline : _providerColor(id),
                                radius: 8,
                              ),
                              title: Text(
                                m['name'] as String,
                                style: busy ? TextStyle(color: cs.onSurfaceVariant) : null,
                              ),
                              subtitle: Text(
                                '${busy ? 'BUSY · ' : ''}$id · ${_priceText(m)}',
                                style: subStyle,
                              ),
                              onTap: () {
                                setState(() => _selectedOverride = id);
                                Navigator.pop(ctx);
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

      void _showModelDetails(String modelId) {
            FocusManager.instance.primaryFocus?.unfocus();
            final m = _allModels.firstWhere(
      (x) => x['id'] == modelId,
      orElse: () => <String, dynamic>{},
    );
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final muted = TextStyle(color: cs.onSurfaceVariant, fontSize: 12);
        final pc = _providerColor(modelId);
        String tok(dynamic v) {
          final n = (v as num?)?.toInt();
          if (n == null) return '-';
          return n >= 1000 ? '${(n / 1000).round()}K' : '$n';
        }

        Widget row(IconData icon, String k, String v) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  SizedBox(width: 82, child: Text(k, style: muted)),
                  Expanded(
                    child: Text(v,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface)),
                  ),
                ],
              ),
            );

        final isFree = m['free'] == true;
        final sup = [
          if (m['tools'] == true) 'tools',
          if (m['reasoning'] == true) 'reasoning',
          if (m['structured'] == true) 'structured output',
        ];
        final created = m['created'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (m['created'] as num).toInt() * 1000)
            : null;
        final desc = ((m['desc'] ?? '') as String).trim();

        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Center(
            child: Dialog(
              backgroundColor: cs.surface,
              surfaceTintColor: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: cs.outline),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: WavePainter(pc)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: pc.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: pc),
                              ),
                              child: Text(
                                modelId.split('/').first[0].toUpperCase(),
                                style: GoogleFonts.fraunces(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    color: pc),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.isEmpty ? 'Model details' : '${m['name']}',
                                    style: GoogleFonts.fraunces(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(modelId, style: muted),
                                ],
                              ),
                            ),
                            if (m.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: pc.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: pc),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                          color: pc,
                                          shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(isFree ? 'Free' : 'Paid',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: pc,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                                               const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 6),
                        if (m.isEmpty)
                          Text('No live details found for this model.',
                              style: muted)
                        else ...[
                          row(Icons.sell_outlined, 'Price', _priceText(m)),
                          row(Icons.layers_outlined, 'Context',
                              '${tok(m['context'])} tokens'),
                          row(Icons.play_arrow_outlined, 'Max output',
                              '${tok(m['maxOut'])} tokens'),
                          row(Icons.description_outlined, 'Inputs',
                              '${m['inputs']}'),
                          row(Icons.settings_outlined, 'Supports',
                              sup.isEmpty ? 'basic chat' : sup.join(', ')),
                          if (created != null)
                            row(Icons.calendar_today_outlined, 'Released',
                                '${created.year}-${created.month.toString().padLeft(2, '0')}'),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            const Divider(),
                            const SizedBox(height: 8),
                            Text(desc,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: muted),
                          ],
                        ],
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: pc,
                            iconColor: pc,
                            side: BorderSide(color: pc),
                          ),
                          onPressed: () => launchUrl(
                            Uri.parse('https://openrouter.ai/$modelId'),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Learn more'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  // ---------- drawer ----------

  Widget _buildChatRow(BuildContext context, Map<String, dynamic> c, bool touch) {
    final cs = Theme.of(context).colorScheme;
    final id = c['id'] as String;
    final selected = id == _currentChatId;
    final pinned = c['pinned'] == true;
    final showDots = touch || _hoveredChat == id;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredChat = id),
      onExit: (_) => setState(() {
        if (_hoveredChat == id) _hoveredChat = null;
      }),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? cs.secondary : null,
          border: selected ? Border(left: BorderSide(color: cs.primary, width: 3)) : null,
        ),
        child: InkWell(
          onTap: _isSending
              ? null
              : () {
                  Navigator.pop(context);
                  _openChat(id);
                },
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Row(
                children: [
                  if (pinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.push_pin, size: 14, color: cs.onSurfaceVariant),
                    ),
                  Expanded(
                    child: Text(
                      c['title'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurface),
                    ),
                  ),
                  IgnorePointer(
                    ignoring: !showDots,
                    child: Opacity(
                      opacity: showDots ? 1 : 0,
                      child: PopupMenuButton<String>(
                        enabled: !_isSending,
                        tooltip: 'Chat options',
                        icon: Icon(Icons.more_horiz, size: 20, color: cs.onSurfaceVariant),
                        onSelected: (v) {
                          if (v == 'pin') _togglePin(id);
                          if (v == 'rename') _renameChat(id);
                          if (v == 'remove') _removeChat(id);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'pin', child: Text(pinned ? 'Unpin' : 'Pin')),
                          const PopupMenuItem(value: 'rename', child: Text('Rename chat')),
                          const PopupMenuItem(value: 'remove', child: Text('Remove chat')),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

    Widget _drawerHeading(String t, ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(
          t,
          style: TextStyle(
              fontSize: 12, color: cs.onSurfaceVariant, letterSpacing: 0.6),
        ),
      );

  Widget _buildDrawer(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final touch = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final q = _chatQuery.trim().toLowerCase();
    final matches = _chats
        .where((c) => q.isEmpty || (c['title'] as String).toLowerCase().contains(q))
        .toList();
        final groups = <String, List<Map<String, dynamic>>>{
      'Pinned': [],
      'Recent': [],
    };
    for (final c in matches) {
      if (c['pinned'] == true) {
        groups['Pinned']!.add(c);
      } else {
        groups['Recent']!.add(c);
      }
    }
    final rows = <Widget>[];
    groups.forEach((title, list) {
      if (list.isEmpty) return;
      rows.add(_drawerHeading(title, cs));
      for (final c in list) {
        rows.add(_buildChatRow(context, c, touch));
      }
    });

    return Drawer(
      backgroundColor: cs.surface,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: WavePainter(cs.primary)),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CustomPaint(
                            painter: AisLogoPainter(cs.primary, cs.tertiary)),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'AIS',
                        style: GoogleFonts.fraunces(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                            color: cs.onSurface),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSending
                          ? null
                          : () {
                              Navigator.pop(context);
                              _newChat();
                            },
                      icon: const Icon(Icons.add),
                      label: const Text('New chat'),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: TextField(
                    onChanged: (v) => setState(() => _chatQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search chats',
                      isDense: true,
                      prefixIcon: Icon(Icons.search,
                          size: 20, color: cs.onSurfaceVariant),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text(
                            q.isEmpty ? 'No chats yet' : 'No matches',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      : ListView(children: rows),
                ),
                const Divider(),
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _openSettings();
                  },
                  child: SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(Icons.settings_outlined,
                              size: 20, color: cs.onSurfaceVariant),
                          const SizedBox(width: 14),
                          Text('Settings', style: TextStyle(color: cs.onSurface)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- messages ----------

  Widget _buildMessage(BuildContext context, int index) {
    final cs = Theme.of(context).colorScheme;
    final msg = _messages[index];

    if (msg.role == 'system') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.tertiary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.tertiary.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg.content, style: TextStyle(color: cs.onSurface, fontSize: 13)),
            if (msg.content.contains("key isn't"))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ElevatedButton(
                  onPressed: _startLogin,
                  child: const Text('Connect with OpenRouter'),
                ),
              ),
          ],
        ),
      );
    }

    final isUser = msg.role == 'user';
    final iconColor = cs.onSurfaceVariant;
    final showCost = (msg.costEstimate ?? 0) > 0.00005;
    final showActions = !msg.isStreaming && msg.content.isNotEmpty;
    final isLastReply =
        !isUser && !_isSending && index == _messages.length - 1;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            width: isUser ? null : double.infinity,
            margin: const EdgeInsets.only(top: 4),
            padding: isUser
                ? const EdgeInsets.all(12)
                : const EdgeInsets.symmetric(vertical: 8),
            constraints: BoxConstraints(
              maxWidth: isUser
                  ? MediaQuery.of(context).size.width * 0.90
                  : double.infinity,
            ),
            decoration: isUser
                ? BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(16),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (msg.isStreaming && msg.content.isEmpty)
                  TypingDots(color: cs.onSurfaceVariant)
                else
                  isUser
                      ? SelectableText(msg.content,
                          style: TextStyle(color: cs.onPrimary))
                      : MarkdownBody(
                          data: _stripTag(msg.content),
                          selectable: true,
                          builders: {'pre': CodeBlockBuilder(context)},
                          styleSheet:
                              MarkdownStyleSheet.fromTheme(Theme.of(context))
                                  .copyWith(
                            p: Theme.of(context).textTheme.bodyMedium,
                            code: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              backgroundColor: cs.onSurface.withOpacity(0.08),
                            ),
                            codeblockDecoration: const BoxDecoration(),
                            codeblockPadding: EdgeInsets.zero,
                          ),
                        ),
                if (!isUser && msg.modelLabel != null && !msg.isStreaming)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: msg.modelId != null
                                ? _providerColor(msg.modelId!)
                                : cs.tertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: GestureDetector(
                            onLongPress: msg.modelId == null
                                ? null
                                : () => _showModelDetails(msg.modelId!),
                            child: Text(
                              '${msg.modelLabel}${showCost ? ' · \$${msg.costEstimate!.toStringAsFixed(4)}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (showActions)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isUser && !_isSending)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _editMessage(index),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.edit, size: 16, color: iconColor),
                    ),
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Clipboard.setData(ClipboardData(
                        text: isUser ? msg.content : _stripTag(msg.content)));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Copied'),
                          duration: Duration(seconds: 1)),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.copy, size: 16, color: iconColor),
                  ),
                ),
                if (isLastReply)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _regenerate,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.refresh, size: 16, color: iconColor),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }


  // ---------- input bar ----------

    Widget _buildInputBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 6, 6),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _promptController,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _promptController,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  final active = _isSending || hasText;
                  return Semantics(
                    button: true,
                    label: _isSending ? 'Stop reply' : 'Send message',
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Material(
                        color: active
                            ? cs.primary
                            : cs.onSurfaceVariant.withOpacity(0.4),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _isSending
                              ? _stopReply
                              : (hasText ? _sendMessage : null),
                          child: Icon(
                            _isSending
                                ? Icons.stop_rounded
                                : Icons.send_rounded,
                            size: 20,
                            color: active ? cs.onPrimary : cs.surface,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  

  // ---------- screen ----------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      bottomNavigationBar: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _buildInputBar(context),
      ),
      onDrawerChanged: (isOpened) {
        FocusManager.instance.primaryFocus?.unfocus();
        if (!isOpened && _chatQuery.isNotEmpty) {
          setState(() => _chatQuery = '');
        }
      },
      drawer: _buildDrawer(context),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        leadingWidth: 44,
        titleSpacing: 0,
                actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.outline),
                ),
                child: Icon(Icons.person_outline,
                    size: 20, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ],
        title: SizedBox(
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: cs.secondary,
                  shape: StadiumBorder(side: BorderSide(color: cs.outline)),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: _openPicker,
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minHeight: 30, maxWidth: 90),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10, right: 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: (_selectedOverride == 'Auto' ||
                                        _manualModels
                                            .containsKey(_selectedOverride))
                                    ? cs.tertiary
                                    : _providerColor(_selectedOverride),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _chipLabel(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            Icon(Icons.arrow_drop_down,
                                size: 15, color: cs.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                'AIS',
                style: GoogleFonts.fraunces(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                    fontSize: 26,
                    color: cs.onSurface),
              ),
            ],
          ),
        ),
      ),
            body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: _messages.isEmpty ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: AnimatedWaves(
                  main: cs.primary,
                  accent: cs.tertiary,
                  animate: _messages.isEmpty,
                ),
              ),
            ),
            Positioned.fill(
              child: Builder(
                builder: (ctx) {
                  final topInset =
                      MediaQuery.of(context).padding.top + kToolbarHeight;
                  final bottomInset = MediaQuery.of(ctx).padding.bottom;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _messages.isEmpty
                              ? Padding(
                                  padding: EdgeInsets.only(
                                      top: topInset, bottom: bottomInset),
                                  child: StartView(onPick: (t) {
                                    _promptController.text = t;
                                    _sendMessage();
                                  }),
                                )
                            : LayoutBuilder(
                                  builder: (context, box) {
                                    final h = box.maxHeight;
                                    final s0 = ((topInset - 12) / h)
                                        .clamp(0.0, 0.45);
                                    final s1 = ((topInset + 28) / h)
                                        .clamp(s0 + 0.01, 0.55);
                                    final s3 = ((h - bottomInset + 4) / h)
                                        .clamp(s1 + 0.03, 1.0);
                                    final s2 = ((h - bottomInset - 20) / h)
                                        .clamp(s1 + 0.01, s3 - 0.01);
                                    return ShaderMask(
                                      blendMode: BlendMode.dstIn,
                                      shaderCallback: (rect) => LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: const [
                                          Colors.transparent,
                                          Colors.black,
                                          Colors.black,
                                          Colors.transparent,
                                        ],
                                        stops: [s0, s1, s2, s3],
                                      ).createShader(rect),
                                      child: ListView.builder(
                                        controller: _scrollController,
                                        padding: EdgeInsets.fromLTRB(12,
                                            topInset + 28, 12, bottomInset + 28),
                                        itemCount: _messages.length,
                                        itemBuilder: (context, index) =>
                                            _buildMessage(context, index),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      if (_showJumpDown && _messages.isNotEmpty)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: bottomInset + 8,
                          child: Center(
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Material(
                                color: cs.surface,
                                shape: CircleBorder(
                                    side: BorderSide(color: cs.outline)),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _goBottom,
                                  child: Icon(Icons.keyboard_arrow_down,
                                      color: cs.onSurface),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Code block with Copy button ----------------

class CodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext ctx;
  CodeBlockBuilder(this.ctx);

  static const _alias = {
    'js': 'javascript',
    'ts': 'typescript',
    'py': 'python',
    'sh': 'bash',
    'shell': 'bash',
    'html': 'xml',
    'yml': 'yaml',
    'c++': 'cpp',
    'kt': 'kotlin',
  };

  Map<String, TextStyle> _theme(bool dark, Color base) {
    final kw = dark ? const Color(0xFFE0765C) : const Color(0xFFC4553B);
    final str = dark ? const Color(0xFF6DB89F) : const Color(0xFF2F6B57);
    final nu = dark ? const Color(0xFFD4A344) : const Color(0xFF9A6B10);
    final fn = dark ? const Color(0xFF6B9BD1) : const Color(0xFF2F6BA8);
    final ty = dark ? const Color(0xFFA68BB5) : const Color(0xFF7A5A99);
    const cm = Color(0xFF8A8577);
    TextStyle s(Color c, {bool italic = false}) => TextStyle(
        color: c, fontStyle: italic ? FontStyle.italic : FontStyle.normal);
    return {
      'root': TextStyle(color: base, backgroundColor: Colors.transparent),
      'keyword': s(kw),
      'selector-tag': s(kw),
      'literal': s(kw),
      'doctag': s(kw),
      'deletion': s(kw),
      'built_in': s(fn),
      'title': s(fn),
      'section': s(fn),
      'name': s(fn),
      'string': s(str),
      'regexp': s(str),
      'addition': s(str),
      'number': s(nu),
      'attr': s(nu),
      'attribute': s(nu),
      'symbol': s(nu),
      'bullet': s(nu),
      'type': s(ty),
      'class': s(ty),
      'variable': s(base),
      'params': s(base),
      'comment': s(cm, italic: true),
      'quote': s(cm, italic: true),
      'meta': s(cm),
    };
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent.trimRight();
    var lang = '';
    final kids = element.children;
    if (kids != null && kids.isNotEmpty && kids.first is md.Element) {
      final cls = (kids.first as md.Element).attributes['class'];
      if (cls != null && cls.startsWith('language-')) lang = cls.substring(9);
    }
    final cs = Theme.of(ctx).colorScheme;
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    final key = _alias[lang.toLowerCase()] ?? lang.toLowerCase();
    final known = allLanguages.containsKey(key);
    const codeStyle =
        TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.5);
        return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: cs.onSurface.withOpacity(0.05),
            padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    lang.isEmpty ? 'code' : lang,
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
                CodeCopyButton(code: code),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outline),
          CodeScroller(
            child: known
                ? HighlightView(
                    code,
                    language: key,
                    theme: _theme(dark, cs.onSurface),
                    padding: EdgeInsets.zero,
                    textStyle: codeStyle,
                  )
                : SelectableText(code, style: codeStyle),
          ),
        ],
      ),
    );
  }
}

// ---------------- Settings screen ----------------

class SettingsScreen extends StatefulWidget {
  final String currentKey;
  final int historyLimit;
  final Function(int) onHistoryLimit;
  final bool isDark;
  final Function(bool) onToggleTheme;
  final Function(String) onKeySaved;
  final VoidCallback onConnect;
  final Future<void> Function() onDeleteAll;
  final Future<void> Function() onRemoveKey;

  const SettingsScreen({
    super.key,
    required this.currentKey,
    required this.historyLimit,
    required this.onHistoryLimit,
    required this.isDark,
    required this.onToggleTheme,
    required this.onKeySaved,
    required this.onConnect,
    required this.onDeleteAll,
    required this.onRemoveKey,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _keyController;
  late double _limit = widget.historyLimit.toDouble();
  String? _statusText;
  bool _statusOk = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.currentKey);
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _validateAndSave() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _statusOk = false;
        _statusText = 'Paste a key first';
      });
      return;
    }
    setState(() {
      _checking = true;
      _statusText = null;
    });
    try {
      final response = await http.get(
        Uri.parse('https://openrouter.ai/api/v1/auth/key'),
        headers: {'Authorization': 'Bearer $key'},
      ).timeout(const Duration(seconds: 15));
      final ok = response.statusCode == 200;
      if (!mounted) return;
      setState(() {
        _statusOk = ok;
        _statusText = ok ? 'Key valid' : 'Key not accepted by OpenRouter';
        _checking = false;
      });
      if (ok) widget.onKeySaved(key);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusOk = false;
        _statusText = "Couldn't check the key. Check your connection.";
        _checking = false;
      });
    }
  }

  Future<void> _removeKey() async {
    await widget.onRemoveKey();
    if (!mounted) return;
    setState(() {
      _keyController.clear();
      _statusOk = false;
      _statusText = 'Key removed from this phone';
    });
  }

  Widget _card(BuildContext context, String title, List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.fraunces(
                fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = TextStyle(color: cs.onSurfaceVariant, fontSize: 13);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.fraunces(fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(context, 'OpenRouter', [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onConnect,
                child: const Text('Connect with OpenRouter'),
              ),
            ),
            const SizedBox(height: 8),
            Text('Opens OpenRouter in your browser. Log in and tap Authorize.',
                style: muted),
            const SizedBox(height: 20),
            Text('OpenRouter API Key',
                style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 8),
            TextField(
              controller: _keyController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'sk-or-v1-...',
                filled: true,
                fillColor: cs.surface,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _checking ? null : _validateAndSave,
                  child: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Validate & Save'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _statusText == null
                        ? ''
                        : (_statusOk ? '$_statusText ✓' : _statusText!),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      color: _statusOk ? cs.primary : cs.tertiary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _removeKey,
                style: TextButton.styleFrom(foregroundColor: cs.tertiary),
                child: const Text('Remove key'),
              ),
            ),
          ]),
                    _card(context, 'Memory', [
            Text(
              'Messages the AI remembers: ${_limit.round()}',
              style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
            Slider(
              value: _limit,
              min: 2,
              max: 50,
              divisions: 48,
              label: '${_limit.round()}',
              onChanged: (v) => setState(() => _limit = v),
              onChangeEnd: (v) => widget.onHistoryLimit(v.round()),
            ),
            Text(
              'Each time you send a message, AIS sends this many of the latest messages (yours and the AI\'s) so the AI can follow the conversation. Older messages are forgotten by the AI, but stay saved on your phone. Higher means better memory, but costs more on paid models and can fail on models with a small context. Lower is cheaper and faster.',
              style: muted,
            ),
          ]),
          _card(context, 'Appearance', [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Dark theme',
                    style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
                Switch(
                  value: widget.isDark,
                  onChanged: widget.onToggleTheme,
                ),
              ],
            ),
          ]),
          _card(context, 'Privacy', [
            Text(
              'Your API key and chats are stored only on this phone. There is no app server and no analytics. Your messages go directly to OpenRouter and the AI model you choose, using your own key, so their privacy policies apply.',
              style: muted,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.tertiary,
                side: BorderSide(color: cs.tertiary),
              ),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete all data?'),
                    content: const Text(
                        'This removes your saved key and all chats from this phone. To fully disable the key, also delete it at openrouter.ai/settings/keys.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) {
                  await widget.onDeleteAll();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              },
              child: const Text('Delete all my data'),
            ),
          ]),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              child: Text('Early test build',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

class TypingDots extends StatefulWidget {
  final Color color;
  const TypingDots({super.key, required this.color});
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = (_c.value - i * 0.2) % 1.0;
          final o = 0.3 + 0.7 * (t < 0.5 ? t * 2 : (1 - t) * 2);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Opacity(
              opacity: o.clamp(0.3, 1.0),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: widget.color, shape: BoxShape.circle),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  final Color color;
  WavePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final back = Path()
      ..moveTo(0, h * 0.78)
      ..cubicTo(w * 0.25, h * 0.62, w * 0.5, h * 0.95, w, h * 0.7)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    final front = Path()
      ..moveTo(w * 0.3, h)
      ..cubicTo(w * 0.55, h * 0.85, w * 0.8, h * 0.9, w, h * 0.5)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(back, Paint()..color = color.withOpacity(0.08));
    canvas.drawPath(front, Paint()..color = color.withOpacity(0.10));
  }

  @override
  bool shouldRepaint(WavePainter old) => old.color != color;
}

class AisLogoPainter extends CustomPainter {
  final Color main;
  final Color accent;
  AisLogoPainter(this.main, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Paint pen(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final a = Path()
      ..moveTo(w * 0.14, h * 0.9)
      ..lineTo(w * 0.5, h * 0.1)
      ..lineTo(w * 0.86, h * 0.9);
    canvas.drawPath(a, pen(main));
    canvas.drawLine(
        Offset(w * 0.5, h * 0.1), Offset(w * 0.5, h * 0.9), pen(main));
    final s = Path()
      ..moveTo(w * 0.27, h * 0.62)
      ..cubicTo(w * 0.37, h * 0.46, w * 0.43, h * 0.46, w * 0.5, h * 0.62)
      ..cubicTo(w * 0.57, h * 0.78, w * 0.63, h * 0.78, w * 0.73, h * 0.62);
    canvas.drawPath(s, pen(accent));
  }

  @override
  bool shouldRepaint(AisLogoPainter old) =>
      old.main != main || old.accent != accent;
}

class StartView extends StatefulWidget {
  final void Function(String) onPick;
  const StartView({super.key, required this.onPick});

  @override
  State<StartView> createState() => _StartViewState();
}

class _StartViewState extends State<StartView> {
  static const _greetings = [
    'Any new ideas to explore?',
    'What are we working on today?',
    'Ready when you are.',
    'What should we figure out?',
    'Got a question worth asking?',
    "What's on your mind?",
    "Let's build something.",
    'Where shall we start?',
  ];
  late final String _greeting =
      _greetings[Random().nextInt(_greetings.length)];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 88,
              height: 88,
              child: CustomPaint(
                  painter: AisLogoPainter(cs.primary, cs.tertiary)),
            ),
            const SizedBox(height: 24),
            Text(
              _greeting,
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface),
            ),
            const SizedBox(height: 10),
            Text(
              'Ask AIS anything.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
class BackgroundWavesPainter extends CustomPainter {
  final Color main;
  final Color accent;
  BackgroundWavesPainter(this.main, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final topLeft = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.65, 0)
      ..cubicTo(w * 0.5, h * 0.08, w * 0.2, h * 0.1, 0, h * 0.18)
      ..close();
    final midRight = Path()
      ..moveTo(w, h * 0.56)
      ..cubicTo(w * 0.9, h * 0.66, w * 0.7, h * 0.72, w * 0.3, h * 0.9)
      ..lineTo(w * 0.3, h)
      ..lineTo(w, h)
      ..close();
    final bottomTeal = Path()
      ..moveTo(0, h * 0.84)
      ..cubicTo(w * 0.3, h * 0.74, w * 0.6, h * 0.95, w, h * 0.72)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    final bottomAccent = Path()
      ..moveTo(w * 0.35, h)
      ..cubicTo(w * 0.6, h * 0.88, w * 0.85, h * 0.9, w, h * 0.74)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(topLeft, Paint()..color = main.withOpacity(0.14));
    canvas.drawPath(midRight, Paint()..color = main.withOpacity(0.08));
    canvas.drawPath(bottomTeal, Paint()..color = main.withOpacity(0.12));
    canvas.drawPath(bottomAccent, Paint()..color = accent.withOpacity(0.14));
  }

  @override
  bool shouldRepaint(BackgroundWavesPainter old) =>
      old.main != main || old.accent != accent;
}

class LiveWavesPainter extends CustomPainter {
  final Color main;
  final Color accent;
  final double t;
  LiveWavesPainter(this.main, this.accent, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final a = sin(t * 2 * pi);
    final b = sin(t * 2 * pi + 2.1);
    final c = sin(t * 2 * pi + 4.2);
    final topLeft = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.65, 0)
      ..cubicTo(w * 0.5, h * (0.08 + 0.03 * a), w * 0.2, h * (0.1 + 0.03 * b),
          0, h * 0.18)
      ..close();
    final midRight = Path()
      ..moveTo(w, h * 0.56)
      ..cubicTo(w * 0.9, h * (0.66 + 0.03 * b), w * 0.7, h * (0.72 + 0.03 * c),
          w * 0.3, h * 0.9)
      ..lineTo(w * 0.3, h)
      ..lineTo(w, h)
      ..close();
    final bottomTeal = Path()
      ..moveTo(0, h * 0.84)
      ..cubicTo(w * 0.3, h * (0.74 + 0.03 * a), w * 0.6, h * (0.95 + 0.03 * c),
          w, h * 0.72)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    final bottomAccent = Path()
      ..moveTo(w * 0.35, h)
      ..cubicTo(w * 0.6, h * (0.88 + 0.03 * c), w * 0.85, h * (0.9 + 0.03 * a),
          w, h * 0.74)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(topLeft, Paint()..color = main.withOpacity(0.14));
    canvas.drawPath(midRight, Paint()..color = main.withOpacity(0.08));
    canvas.drawPath(bottomTeal, Paint()..color = main.withOpacity(0.12));
    canvas.drawPath(bottomAccent, Paint()..color = accent.withOpacity(0.14));
  }

  @override
  bool shouldRepaint(LiveWavesPainter old) =>
      old.t != t || old.main != main || old.accent != accent;
}

class AnimatedWaves extends StatefulWidget {
  final Color main;
  final Color accent;
  final bool animate;
  const AnimatedWaves({
    super.key,
    required this.main,
    required this.accent,
    required this.animate,
  });

  @override
  State<AnimatedWaves> createState() => _AnimatedWavesState();
}

class _AnimatedWavesState extends State<AnimatedWaves>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(AnimatedWaves old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: LiveWavesPainter(widget.main, widget.accent, _c.value),
        ),
      ),
    );
  }
}

class CodeCopyButton extends StatefulWidget {
  final String code;
  const CodeCopyButton({super.key, required this.code});

  @override
  State<CodeCopyButton> createState() => _CodeCopyButtonState();
}

class _CodeCopyButtonState extends State<CodeCopyButton> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = _done ? cs.primary : cs.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: widget.code));
        if (!mounted) return;
        setState(() => _done = true);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _done = false);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_done ? Icons.check : Icons.copy, size: 14, color: c),
            const SizedBox(width: 6),
            Text(_done ? 'Copied' : 'Copy',
                style: TextStyle(fontSize: 12, color: c)),
          ],
        ),
      ),
    );
  }
}

class CodeScroller extends StatefulWidget {
  final Widget child;
  const CodeScroller({super.key, required this.child});

  @override
  State<CodeScroller> createState() => _CodeScrollerState();
}

class _CodeScrollerState extends State<CodeScroller> {
  final ScrollController _c = ScrollController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          scrollbarTheme: ScrollbarThemeData(
            thumbColor: WidgetStatePropertyAll(
                cs.onSurfaceVariant.withOpacity(0.55)),
            trackColor:
                WidgetStatePropertyAll(cs.onSurface.withOpacity(0.06)),
            trackBorderColor:
                const WidgetStatePropertyAll(Colors.transparent),
            thickness: WidgetStateProperty.resolveWith((s) =>
                s.contains(WidgetState.hovered) ? 12.0 : 8.0),
            radius: const Radius.circular(6),
            minThumbLength: 48,
          ),
        ),
        child: Scrollbar(
          controller: _c,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          child: SingleChildScrollView(
            controller: _c,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}