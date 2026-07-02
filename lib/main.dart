import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:local_auth/local_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString('user_password') == null) {
    await prefs.setString('user_password', '123456');
  }

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint("Firebase not initialized: $e.");
  }
  runApp(const ThemeWrapper());
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class ThemeWrapper extends StatefulWidget {
  const ThemeWrapper({super.key});

  @override
  State<ThemeWrapper> createState() => ThemeWrapperState();

  static ThemeWrapperState of(BuildContext context) =>
      context.findAncestorStateOfType<ThemeWrapperState>()!;
}

class ThemeWrapperState extends State<ThemeWrapper> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = prefs.getBool('isDarkMode') == true ? ThemeMode.dark : ThemeMode.light;
    });
  }

  void toggleTheme(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDark);
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BloodApp(themeMode: _themeMode);
  }
}

class BloodApp extends StatelessWidget {
  final ThemeMode themeMode;
  const BloodApp({super.key, required this.themeMode});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Life Flow',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          primary: Colors.red.shade800,
          secondary: Colors.redAccent,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.red.shade800,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade800,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 30),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ---------------- DATABASE SERVICE ----------------
class DatabaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String colDonors = 'donors';
  static const String colRequests = 'requests';
  static const String _historyKey = 'donation_history';
  static const String _donorsKey = 'registered_donors';

  static Future<String?> signUp(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> updatePassword(String newPassword) async {
    try {
      await _auth.currentUser?.updatePassword(newPassword);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<void> saveDonor(Donor donor) async {
    final data = donor.toMap();
    final prefs = await SharedPreferences.getInstance();
    List<String> donors = prefs.getStringList(_donorsKey) ?? [];
    donors.removeWhere((d) => jsonDecode(d)['email'] == donor.email);
    donors.add(jsonEncode(data));
    await prefs.setStringList(_donorsKey, donors);

    try {
      await _db.collection(colDonors).doc(donor.email).set(data, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<List<Donor>> getAllDonors() async {
    try {
      final snapshot = await _db.collection(colDonors).get();
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) => Donor.fromMap(doc.data())).toList();
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getStringList(_donorsKey) ?? [];
    return local.map((e) => Donor.fromMap(jsonDecode(e) as Map<String, dynamic>)).toList();
  }

  static Future<Donor?> getDonor(String email) async {
    try {
      final doc = await _db.collection(colDonors).doc(email).get();
      if (doc.exists) return Donor.fromMap(doc.data()!);
    } catch (_) {}

    final all = await getAllDonors();
    try {
      return all.firstWhere((d) => d.email == email);
    } catch (_) {
      return null;
    }
  }

  static Future<void> broadcastRequest(Map<String, dynamic> request) async {
    final timestamp = DateTime.now().toIso8601String();
    final localData = {...request, 'timestamp': timestamp};
    final cloudData = {
      ...request,
      'timestamp': timestamp,
      'serverTimestamp': FieldValue.serverTimestamp()
    };

    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList(_historyKey) ?? [];
    history.insert(0, jsonEncode(localData));
    await prefs.setStringList(_historyKey, history);

    try {
      await _db.collection(colRequests).add(cloudData);
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getRequestHistory() async {
    try {
      final snapshot = await _db.collection(colRequests)
          .orderBy('serverTimestamp', descending: true)
          .get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getStringList(_historyKey) ?? [];
    return local.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }
}

// ---------------- BIOMETRIC SERVICE ----------------
class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> canCheckBiometrics() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Access Life Flow Securely',
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

// ---------------- LOCATION SERVICE ----------------
class LocationService {
  static Future<Position?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }

    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition();
  }
}

// ---------------- UNIQUE LOGO WIDGET ----------------
class AppLogo extends StatelessWidget {
  final double size;
  final Color? color;

  const AppLogo({super.key, this.size = 100, this.color});

  @override
  Widget build(BuildContext context) {
    final primaryColor = color ?? Colors.white;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer Glow
          Container(
            width: size * 0.7,
            height: size * 0.7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.3),
                  blurRadius: size * 0.3,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),
          // Blood Drop
          Icon(Icons.water_drop_rounded, size: size, color: primaryColor),
          // Medical Cross Overlays
          Positioned(
            top: size * 0.42,
            child: Container(
              padding: EdgeInsets.all(size * 0.04),
              decoration: BoxDecoration(
                color: primaryColor == Colors.white ? Colors.red.shade900 : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: primaryColor, width: size * 0.02),
              ),
              child: Icon(
                Icons.add_rounded,
                size: size * 0.28,
                color: primaryColor == Colors.white ? Colors.white : Colors.red.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- SPLASH SCREEN ----------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red.shade400, Colors.red.shade900],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: Tween(begin: 1.0, end: 1.1).animate(_controller),
              child: const AppLogo(size: 150),
            ),
            const SizedBox(height: 30),
            const Text(
              "LIFE FLOW",
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}

// ---------------- LOGIN PAGE ----------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  bool canBiometric = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool('biometric_enabled') ?? false;
    final hasUser = prefs.getString('last_user_email') != null;

    if (await BiometricService.canCheckBiometrics()) {
      setState(() => canBiometric = isEnabled);
      
      if (isEnabled && hasUser) {
        bool didAuth = await BiometricService.authenticate();
        if (didAuth && mounted) {
          String email = prefs.getString('last_user_email')!;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => HomePage(userEmail: email)),
          );
        }
      }
    }
  }

  void _handleLogin() async {
    setState(() => isLoading = true);
    String? err = await DatabaseService.signIn(emailController.text, passwordController.text);
    if (err == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_user_email', emailController.text);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomePage(userEmail: emailController.text)),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => isLoading = false);
  }

  void _showAdminLoginDialog() {
    final keyController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Administrator Access"),
        content: TextField(
          controller: keyController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: "Master Admin Key",
            hintText: "Enter admin code",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              if (keyController.text == "123456") {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const HomePage(userEmail: "admin@lifeflow.com", isMasterAdmin: true)),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Invalid Admin Key"), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text("Access Console"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const SizedBox(height: 80),
            AppLogo(size: 100, color: Colors.red.shade800),
            const SizedBox(height: 40),
            const Text(
              "Welcome Back",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: "Email Address",
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Password",
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _handleLogin,
                    child: isLoading
                        ? const CircularProgressIndicator()
                        : const Text("Login", style: TextStyle(fontSize: 18)),
                  ),
                ),
                if (canBiometric) ...[
                  const SizedBox(width: 15),
                  IconButton(
                    onPressed: () async {
                      if (await BiometricService.authenticate()) {
                        final prefs = await SharedPreferences.getInstance();
                        String? email = prefs.getString('last_user_email');
                        if (email != null && mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => HomePage(userEmail: email)),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.fingerprint, size: 40, color: Colors.red),
                  ),
                ]
              ],
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegisterPage()),
              ),
              child: const Text("Register as a Donor"),
            ),
            const Divider(height: 60),
            TextButton.icon(
              onPressed: _showAdminLoginDialog,
              icon: const Icon(Icons.admin_panel_settings, color: Colors.grey),
              label: const Text("Administrator Access", style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- HOME PAGE ----------------
class HomePage extends StatefulWidget {
  final String userEmail;
  final bool isMasterAdmin;
  const HomePage({super.key, required this.userEmail, this.isMasterAdmin = false});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedIndex = 0;
  bool isAdmin = false;

  @override
  void initState() {
    super.initState();
    isAdmin = widget.isMasterAdmin;
    _checkAdmin();
  }

  void _checkAdmin() async {
    if (widget.isMasterAdmin) return;
    final d = await DatabaseService.getDonor(widget.userEmail);
    if (mounted && d?.role == 'admin') {
      setState(() => isAdmin = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      Dashboard(onTabRequested: (i) => setState(() => selectedIndex = i)),
      const SearchPage(),
      const RequestPage(),
      ProfilePage(userEmail: widget.userEmail),
      if (isAdmin) const AdminPanel(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedIndex == 4 ? "Admin Console" : "Life Flow"),
      ),
      body: pages[selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => setState(() => selectedIndex = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), label: "Home"),
          const NavigationDestination(icon: Icon(Icons.search), label: "Search"),
          const NavigationDestination(icon: Icon(Icons.add_circle_outline), label: "Request"),
          const NavigationDestination(icon: Icon(Icons.person_outline), label: "Profile"),
          if (isAdmin)
            const NavigationDestination(icon: Icon(Icons.admin_panel_settings), label: "Admin"),
        ],
      ),
    );
  }
}

// ---------------- DASHBOARD ----------------
class Dashboard extends StatefulWidget {
  final Function(int)? onTabRequested;
  const Dashboard({super.key, this.onTabRequested});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  String city = "Fetching location...";
  List<Map<String, dynamic>> requests = [];

  @override
  void initState() {
    super.initState();
    _load();
    _fetchLocation();
  }

  void _fetchLocation() async {
    final pos = await LocationService.getCurrentLocation();
    if (mounted && pos != null) {
      setState(() {
        city = "GPS: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}";
      });
    } else if (mounted) {
      setState(() => city = "Nairobi, KE (Default)");
    }
  }

  void _load() async {
    final h = await DatabaseService.getRequestHistory();
    if (mounted) setState(() => requests = h.take(3).toList());
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Icon(Icons.location_on, color: Colors.red),
            const SizedBox(width: 5),
            Text(city, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 20),
        _buildAIInsight(),
        const SizedBox(height: 20),
        const Text("Quick Services", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 4,
          children: [
            _serviceIcon(Icons.person_search, "Donors", Colors.red, () => widget.onTabRequested?.call(1)),
            _serviceIcon(Icons.local_hospital, "Banks", Colors.blue, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const BanksPage()));
            }),
            _serviceIcon(Icons.emergency, "Emergency", Colors.orange, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyPage()));
            }),
            _serviceIcon(Icons.history, "History", Colors.green, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()));
            }),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Urgent Requests", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            TextButton(onPressed: () => widget.onTabRequested?.call(2), child: const Text("See All")),
          ],
        ),
        ...requests.map((r) => Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.red.shade100,
              child: Text(r['blood'] ?? '?', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
            title: Text(r['location'] ?? 'Unknown Location', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(r['date'] ?? 'Just now'),
            trailing: const Icon(Icons.chevron_right),
          ),
        )),
      ],
    );
  }

  Widget _buildAIInsight() {
    return Card(
      color: Colors.blue.shade50,
      child: const ListTile(
        leading: Icon(Icons.auto_awesome, color: Colors.blue),
        title: Text("AI Demand Prediction", style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("O+ demand expected to rise by 15% in your area next week. Donate now!"),
      ),
    );
  }

  Widget _serviceIcon(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.1),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

// ---------------- SEARCH PAGE ----------------
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String search = "";
  List<Donor> donors = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final d = await DatabaseService.getAllDonors();
    if (mounted) setState(() { donors = d; loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 900 ? 3 : (screenWidth > 600 ? 2 : 1);

    final filtered = donors.where((d) =>
        d.isAvailable &&
        (d.bloodGroup.toLowerCase().contains(search.toLowerCase()) ||
        d.location.toLowerCase().contains(search.toLowerCase()))
    ).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: const InputDecoration(
              labelText: "Search Blood Group or Location",
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final d = filtered[i];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundImage: d.profilePic.isNotEmpty && !d.profilePic.startsWith('http')
                                ? FileImage(File(d.profilePic)) as ImageProvider
                                : NetworkImage("https://ui-avatars.com/api/?name=${d.name}&background=random"),
                          ),
                          title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("${d.location} • ${d.bloodGroup}", style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                              if (d.latitude != null)
                                Text("📍 Nearby: ${d.latitude!.toStringAsFixed(2)}, ${d.longitude!.toStringAsFixed(2)}", style: const TextStyle(fontSize: 10, color: Colors.red)),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.phone, color: Colors.green),
                            onPressed: () => launchUrl(Uri.parse("tel:${d.phone}")),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------- REQUEST PAGE ----------------
class RequestPage extends StatefulWidget {
  const RequestPage({super.key});

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage> {
  final locController = TextEditingController();
  final msgController = TextEditingController();
  String? group;
  bool broadcasting = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Create Blood Request", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: group,
            decoration: const InputDecoration(labelText: "Blood Group Needed"),
            items: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => setState(() => group = v),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: locController,
            decoration: const InputDecoration(
              labelText: "Hospital / Collection Point",
              prefixIcon: Icon(Icons.location_city),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: msgController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: "Additional Message"),
          ),
          const SizedBox(height: 35),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: broadcasting ? null : _broadcast,
              child: broadcasting ? const CircularProgressIndicator() : const Text("Broadcast Request"),
            ),
          ),
        ],
      ),
    );
  }

  void _broadcast() async {
    if (group == null || locController.text.isEmpty) return;
    setState(() => broadcasting = true);
    await DatabaseService.broadcastRequest({
      'blood': group,
      'location': locController.text,
      'message': msgController.text,
      'type': 'Emergency',
      'date': 'Just now'
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Broadcast Successful!"), backgroundColor: Colors.green),
      );
      setState(() {
        broadcasting = false;
        group = null;
        locController.clear();
        msgController.clear();
      });
    }
  }
}

// ---------------- PROFILE PAGE ----------------
class ProfilePage extends StatefulWidget {
  final String userEmail;
  const ProfilePage({super.key, required this.userEmail});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Donor? donor;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final d = await DatabaseService.getDonor(widget.userEmail);
    if (mounted) setState(() { donor = d; loading = false; });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null && donor != null) {
      final updatedDonor = Donor(
        donor!.name, donor!.bloodGroup, donor!.location, donor!.phone,
        email: donor!.email,
        isAvailable: donor!.isAvailable,
        profilePic: pickedFile.path,
        points: donor!.points,
        isVerified: donor!.isVerified,
        lastDonationDate: donor!.lastDonationDate,
        role: donor!.role,
      );
      await DatabaseService.saveDonor(updatedDonor);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final d = donor!;
    final screenWidth = MediaQuery.of(context).size.width;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: screenWidth > 800 ? 700 : double.infinity),
        child: ListView(
          padding: const EdgeInsets.all(25),
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 65,
                    backgroundImage: d.profilePic.isNotEmpty && !d.profilePic.startsWith('http')
                        ? FileImage(File(d.profilePic)) as ImageProvider
                        : NetworkImage("https://ui-avatars.com/api/?name=${d.name}&background=random"),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: Colors.red,
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, color: Colors.white),
                        onPressed: _pickImage,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Center(child: Text(d.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: d.isAvailable ? Colors.green.shade100 : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  d.isAvailable ? "Available to Donate" : "Busy / Not Available",
                  style: TextStyle(
                    color: d.isAvailable ? Colors.green.shade900 : Colors.red.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: SwitchListTile(
                title: const Text("Accepting Requests", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Toggle availability for blood requests"),
                value: d.isAvailable,
                activeThumbColor: Colors.red.shade800,
                onChanged: (bool value) async {
                  final updatedDonor = Donor(
                    d.name, d.bloodGroup, d.location, d.phone,
                    email: d.email,
                    isAvailable: value,
                    profilePic: d.profilePic,
                    points: d.points,
                    isVerified: d.isVerified,
                    lastDonationDate: d.lastDonationDate,
                    role: d.role,
                  );
                  await DatabaseService.saveDonor(updatedDonor);
                  _load();
                },
                secondary: Icon(
                  d.isAvailable ? Icons.check_circle : Icons.do_not_disturb_on,
                  color: d.isAvailable ? Colors.green : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _eligibilityCard(d),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _stat("Donated", "3"),
                _stat("Points", "${d.points}"),
                _stat("Lives Saved", "9"),
              ],
            ),
            const SizedBox(height: 30),
            const Text("Badges", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _badge(Icons.workspace_premium, "First Gift", Colors.amber),
                  _badge(Icons.volunteer_activism, "Saver", Colors.red),
                  _badge(Icons.verified, "Verified", Colors.green, locked: !d.isVerified),
                ],
              ),
            ),
            const SizedBox(height: 30),
            ListTile(
              leading: const Icon(Icons.qr_code, color: Colors.red),
              title: const Text("Donor ID Card"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showQR(),
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.grey),
              title: const Text("Settings"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
            ),
            const Divider(height: 40),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Logout", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('last_user_email');
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showQR() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Donor ID"),
        content: SizedBox(
          width: 200,
          height: 200,
          child: QrImageView(data: "donor_${widget.userEmail}", size: 200),
        ),
      ),
    );
  }

  Widget _eligibilityCard(Donor d) {
    bool can = true;
    String text = "Eligible to Donate";
    if (d.lastDonationDate != null) {
      final diff = DateTime.now().difference(DateTime.parse(d.lastDonationDate!)).inDays;
      if (diff < 90) {
        can = false;
        text = "Next eligible in ${90 - diff} days";
      }
    }
    return Card(
      color: can ? Colors.green.shade50 : Colors.orange.shade50,
      child: ListTile(
        leading: Icon(can ? Icons.check_circle : Icons.timer, color: can ? Colors.green : Colors.orange),
        title: const Text("Donation Eligibility", style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(text),
      ),
    );
  }

  Widget _stat(String l, String v) => Column(
    children: [
      Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red)),
      Text(l, style: const TextStyle(color: Colors.grey)),
    ],
  );

  Widget _badge(IconData i, String l, Color c, {bool locked = false}) => Padding(
    padding: const EdgeInsets.only(right: 15),
    child: Column(
      children: [
        CircleAvatar(
          backgroundColor: locked ? Colors.grey.shade200 : c.withValues(alpha: 0.1),
          child: Icon(i, color: locked ? Colors.grey : c),
        ),
        const SizedBox(height: 5),
        Text(l, style: const TextStyle(fontSize: 10)),
      ],
    ),
  );
}

// ---------------- ADMIN PANEL ----------------
class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("System Overview", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _adminStat("12", "Pending Verifications", Colors.orange)),
            const SizedBox(width: 10),
            Expanded(child: _adminStat("45", "Active Requests", Colors.red)),
          ],
        ),
        const SizedBox(height: 30),
        const Text("Management", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _adminTile(Icons.verified_user, "Verify Donors", "Review donor documentation", () {}),
        _adminTile(Icons.local_hospital, "Manage Hospitals", "Add or verify medical facilities", () {}),
        _adminTile(Icons.analytics, "AI Insights & Demand", "National blood demand predictions", () {}),
        _adminTile(Icons.people, "Manage Users", "Access control and moderation", () {}),
      ],
    );
  }

  Widget _adminStat(String v, String l, Color c) => Card(
    color: c.withValues(alpha: 0.1),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(v, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c)),
          Text(l, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    ),
  );

  Widget _adminTile(IconData icon, String title, String sub, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: Colors.red.shade50, child: Icon(icon, color: Colors.red)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ---------------- NEW PAGES ----------------

class BanksPage extends StatelessWidget {
  const BanksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final banks = [
      {'name': 'National Blood Transfusion Center', 'loc': 'Nairobi', 'stock': 'High'},
      {'name': 'Regional Blood Bank', 'loc': 'Mombasa', 'stock': 'Moderate'},
      {'name': 'Westlands Collection Point', 'loc': 'Westlands', 'stock': 'Low'},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Blood Banks")),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: banks.length,
        itemBuilder: (context, i) {
          final b = banks[i];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.local_hospital, color: Colors.red),
              title: Text(b['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(b['loc']!),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: b['stock'] == 'Low' ? Colors.red.shade100 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "${b['stock']} Stock",
                  style: TextStyle(
                    color: b['stock'] == 'Low' ? Colors.red : Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class EmergencyPage extends StatelessWidget {
  const EmergencyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Emergency Contacts")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _contactTile("Ambulance", "999", Colors.red),
          _contactTile("Red Cross", "1199", Colors.red),
          _contactTile("Police", "911", Colors.blue),
          const SizedBox(height: 30),
          const Card(
            color: Colors.orangeAccent,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                "If you are in immediate danger or have a medical emergency, please call the local authorities immediately.",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactTile(String title, String phone, Color color) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, child: const Icon(Icons.phone, color: Colors.white)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(phone),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color),
          onPressed: () => launchUrl(Uri.parse("tel:$phone")),
          child: const Text("Call"),
        ),
      ),
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Donation History")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseService.getRequestHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final history = snapshot.data ?? [];
          if (history.isEmpty) return const Center(child: Text("No history found"));

          final screenWidth = MediaQuery.of(context).size.width;
          final crossAxisCount = screenWidth > 800 ? 2 : 1;

          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: history.length,
            itemBuilder: (context, i) {
              final h = history[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red.shade50,
                    child: Text(h['blood'] ?? '?', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(h['location'] ?? 'Unknown Location', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${h['type'] ?? 'Request'} • ${h['date'] ?? 'Recently'}"),
                  trailing: const Icon(Icons.check_circle, color: Colors.green),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------- SETTINGS PAGE ----------------
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool bio = false;
  final _passController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => bio = prefs.getBool('biometric_enabled') ?? false);
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Change Password"),
        content: TextField(
          controller: _passController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: "New Password",
            hintText: "Enter at least 6 characters",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (_passController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Password too short")),
                );
                return;
              }
              String? err = await DatabaseService.updatePassword(_passController.text);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(err ?? "Password updated successfully!"),
                    backgroundColor: err == null ? Colors.green : Colors.red,
                  ),
                );
                _passController.clear();
              }
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Account Settings")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("Security", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.lock_outline, color: Colors.red),
            title: const Text("Change Password"),
            subtitle: const Text("Update your login security"),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showChangePasswordDialog,
          ),
          const Divider(height: 40),
          const Text("Preferences", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: const Text("Dark Mode"),
            value: Theme.of(context).brightness == Brightness.dark,
            onChanged: (v) => ThemeWrapper.of(context).toggleTheme(v),
          ),
          SwitchListTile(
            title: const Text("Biometric Security"),
            subtitle: const Text("Use Fingerprint or Face ID"),
            value: bio,
            onChanged: (v) async {
              if (await BiometricService.authenticate()) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('biometric_enabled', v);
                setState(() => bio = v);
              }
            },
          ),
          const Divider(),
          const ListTile(title: Text("App Version"), trailing: Text("2.1.0")),
        ],
      ),
    );
  }
}

// ---------------- REGISTER PAGE ----------------
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final name = TextEditingController();
  final email = TextEditingController();
  final pass = TextEditingController();
  final group = TextEditingController();
  final loc = TextEditingController();
  final phone = TextEditingController();
  bool loading = false;
  double? lat, lng;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Donor Registration")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const AppLogo(size: 80, color: Colors.red),
            const SizedBox(height: 30),
            TextField(controller: name, decoration: const InputDecoration(labelText: "Full Name")),
            const SizedBox(height: 15),
            TextField(controller: email, decoration: const InputDecoration(labelText: "Email")),
            const SizedBox(height: 15),
            TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: "Password")),
            const SizedBox(height: 15),
            TextField(controller: group, decoration: const InputDecoration(labelText: "Blood Group")),
            const SizedBox(height: 15),
            TextField(
              controller: loc,
              decoration: InputDecoration(
                labelText: "Location",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.my_location, color: Colors.red),
                  onPressed: _fetchGPS,
                ),
              ),
            ),
            if (lat != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text("GPS: ${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            const SizedBox(height: 15),
            TextField(controller: phone, decoration: const InputDecoration(labelText: "Phone Number")),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : _reg,
                child: loading ? const CircularProgressIndicator() : const Text("Register"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _fetchGPS() async {
    final pos = await LocationService.getCurrentLocation();
    if (!mounted) return;
    if (pos != null) {
      setState(() {
        lat = pos.latitude;
        lng = pos.longitude;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("GPS Location captured!")));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to get GPS. Enable location services."), backgroundColor: Colors.orange));
    }
  }

  void _reg() async {
    setState(() => loading = true);
    String? err = await DatabaseService.signUp(email.text, pass.text);
    if (err == null) {
      await DatabaseService.saveDonor(Donor(
        name.text, group.text, loc.text, phone.text,
        email: email.text,
        latitude: lat,
        longitude: lng,
      ));
      if (mounted) Navigator.pop(context);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
    if (mounted) setState(() => loading = false);
  }
}

// ---------------- MODELS ----------------
class Donor {
  final String name, bloodGroup, location, phone, email, profilePic;
  final bool isAvailable, isVerified;
  final int points;
  final String? lastDonationDate, role;
  final double? latitude, longitude;

  const Donor(this.name, this.bloodGroup, this.location, this.phone,
      {this.email = "",
      this.isAvailable = true,
      this.profilePic = "",
      this.points = 0,
      this.isVerified = false,
      this.lastDonationDate,
      this.role = 'user',
      this.latitude,
      this.longitude});

  Map<String, dynamic> toMap() => {
    'name': name,
    'bloodGroup': bloodGroup,
    'location': location,
    'phone': phone,
    'email': email,
    'isAvailable': isAvailable,
    'profilePic': profilePic,
    'points': points,
    'isVerified': isVerified,
    'lastDonationDate': lastDonationDate,
    'role': role,
    'latitude': latitude,
    'longitude': longitude
  };

  factory Donor.fromMap(Map<String, dynamic> m) => Donor(
    m['name'] ?? '',
    m['bloodGroup'] ?? '',
    m['location'] ?? '',
    m['phone'] ?? '',
    email: m['email'] ?? '',
    isAvailable: m['isAvailable'] ?? true,
    profilePic: m['profilePic'] ?? '',
    points: m['points'] ?? 0,
    isVerified: m['isVerified'] ?? false,
    lastDonationDate: m['lastDonationDate'],
    role: m['role'] ?? 'user',
    latitude: m['latitude'],
    longitude: m['longitude']
  );
}

class Hospital {
  final String id, name, location;
  final Map<String, int> bloodStock;
  final bool isVerified;

  const Hospital(this.id, this.name, this.location, this.bloodStock,
      {this.isVerified = false});

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'location': location,
    'bloodStock': bloodStock,
    'isVerified': isVerified
  };

  factory Hospital.fromMap(Map<String, dynamic> m) => Hospital(
    m['id'] ?? '',
    m['name'] ?? '',
    m['location'] ?? '',
    Map<String, int>.from(m['bloodStock'] ?? {}),
    isVerified: m['isVerified'] ?? false
  );
}
