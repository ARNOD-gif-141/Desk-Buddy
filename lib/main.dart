// Arno Link - control app for the ARNO OS Desk Buddy (Android)
// Created By- Arnod
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kBg = Color(0xFF08121B);
const kCard = Color(0xFF102232);
const kTeal = Color(0xFF1FB5C9);
const kNavy = Color(0xFF12304D);

const faceNames = [
  'Smirk', 'Winking Heart', 'Laughing', 'Crying', 'Enraged', 'Mind Blown', 'Starry Eyed', 'Thinking', 'Yawning', 'Skeptic',
  'Sweating', 'In Love', 'Determined', 'Boo', 'Silly', 'Cool', 'Ninja', 'Robot', 'Cat', 'Nerd',
  'Vampire', 'Ghost Panic', 'Angel', 'Devil', 'Money Eyes', 'Alien', 'Victorious', 'Teasing', 'Exhausted', 'Loading',
  'Glitch', 'Pixel Heart', 'Cyber Shield', 'Matrix Code', 'Neon Spiral', 'Equalizer', 'Radar', 'Battery Low', 'Charging', 'WiFi Search',
  'Bluetooth', 'Terminal', 'Skull', 'Crosshair', 'Gamepad', 'Rocket', 'Atom', 'Infinity', 'Biohazard', 'Radioactive',
  'Fire', 'Water Drop', 'Lightning', 'Snowflake', 'Sun Rays', 'Crescent Moon', 'Cloud Rain', 'Wind Gust', 'Compass', 'Bullseye',
];
const faceEmoji = [
  '😏', '😘', '😂', '😢', '😡', '🤯', '🤩', '🤔', '🥱', '🤨',
  '😅', '😍', '😤', '👻', '😜', '😎', '🥷', '🤖', '🐱', '🤓',
  '🧛', '😱', '😇', '😈', '🤑', '👽', '✌️', '😛', '😩', '⏳',
  '📺', '❤️', '🛡️', '💻', '🌀', '🎚️', '📡', '🪫', '🔋', '📶',
  '🔷', '⌨️', '💀', '⌖', '🎮', '🚀', '⚛️', '♾️', '☣️', '☢️',
  '🔥', '💧', '⚡', '❄️', '☀️', '🌙', '🌧️', '💨', '🧭', '🎯',
];

String appName(String pkg) {
  const known = {
    'com.whatsapp': 'WhatsApp', 'com.whatsapp.w4b': 'WhatsApp Biz', 'com.instagram.android': 'Instagram',
    'org.telegram.messenger': 'Telegram', 'com.google.android.gm': 'Gmail', 'com.google.android.apps.messaging': 'Messages',
    'com.samsung.android.messaging': 'Messages', 'com.google.android.dialer': 'Phone', 'com.android.phone': 'Phone',
    'com.facebook.orca': 'Messenger', 'com.twitter.android': 'X', 'com.snapchat.android': 'Snapchat', 'com.discord': 'Discord',
  };
  if (known.containsKey(pkg)) return known[pkg]!;
  final parts = pkg.split('.');
  final last = parts.isNotEmpty ? parts.last : pkg;
  return last.isEmpty ? 'App' : last[0].toUpperCase() + last.substring(1);
}

String clean(String s, int max) {
  final t = s.replaceAll('|', ' ').replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
  return t.length > max ? t.substring(0, max) : t;
}

// ------------------------------------------------------------------ Bluetooth link
class BuddyLink extends ChangeNotifier {
  static final Guid svcG = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final Guid rxG = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E');
  static final Guid txG = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E');

  BluetoothCharacteristic? _rx, _tx;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _valSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<ServiceNotificationEvent>? _notifSub;
  SharedPreferences? _prefs;
  Timer? _retry;
  String _lastNotif = '';
  DateTime _lastNotifAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool connected = false, scanning = false, forward = false;
  String status = 'Starting...';
  int face = 0;
  final Map<String, String> info = {};

  Future<void> start() async {
    _prefs = await SharedPreferences.getInstance();
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse, Permission.notification].request();
    forward = _prefs!.getBool('fwd') ?? false;
    if (forward) await setForward(true);
    final id = _prefs!.getString('dev');
    if (id != null) {
      _connect(BluetoothDevice.fromId(id));
    } else {
      await search();
    }
    _retry = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!connected && !scanning && _prefs?.getString('dev') == null) search();
    });
  }

  Future<void> forgetAndSearch() async {
    await _prefs?.remove('dev');
    await _connSub?.cancel();
    connected = false;
    notifyListeners();
    await search();
  }

  Future<void> search() async {
    if (scanning || connected) return;
    scanning = true;
    status = 'Searching for ARNO-OS...';
    notifyListeners();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
        if (name == 'ARNO-OS' || r.advertisementData.serviceUuids.contains(svcG)) {
          await FlutterBluePlus.stopScan();
          await _scanSub?.cancel();
          scanning = false;
          await _prefs?.setString('dev', r.device.remoteId.str);
          _connect(r.device);
          return;
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
    } catch (e) {
      status = 'Bluetooth problem: $e';
    }
    await Future.delayed(const Duration(seconds: 13));
    if (scanning) {
      scanning = false;
      status = 'Desk Buddy not found - is it on?';
      notifyListeners();
    }
  }

  Future<void> _connect(BluetoothDevice d) async {
    status = 'Connecting...';
    notifyListeners();
    await _connSub?.cancel();
    _connSub = d.connectionState.listen((s) async {
      if (s == BluetoothConnectionState.connected) {
        await _onConnected(d);
      } else if (s == BluetoothConnectionState.disconnected) {
        connected = false;
        _rx = null;
        _tx = null;
        status = 'Disconnected - reconnects when in range';
        notifyListeners();
      }
    });
    try {
      await d.connect(autoConnect: true, mtu: null);
    } catch (e) {
      status = 'Connect problem: $e';
      notifyListeners();
    }
  }

  Future<void> _onConnected(BluetoothDevice d) async {
    try {
      await d.requestMtu(247);
    } catch (_) {}
    final services = await d.discoverServices();
    for (final s in services) {
      if (s.uuid == svcG) {
        for (final c in s.characteristics) {
          if (c.uuid == rxG) _rx = c;
          if (c.uuid == txG) _tx = c;
        }
      }
    }
    if (_rx == null || _tx == null) {
      status = 'This is not an ARNO Desk Buddy';
      notifyListeners();
      return;
    }
    await _tx!.setNotifyValue(true);
    await _valSub?.cancel();
    _valSub = _tx!.onValueReceived.listen(_onData);
    connected = true;
    status = 'Connected';
    notifyListeners();
    await send('I?');
  }

  void _onData(List<int> v) {
    final p = utf8.decode(v, allowMalformed: true).split('|');
    if (p[0] == 'I' && p.length >= 3) {
      info[p[1]] = p.sublist(2).join('|');
    } else if (p[0] == 'S' && p.length >= 2) {
      final n = int.tryParse(p[1]);
      if (n != null) face = n;
    }
    notifyListeners();
  }

  Future<void> send(String s) async {
    if (_rx == null || !connected) return;
    try {
      await _rx!.write(utf8.encode(s), allowLongWrite: true);
    } catch (_) {}
  }

  Future<void> showFace(int n) async {
    face = n;
    notifyListeners();
    await send('F$n');
  }

  Future<bool> setForward(bool on) async {
    if (on) {
      var ok = await NotificationListenerService.isPermissionGranted();
      if (!ok) ok = await NotificationListenerService.requestPermission();
      if (!ok) return false;
      await _notifSub?.cancel();
      _notifSub = NotificationListenerService.notificationsStream.listen((e) {
        if (e.hasRemoved == true) return;
        final pkg = e.packageName ?? '';
        if (pkg.contains('arno_link')) return;
        final t = clean(e.title ?? '', 28), c = clean(e.content ?? '', 120);
        if (t.isEmpty && c.isEmpty) return;
        final key = '$pkg$t$c';
        final now = DateTime.now();
        if (key == _lastNotif && now.difference(_lastNotifAt).inSeconds < 3) return;
        _lastNotif = key;
        _lastNotifAt = now;
        send('N|${appName(pkg)}|$t|$c');
      });
    } else {
      await _notifSub?.cancel();
    }
    forward = on;
    await _prefs?.setBool('fwd', on);
    notifyListeners();
    return true;
  }
}

final link = BuddyLink();

// ------------------------------------------------------------------ app
void main() => runApp(const ArnoLinkApp());

class ArnoLinkApp extends StatelessWidget {
  const ArnoLinkApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arno Link',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kTeal, secondary: kTeal, surface: kCard),
        navigationBarTheme: NavigationBarThemeData(backgroundColor: kCard, indicatorColor: kTeal.withOpacity(.25)),
      ),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  @override
  void initState() {
    super.initState();
    link.start();
  }

  @override
  Widget build(BuildContext context) {
    const pages = [HomePage(), FacesPage(), ToolsPage(), DevicePage()];
    return Scaffold(
      body: SafeArea(child: Column(children: [const Header(), Expanded(child: pages[tab])])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: 'Control'),
          NavigationDestination(icon: Icon(Icons.emoji_emotions_rounded), label: 'Faces'),
          NavigationDestination(icon: Icon(Icons.timer_rounded), label: 'Tools'),
          NavigationDestination(icon: Icon(Icons.memory_rounded), label: 'Device'),
        ],
      ),
    );
  }
}

class Header extends StatelessWidget {
  const Header({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final on = link.connected;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [kNavy, Color(0xFF0B5568)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('assets/icon.png', width: 46, height: 46,
                  errorBuilder: (_, __, ___) => const Icon(Icons.hub_rounded, size: 40)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Arno Link', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: .5)),
                Text('Created By- Arnod', style: TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 10, color: on ? Colors.greenAccent : Colors.orangeAccent),
                const SizedBox(width: 6),
                Text(on ? 'ARNO-OS' : 'Offline', style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class Section extends StatelessWidget {
  final String title;
  final Widget child;
  const Section(this.title, this.child, {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kTeal)),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

// ------------------------------------------------------------------ Control
class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    const tiles = <List<Object>>[
      [Icons.access_time_rounded, 'Time', 'MTIME'],
      [Icons.wb_sunny_rounded, 'Weather', 'MWEATHER'],
      [Icons.calendar_view_week_rounded, '3-Day Forecast', 'MFORECAST'],
      [Icons.schedule_rounded, 'Analog Clock', 'MCLOCK'],
      [Icons.info_rounded, 'System Info', 'MINFO'],
      [Icons.bedtime_rounded, 'Sleep Clock', 'MSLEEP'],
      [Icons.sports_esports_rounded, 'Dino Game', 'MDINO'],
      [Icons.timer_outlined, 'Stopwatch', 'MSW'],
      [Icons.hourglass_bottom_rounded, 'Countdown', 'MCD'],
      [Icons.menu_book_rounded, 'Manual Pad 1', 'MMAN1'],
      [Icons.menu_book_outlined, 'Manual Pad 2', 'MMAN2'],
    ];
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
        Section(
          'Connection',
          Row(children: [
            Expanded(child: Text(link.status, style: const TextStyle(fontSize: 15))),
            FilledButton.tonal(onPressed: link.forgetAndSearch, child: const Text('Search again')),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8, left: 4),
          child: Text('Show on Desk Buddy', style: TextStyle(fontWeight: FontWeight.w700, color: kTeal)),
        ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            for (final t in tiles)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => link.send(t[2] as String),
                child: Container(
                  decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.all(8),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(t[0] as IconData, size: 28, color: kTeal),
                    const SizedBox(height: 6),
                    Text(t[1] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => link.send('F${link.face}'),
          icon: const Icon(Icons.wb_twilight_rounded),
          label: const Text('Wake Desk Buddy'),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ Faces
class FacesPage extends StatelessWidget {
  const FacesPage({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final f = link.face.clamp(0, faceNames.length - 1);
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(children: [
              IconButton.filledTonal(onPressed: () => link.showFace((f - 1 + 60) % 60), icon: const Icon(Icons.chevron_left_rounded)),
              Expanded(
                child: Column(children: [
                  Text(faceEmoji[f], style: const TextStyle(fontSize: 34)),
                  Text('${f + 1}/60  ${faceNames[f]}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
              IconButton.filledTonal(onPressed: () => link.showFace((f + 1) % 60), icon: const Icon(Icons.chevron_right_rounded)),
            ]),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: .86),
              itemCount: 60,
              itemBuilder: (context, i) {
                final sel = i == f;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => link.showFace(i),
                  child: Container(
                    decoration: BoxDecoration(
                      color: sel ? kTeal.withOpacity(.22) : kCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: sel ? kTeal : Colors.transparent, width: 1.5),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(faceEmoji[i], style: const TextStyle(fontSize: 26)),
                      const SizedBox(height: 4),
                      Text(faceNames[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ Tools
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});
  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  final msg = TextEditingController();
  final mins = TextEditingController(text: '5');
  final secs = TextEditingController(text: '0');

  @override
  void dispose() {
    msg.dispose();
    mins.dispose();
    secs.dispose();
    super.dispose();
  }

  void snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 1)));

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Section(
        'Send text to Desk Buddy',
        Column(children: [
          TextField(controller: msg, maxLength: 150, decoration: const InputDecoration(hintText: 'Type a short message...', border: OutlineInputBorder())),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () {
                final t = clean(msg.text, 150);
                if (t.isEmpty) return;
                link.send('T|$t');
                snack('Sent');
              },
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send'),
            ),
          ),
        ]),
      ),
      Section(
        'Stopwatch',
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          FilledButton.icon(onPressed: () => link.send('SW1'), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Start')),
          FilledButton.tonalIcon(onPressed: () => link.send('SW0'), icon: const Icon(Icons.stop_rounded), label: const Text('Stop')),
          OutlinedButton.icon(onPressed: () => link.send('SWR'), icon: const Icon(Icons.restart_alt_rounded), label: const Text('Reset')),
        ]),
      ),
      Section(
        'Countdown',
        Column(children: [
          Wrap(spacing: 8, children: [
            for (final m in [1, 5, 10, 25, 45])
              ActionChip(label: Text('$m min'), onPressed: () { mins.text = '$m'; secs.text = '0'; }),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: mins, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minutes', border: OutlineInputBorder()))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: secs, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Seconds', border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            FilledButton.icon(
              onPressed: () {
                final total = (int.tryParse(mins.text) ?? 0) * 60 + (int.tryParse(secs.text) ?? 0);
                if (total <= 0) return;
                link.send('CD$total');
                snack('Countdown started');
              },
              icon: const Icon(Icons.hourglass_top_rounded),
              label: const Text('Start'),
            ),
            OutlinedButton.icon(onPressed: () => link.send('CD0'), icon: const Icon(Icons.close_rounded), label: const Text('Cancel')),
          ]),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ Device
class DevicePage extends StatelessWidget {
  const DevicePage({super.key});
  @override
  Widget build(BuildContext context) {
    const rows = <List<String>>[
      ['dev', 'Device Name'], ['user', 'User Name'], ['by', 'Created By'], ['os', 'OS Version'], ['ip', 'IP Address'],
      ['ram', 'Free RAM'], ['wifi', 'WiFi'], ['rssi', 'Signal'], ['net1', 'Saved Network 1'], ['net2', 'Saved Network 2'],
      ['fw', 'Firmware'], ['tz', 'Timezone'],
    ];
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
        Section(
          'Desk Buddy details',
          Column(children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(flex: 4, child: Text(r[1], style: const TextStyle(color: Colors.white60))),
                  Expanded(flex: 5, child: Text(link.info[r[0]] ?? (link.connected ? '...' : '-'), textAlign: TextAlign.right)),
                ]),
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(onPressed: () => link.send('I?'), icon: const Icon(Icons.refresh_rounded), label: const Text('Refresh')),
            ),
          ]),
        ),
        Section(
          'Phone to Desk Buddy',
          Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Forward phone notifications'),
              subtitle: const Text('Shows each new notification on the Desk Buddy for 5 seconds'),
              value: link.forward,
              onChanged: (v) async {
                final ok = await link.setForward(v);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notification access was not granted')));
                }
              },
            ),
            const Text('Tip: Desk Buddy greets you automatically when your phone connects.', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}
