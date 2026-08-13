import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _voiceWarnings = true;
  bool _autoParkingMode = false;
  bool _arabicVoice = true;
  final _homeCtrl = TextEditingController();
  final _workCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _voiceWarnings = prefs.getBool('voice_warnings') ?? true;
      _autoParkingMode = prefs.getBool('auto_parking_mode') ?? false;
      _arabicVoice = prefs.getBool('arabic_voice') ?? true;
      _homeCtrl.text = prefs.getString('home_address') ?? '';
      _workCtrl.text = prefs.getString('work_address') ?? '';
    });
  }

  Future<void> _saveAddress(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _set(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      children: [
        SwitchListTile(
          title: const Text('Spoken warnings'),
          subtitle: const Text('Collision, lane drift & drowsiness voice alerts'),
          value: _voiceWarnings,
          onChanged: (v) {
            setState(() => _voiceWarnings = v);
            _set('voice_warnings', v);
          },
        ),
        SwitchListTile(
          title: const Text('Auto parking mode'),
          subtitle: const Text('Start parking mode automatically when the trip ends'),
          value: _autoParkingMode,
          onChanged: (v) {
            setState(() => _autoParkingMode = v);
            _set('auto_parking_mode', v);
          },
        ),
        SwitchListTile(
          title: const Text('Arabic voice (العربية)'),
          subtitle: const Text('Use Arabic for spoken warnings and responses'),
          value: _arabicVoice,
          onChanged: (v) {
            setState(() => _arabicVoice = v);
            _set('arabic_voice', v);
          },
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Home & Work addresses',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _homeCtrl,
            decoration: const InputDecoration(
              labelText: 'Home address',
              helperText: 'Used by "Navigate Home" voice command & Android Auto',
            ),
            onSubmitted: (v) => _saveAddress('home_address', v),
            onTapOutside: (_) => _saveAddress('home_address', _homeCtrl.text),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: TextField(
            controller: _workCtrl,
            decoration: const InputDecoration(
              labelText: 'Work address',
              helperText: 'Used by "Navigate Work" voice command & Android Auto',
            ),
            onSubmitted: (v) => _saveAddress('work_address', v),
            onTapOutside: (_) => _saveAddress('work_address', _workCtrl.text),
          ),
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.privacy_tip_outlined),
          title: Text('Privacy'),
          subtitle: Text(
            'All AI processing and video storage happens on-device. '
            'Nothing is uploaded to a server.',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Version'),
          subtitle: Text('1.0.0'),
        ),
      ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: body,
    );
  }
}
