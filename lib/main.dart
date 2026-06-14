import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:typed_data';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// BACKGROUND HANDLER (Saat Aplikasi Ditutup / Latar Belakang)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['tipe'] == 'alarm_panik') {
    // CEK KTP: Ambil token HP ini, bandingkan dengan token pengirim
    String? myToken = await FirebaseMessaging.instance.getToken();
    if (message.data['sender_token'] != myToken) {
      _ledakkanAlarm(message.data);
    } else {
      print("INFO: Ini adalah pantulan sinyal dari HP sendiri. Alarm dibatalkan.");
    }
  }
}

Future<void> _ledakkanAlarm(Map<String, dynamic> data) async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'alarm_darurat',
    'Alarm Darurat Warga',
    description: 'Kanal khusus untuk membunyikan sirine panik',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('sirine'),
    enableVibration: true,
  );

  final Int32List insistentFlag = Int32List.fromList(<int>[4]);

  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    channel.id,
    channel.name,
    channelDescription: channel.description,
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    additionalFlags: insistentFlag,
    sound: const RawResourceAndroidNotificationSound('sirine'),
  );

  final NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    id: DateTime.now().millisecond,
    title: data['title'] ?? '🚨 DARURAT!',
    body: data['body'] ?? 'Bantuan dibutuhkan segera!',
    notificationDetails: platformDetails,
    payload: 'matikan_alarm',
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  const AndroidInitializationSettings initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings = InitializationSettings(android: initSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    settings: initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload == 'matikan_alarm') {
        flutterLocalNotificationsPlugin.cancelAll();
      }
    },
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const PanicButtonApp());
}

class PanicButtonApp extends StatelessWidget {
  const PanicButtonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Panic Button',
      theme: ThemeData(
        primarySwatch: Colors.red,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
      ),
      home: const HalamanLogin(),
    );
  }
}

// ==========================================
// HALAMAN 1: LOGIN WARGA
// ==========================================
class HalamanLogin extends StatefulWidget {
  const HalamanLogin({super.key});

  @override
  State<HalamanLogin> createState() => _HalamanLoginState();
}

class _HalamanLoginState extends State<HalamanLogin> {
  String komunitasDiketik = '';
  final TextEditingController namaController = TextEditingController();
  final TextEditingController lokasiController = TextEditingController();
  final TextEditingController pinController = TextEditingController();
  List<String> daftarKomunitas = [];

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance.collection('komunitas').snapshots().listen((snapshot) {
      if(mounted) {
        setState(() {
          daftarKomunitas = snapshot.docs.map((doc) => doc.id).toList();
        });
      }
    });
  }

  Future<void> loginWarga() async {
    final komunitas = komunitasDiketik.trim();
    final nama = namaController.text.trim();
    final lokasi = lokasiController.text.trim();
    final pin = pinController.text.trim();

    if (komunitas.isEmpty || nama.isEmpty || lokasi.isEmpty || pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Semua kolom data wajib diisi!')));
      return;
    }

    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('komunitas').doc(komunitas).get();

      if (doc.exists && doc.get('pin') == pin) {
        FirebaseMessaging messaging = FirebaseMessaging.instance;
        await messaging.requestPermission();

        String topikAman = komunitas.replaceAll(' ', '_').toLowerCase();
        await messaging.subscribeToTopic(topikAman);

        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Berhasil Masuk!'), backgroundColor: Colors.green)
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HalamanUtama(
              namaKomunitas: komunitas,
              namaWarga: nama,
              detailLokasi: lokasi,
              topikFCM: topikAman,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Komunitas tidak ditemukan atau PIN Salah!'), backgroundColor: Colors.red)
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrasi Keamanan', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.security, size: 80, color: Colors.red),
              const SizedBox(height: 24),
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.length < 3) return const Iterable<String>.empty();
                  return daftarKomunitas.where((String option) => option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                },
                onSelected: (String selection) => komunitasDiketik = selection,
                fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                  return TextField(controller: controller, focusNode: focusNode, onChanged: (value) => komunitasDiketik = value, decoration: const InputDecoration(labelText: 'Nama Lingkungan/Komunitas', hintText: 'Ketik min. 3 huruf', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_city)));
                },
              ),
              const SizedBox(height: 16),
              TextField(controller: namaController, decoration: const InputDecoration(labelText: 'Nama Panggilan / Kepala Keluarga', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
              const SizedBox(height: 16),
              TextField(controller: lokasiController, decoration: const InputDecoration(labelText: 'Detail Lokasi (Misal: RT 02 / Blok C6)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.home))),
              const SizedBox(height: 16),
              TextField(controller: pinController, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN Komunitas', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock))),
              const SizedBox(height: 32),
              ElevatedButton(onPressed: loginWarga, style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 16)), child: const Text('MASUK', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold))),
              const SizedBox(height: 16),
              TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const HalamanBuatKomunitas())), child: const Text('Belum terdaftar? Buat Lingkungan Baru', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// HALAMAN 2: BUAT KOMUNITAS BARU (ADMIN)
// ==========================================
class HalamanBuatKomunitas extends StatefulWidget {
  const HalamanBuatKomunitas({super.key});
  @override
  State<HalamanBuatKomunitas> createState() => _HalamanBuatKomunitasState();
}

class _HalamanBuatKomunitasState extends State<HalamanBuatKomunitas> {
  final TextEditingController namaKomunitasBaruController = TextEditingController();
  final TextEditingController pinBaruController = TextEditingController();

  Future<void> simpanKomunitasBaru() async {
    final nama = namaKomunitasBaruController.text.trim();
    final pin = pinBaruController.text.trim();
    if (nama.length < 4) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Minimal 4 huruf!'), backgroundColor: Colors.orange)); return; }
    if (pin.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN wajib diisi!'))); return; }
    try {
      await FirebaseFirestore.instance.collection('komunitas').doc(nama).set({'pin': pin, 'dibuat_pada': FieldValue.serverTimestamp()});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Komunitas $nama berhasil dibuat!'), backgroundColor: Colors.green));
      Navigator.pop(context);
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e'))); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daftar Lingkungan Baru', style: TextStyle(color: Colors.white, fontSize: 18)), backgroundColor: Colors.red),
      body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.group_add, size: 80, color: Colors.red), const SizedBox(height: 24), const Text('Buat PIN rahasia dan bagikan ke warga terpercaya.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)), const SizedBox(height: 24),
        TextField(controller: namaKomunitasBaruController, decoration: const InputDecoration(labelText: 'Nama Lingkungan (Min. 4 Huruf)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_city))), const SizedBox(height: 16),
        TextField(controller: pinBaruController, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Buat PIN Rahasia (Angka)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.key))), const SizedBox(height: 32),
        ElevatedButton(onPressed: simpanKomunitasBaru, style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 16)), child: const Text('DAFTARKAN', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold))),
      ]))),
    );
  }
}

// ==========================================
// HALAMAN 3: HALAMAN UTAMA (PANIC BUTTON DENGAN MODAL)
// ==========================================
class HalamanUtama extends StatefulWidget {
  final String namaKomunitas;
  final String namaWarga;
  final String detailLokasi;
  final String topikFCM;

  const HalamanUtama({
    super.key,
    required this.namaKomunitas,
    required this.namaWarga,
    required this.detailLokasi,
    required this.topikFCM,
  });

  @override
  State<HalamanUtama> createState() => _HalamanUtamaState();
}

class _HalamanUtamaState extends State<HalamanUtama> {

  @override
  void initState() {
    super.initState();
    // FOREGROUND HANDLER (Saat Aplikasi Terbuka)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (message.data['tipe'] == 'alarm_panik') {

        // CEK KTP: Ambil token HP ini, bandingkan dengan token pengirim
        String? myToken = await FirebaseMessaging.instance.getToken();

        if (message.data['sender_token'] != myToken) {
          _ledakkanAlarm(message.data);

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              backgroundColor: Colors.red.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Column(
                children: [
                  Icon(Icons.warning_rounded, color: Colors.red, size: 60),
                  SizedBox(height: 10),
                  Text('STATUS DARURAT!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 24)),
                ],
              ),
              content: Text(
                message.data['body'] ?? 'Ada warga yang butuh bantuan!',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  ),
                  onPressed: () {
                    flutterLocalNotificationsPlugin.cancelAll();
                    Navigator.pop(context);
                  },
                  child: const Text('SAYA MENGERTI / TUTUP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                )
              ],
            ),
          );
        } else {
          print("INFO: Pantulan sinyal dari diri sendiri tertangkap di Foreground, diabaikan.");
        }
      }
    });
  }

  Future<void> tekanTombolPanik(BuildContext context) async {
    FirebaseFirestore.instance.collection('darurat').add({
      'komunitas': widget.namaKomunitas, 'topik': widget.topikFCM, 'warga': widget.namaWarga, 'lokasi': widget.detailLokasi, 'waktu': FieldValue.serverTimestamp(),
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mengirim Sinyal Darurat...'), backgroundColor: Colors.orange, duration: Duration(seconds: 2)));

    try {
      // PERUBAHAN: Mengambil KTP HP ini dan mengirimkannya ke VPS
      String? myToken = await FirebaseMessaging.instance.getToken();

      final response = await http.post(
        Uri.parse('https://panic.duitkas.com/index.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'komunitas': widget.namaKomunitas,
          'topik': widget.topikFCM,
          'warga': widget.namaWarga,
          'lokasi': widget.detailLokasi,
          'sender_token': myToken ?? '' // Diselipkan di sini
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sinyal Darurat BERHASIL Terkirim ke Warga!'), backgroundColor: Colors.green, duration: Duration(seconds: 4)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengirim sinyal: Kode ${response.statusCode}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error Koneksi: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Lingkungan ${widget.namaKomunitas}', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Halo, ${widget.namaWarga}\nLokasi: ${widget.detailLokasi}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 60),
            GestureDetector(
              onTap: () => tekanTombolPanik(context),
              child: Container(
                width: 250, height: 250,
                decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.5), spreadRadius: 10, blurRadius: 20, offset: const Offset(0, 10))]),
                child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.warning_rounded, size: 80, color: Colors.white), SizedBox(height: 10),
                  Text('PANIC\nBUTTON', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
                ])),
              ),
            ),
            const SizedBox(height: 60),
            const Text('TEKAN SAAT KEADAAN DARURAT!\nSemua warga akan menerima alarm.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}