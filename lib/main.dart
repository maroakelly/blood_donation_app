import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set default testing password if none exists
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString('user_password') == null) {
    await prefs.setString('user_password', '123456');
  }

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint("Firebase not initialized: $e. Using local storage mode.");
  }
  runApp(const ThemeWrapper());
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

class ThemeWrapper extends StatefulWidget {
  const ThemeWrapper({super.key});

  @override
  State<ThemeWrapper> createState() => _ThemeWrapperState();

  static _ThemeWrapperState of(BuildContext context) =>
      context.findAncestorStateOfType<_ThemeWrapperState>()!;
}

class _ThemeWrapperState extends State<ThemeWrapper> {
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
      title: 'Blood Donation App',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          primary: Colors.red.shade800,
          secondary: Colors.redAccent,
          surface: Colors.white,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.red.shade800,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade800,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            elevation: 2,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
          primary: Colors.red.shade400,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey.shade900,
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade400,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ---------------- DATABASE SERVICE (FIREBASE & PERSISTENCE) ----------------
class DatabaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collection Names
  static const String colDonors = 'donors';
  static const String colRequests = 'requests';
  
  // Local Storage Keys
  static const String _historyKey = 'donation_history';
  static const String _donorsKey = 'registered_donors';

  // --- AUTHENTICATION ---
  static Future<String?> signUp(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
      return null; // Success
    } on FirebaseAuthException catch (e) {
      return e.message ?? "Registration failed.";
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null; // No error
    } on FirebaseAuthException catch (e) {
      debugPrint("Auth SignIn Error: ${e.code} - ${e.message}");
      return e.message ?? "An unknown error occurred.";
    } catch (e) {
      debugPrint("Auth SignIn Error: $e");
      return e.toString();
    }
  }

  // --- DONOR MANAGEMENT ---
  static Future<void> saveDonor(Donor donor) async {
    final data = donor.toMap();
    
    // 1. Always save locally first (Offline-first approach)
    final prefs = await SharedPreferences.getInstance();
    List<String> donors = prefs.getStringList(_donorsKey) ?? [];
    donors.removeWhere((d) {
      final map = jsonDecode(d);
      return map['email'] == donor.email;
    });
    donors.add(jsonEncode(data));
    await prefs.setStringList(_donorsKey, donors);

    // 2. Sync to Firestore if online
    try {
      await _db.collection(colDonors).doc(donor.email).set(data, SetOptions(merge: true));
      debugPrint("Donor synced to cloud successfully.");
    } catch (e) {
      debugPrint("Cloud sync failed (offline?): $e");
    }
  }

  static Future<List<Donor>> getAllDonors() async {
    try {
      // Try fetching from Cloud first
      final snapshot = await _db.collection(colDonors).get();
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) => Donor.fromMap(doc.data())).toList();
      }
    } catch (e) {
      debugPrint("Cloud fetch failed, using local backup: $e");
    }

    // Local Fallback
    final prefs = await SharedPreferences.getInstance();
    List<String> donorsJson = prefs.getStringList(_donorsKey) ?? [];
    return donorsJson.map((e) => Donor.fromMap(jsonDecode(e))).toList();
  }

  static Future<Donor?> getDonor(String email) async {
    try {
      final doc = await _db.collection(colDonors).doc(email).get();
      if (doc.exists) return Donor.fromMap(doc.data()!);
    } catch (e) {
      debugPrint("Cloud getDonor failed: $e");
    }

    final all = await getAllDonors();
    try {
      return all.firstWhere((d) => d.email == email);
    } catch (_) {
      return null;
    }
  }

  // --- REQUEST MANAGEMENT ---
  static Future<void> broadcastRequest(Map<String, dynamic> request) async {
    final timestamp = DateTime.now().toIso8601String();
    
    // Data for local storage (no FieldValue)
    final localData = {
      ...request,
      'timestamp': timestamp,
    };

    // Data for Cloud (includes FieldValue)
    final cloudData = {
      ...request,
      'timestamp': timestamp,
      'serverTimestamp': FieldValue.serverTimestamp(),
    };

    // 1. Save Locally
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> history = prefs.getStringList(_historyKey) ?? [];
      history.insert(0, jsonEncode(localData));
      await prefs.setStringList(_historyKey, history);
    } catch (e) {
      debugPrint("Local save failed: $e");
    }

    // 2. Sync to Cloud
    try {
      await _db.collection(colRequests).add(cloudData);
    } catch (e) {
      debugPrint("Cloud broadcast failed: $e");
    }
  }

  static Future<List<Map<String, dynamic>>> getRequestHistory() async {
    try {
      final snapshot = await _db.collection(colRequests)
          .orderBy('serverTimestamp', descending: true)
          .get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint("Cloud history fetch failed: $e");
    }

    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList(_historyKey) ?? [];
    return history.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }
}


// ---------------- UNIQUE LOGO WIDGET ----------------
class AppLogo extends StatelessWidget {
  final double size;
  final Color color;

  const AppLogo({super.key, this.size = 100, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(Icons.favorite, size: size, color: color),
        Positioned(
          bottom: size * 0.2,
          child: Icon(
            Icons.water_drop,
            size: size * 0.4,
            color: color == Colors.white ? Colors.red.shade800 : Colors.white,
          ),
        ),
      ],
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
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );

    _controller.forward();

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
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _opacityAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppLogo(size: 150),
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
                    const Text(
                      "Your Gift of Life",
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 80),
                    const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ],
                ),
              ),
            );
          },
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
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController(text: "");
  final TextEditingController passwordController = TextEditingController(text: "123456");
  bool isPasswordVisible = false;
  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 50),
                AppLogo(size: 100, color: Colors.red.shade800),
                const SizedBox(height: 40),
                Text(
                  "Welcome Back",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Login to continue saving lives",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                ),
                const SizedBox(height: 50),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: "Email Address",
                    hintText: "example@mail.com",
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v!.contains('@') ? null : "Enter a valid email",
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: passwordController,
                  obscureText: !isPasswordVisible,
                  decoration: InputDecoration(
                    labelText: "Password",
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(isPasswordVisible ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => isPasswordVisible = !isPasswordVisible),
                    ),
                  ),
                  validator: (v) => v!.length >= 6 ? null : "Password must be 6+ characters",
                ),
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _handleLogin,
                    child: isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : const Text("Login", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("New donor?", style: TextStyle(color: Colors.grey.shade600)),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RegisterPage()),
                        );
                      },
                      child: const Text("Register Now", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() => isLoading = true);
      
      String? errorMessage = await DatabaseService.signIn(emailController.text, passwordController.text);
      
      if (errorMessage == null) {
        _onLoginSuccess();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
      setState(() => isLoading = false);
    }
  }

  void _onLoginSuccess() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomePage(userEmail: emailController.text),
      ),
    );
  }
}

// ---------------- HOME PAGE ----------------
class HomePage extends StatefulWidget {
  final String userEmail;

  const HomePage({super.key, required this.userEmail});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedIndex = 0;
  late List<Widget> pages;

  @override
  void initState() {
    super.initState();
    _updatePages();
  }

  void _updatePages() {
    pages = [
      Dashboard(onTabRequested: (index) {
        setState(() {
          selectedIndex = index;
        });
      }),
      const SearchPage(),
      const RequestPage(),
      ProfilePage(userEmail: widget.userEmail),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _updatePages();
    return Scaffold(
      appBar: AppBar(
        title: Text("Hello, ${widget.userEmail.split('@')[0]}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: pages[selectedIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        height: 70,
        elevation: 10,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: "Home",
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: "Search",
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline_rounded),
            label: "Request",
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: "Profile",
          ),
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
  String _currentCity = "Detecting location...";
  List<Map<String, dynamic>> _urgentRequests = [];
  bool _isLoadingRequests = true;

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _loadUrgentRequests();
  }

  Future<void> _loadUrgentRequests() async {
    final history = await DatabaseService.getRequestHistory();
    if (mounted) {
      setState(() {
        _urgentRequests = history.take(3).toList();
        _isLoadingRequests = false;
      });
    }
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _currentCity = "Location disabled");
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _currentCity = "Permission denied");
        return;
      }
    }
    
    try {
      Position position = await Geolocator.getCurrentPosition();
      // In a real app, use geocoding to get city name. 
      // Mocking for now:
      setState(() => _currentCity = "Nairobi, KE (Lat: ${position.latitude.toStringAsFixed(2)})");
    } catch (e) {
      setState(() => _currentCity = "Location error");
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 600 ? 4 : 2;

    return RefreshIndicator(
      onRefresh: _loadUrgentRequests,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
        Row(
          children: [
            const Icon(Icons.location_on, color: Colors.red, size: 20),
            const SizedBox(width: 5),
            Text(_currentCity, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 15),
        const Text(
          "Quick Services",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 15),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 1.1,
          children: [
            _buildActionCard(context, "Find Donor", Icons.person_search_rounded, Colors.red, () {
              widget.onTabRequested?.call(1); // Switch to Search tab
            }),
            _buildActionCard(context, "Emergency", Icons.emergency_rounded, Colors.orange, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyPage()));
            }),
            _buildActionCard(context, "Blood Bank", Icons.local_hospital_rounded, Colors.blue, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const BloodBankPage()));
            }),
            _buildActionCard(context, "History", Icons.history_rounded, Colors.green, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()));
            }),
          ],
        ),
        const SizedBox(height: 30),
        const Text(
          "Smart Match Suggestion",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        _buildSmartMatchTile(),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Urgent Requests",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => widget.onTabRequested?.call(2), 
              child: const Text("View All")
            ),
          ],
        ),
        if (_isLoadingRequests)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
        else if (_urgentRequests.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text("No urgent requests found", style: TextStyle(color: Colors.grey)),
          )
        else
          ..._urgentRequests.map((r) => _buildRequestTile(
            r['blood'] ?? '?', 
            r['location'] ?? 'Unknown', 
            r['date'] ?? 'Recent',
            message: r['message']
          )),
        ],
      ),
    );
  }

  Widget _buildSmartMatchTile() {
    return Card(
      color: Colors.red.shade50,
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.auto_awesome, color: Colors.white)),
        title: const Text("Best Match Found!", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        subtitle: const Text("Maroa Kelly (O+) is 500m away and available."),
        trailing: const Icon(Icons.chevron_right, color: Colors.red),
        onTap: () => widget.onTabRequested?.call(1),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color.withAlpha(200),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestTile(String blood, String location, String dist, {String? message}) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              blood,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade800,
              ),
            ),
          ),
        ),
        title: Text(location, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dist),
            if (message != null && message.isNotEmpty)
              Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {},
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
  List<Donor> donorsList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDonors();
  }

  Future<void> _loadDonors() async {
    final savedDonors = await DatabaseService.getAllDonors();
    // Pre-populate with some mock data if empty
    if (savedDonors.isEmpty) {
      savedDonors.addAll([
        const Donor("Anna Itotiah W.", "O+", "Nairobi", "+254700111222", email: "anna@mail.com"),
        const Donor("Sharon Kendi.", "B-", "Nakuru", "+254700333444", email: "sharon@mail.com"),
        const Donor("Faith Mueni.", "A+", "Mombasa", "+254700555666", email: "faith@mail.com"),
      ]);
    }
    if (mounted) {
      setState(() {
        donorsList = savedDonors;
        isLoading = false;
      });
    }
  }

  ImageProvider _getImageProvider(String path) {
    if (path.isEmpty) {
      return const NetworkImage("https://ui-avatars.com/api/?name=User&background=random");
    }
    if (path.startsWith('http') || path.startsWith('https')) {
      return NetworkImage(path);
    }
    return FileImage(File(path));
  }

  Future<void> _makeCall(String phoneNumber) async {
    final Uri url = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch dialer")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 900 ? 3 : (screenWidth > 600 ? 2 : 1);

    final filtered = donorsList
        .where((d) => 
            d.isAvailable &&
            (d.bloodGroup.toLowerCase().contains(search.toLowerCase()) ||
             d.location.toLowerCase().contains(search.toLowerCase()) ||
             d.name.toLowerCase().contains(search.toLowerCase())))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: const InputDecoration(
              labelText: "Search Donor, Group or Location",
              hintText: "e.g. O+, Nairobi, Anna",
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: isLoading 
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                ? const Center(child: Text("No available donors found"))
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
                            backgroundColor: Colors.red.shade800,
                            backgroundImage: _getImageProvider(d.profilePic),
                            child: d.profilePic.isEmpty 
                                ? Text(d.bloodGroup, style: const TextStyle(color: Colors.white, fontSize: 12))
                                : null,
                          ),
                          title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                          subtitle: Text("${d.location} • ${d.bloodGroup}", style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.phone_enabled_rounded, color: Colors.green, size: 20),
                            onPressed: () => _makeCall(d.phone),
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
  final TextEditingController locationController = TextEditingController();
  final TextEditingController messageController = TextEditingController();
  String? selectedBloodGroup;
  final List<String> bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  bool isBroadcasting = false;

  @override
  void dispose() {
    locationController.dispose();
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isTablet ? 600 : double.infinity),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Create Blood Request",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "Fill the details below to notify nearby donors.",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
              const SizedBox(height: 35),
              DropdownButtonFormField<String>(
                value: selectedBloodGroup,
                decoration: const InputDecoration(
                  labelText: "Blood Group Needed",
                  prefixIcon: Icon(Icons.bloodtype_rounded, color: Colors.red),
                ),
                items: bloodGroups.map((group) {
                  return DropdownMenuItem(value: group, child: Text(group));
                }).toList(),
                onChanged: (val) => setState(() => selectedBloodGroup = val),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: "Hospital Name / Location",
                  prefixIcon: Icon(Icons.location_on_rounded, color: Colors.red),
                  hintText: "e.g. City General Hospital",
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: messageController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: "Message",
                  alignLabelWithHint: true,
                  hintText: "Why is the blood needed? (Optional)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 35),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: isBroadcasting ? null : _handleBroadcast,
                  child: isBroadcasting 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Broadcast Request", 
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                      ),
                ),
              ),
              const SizedBox(height: 20),
              if (isBroadcasting)
                const Center(
                  child: Text(
                    "Sending notifications to nearby donors...",
                    style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleBroadcast() async {
    if (selectedBloodGroup != null && locationController.text.isNotEmpty) {
      setState(() => isBroadcasting = true);
      
      try {
        await DatabaseService.broadcastRequest({
          'blood': selectedBloodGroup,
          'location': locationController.text.trim(),
          'message': messageController.text.trim(),
          'type': 'Emergency Request',
          'date': 'Just now',
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 10),
                  Text("Request for $selectedBloodGroup broadcasted!"),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          
          // Clear form
          setState(() {
            selectedBloodGroup = null;
            locationController.clear();
            messageController.clear();
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to broadcast: $e"), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => isBroadcasting = false);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select blood group and hospital"),
          backgroundColor: Colors.orange,
        ),
      );
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
  Donor? _donor;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final donor = await DatabaseService.getDonor(widget.userEmail);
    if (mounted) {
      setState(() {
        _donor = donor;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        // Create a donor object if it doesn't exist
        final currentDonor = _donor ?? Donor(
          widget.userEmail.split('@')[0],
          "Unknown",
          "Unknown",
          "",
          email: widget.userEmail,
        );

        final updatedDonor = Donor(
          currentDonor.name,
          currentDonor.bloodGroup,
          currentDonor.location,
          currentDonor.phone,
          email: currentDonor.email,
          isAvailable: currentDonor.isAvailable,
          profilePic: pickedFile.path,
        );

        setState(() {
          _donor = updatedDonor;
        });

        await DatabaseService.saveDonor(updatedDonor);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Profile picture updated!")),
          );
        }
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to pick image")),
        );
      }
    }
  }

  void _toggleAvailability(bool value) async {
    // Create a donor object if it doesn't exist to allow toggling even if profile isn't fully set up
    final currentDonor = _donor ?? Donor(
      widget.userEmail.split('@')[0],
      "Unknown",
      "Unknown",
      "",
      email: widget.userEmail,
    );

    final updatedDonor = Donor(
      currentDonor.name,
      currentDonor.bloodGroup,
      currentDonor.location,
      currentDonor.phone,
      email: currentDonor.email,
      isAvailable: value,
      profilePic: currentDonor.profilePic,
    );

    // Optimistic UI update
    setState(() {
      _donor = updatedDonor;
    });

    try {
      await DatabaseService.saveDonor(updatedDonor);
    } catch (e) {
      // Revert if it fails
      if (mounted) {
        setState(() {
          _donor = currentDonor;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to update status")),
        );
      }
    }
  }

  ImageProvider _getImageProvider(String path) {
    if (path.isEmpty) {
      return NetworkImage("https://ui-avatars.com/api/?name=${widget.userEmail}&background=random");
    }
    if (path.startsWith('http') || path.startsWith('https')) {
      return NetworkImage(path);
    }
    // Check if file exists to avoid crashes
    final file = File(path);
    if (file.existsSync()) {
      return FileImage(file);
    }
    return NetworkImage("https://ui-avatars.com/api/?name=${widget.userEmail}&background=random");
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    final name = _donor?.name ?? widget.userEmail.split('@')[0];
    final isAvailable = _donor?.isAvailable ?? true;
    final bloodGroup = _donor?.bloodGroup ?? "N/A";

    return ListView(
      padding: const EdgeInsets.all(25),
      children: [
        Center(
          child: Stack(
            children: [
              InkWell(
                onTap: _pickImage,
                borderRadius: BorderRadius.circular(65),
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red.shade800, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(25),
                        blurRadius: 10,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: ClipOval(
                    child: Image(
                      image: _getImageProvider(_donor?.profilePic ?? ""),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.person, size: 80, color: Colors.grey);
                      },
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 5,
                right: 5,
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade800,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        Center(
          child: Column(
            children: [
              Text(
                name, 
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isAvailable ? Colors.green.withAlpha(30) : Colors.red.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isAvailable ? Colors.green.withAlpha(100) : Colors.red.withAlpha(100),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isAvailable ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isAvailable ? "Available to Donate" : "Currently Busy", 
                      style: TextStyle(
                        color: isAvailable ? Colors.green.shade700 : Colors.red.shade700, 
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SwitchListTile(
            title: const Text("Accepting Requests", style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(isAvailable ? "Your profile is visible to hospitals" : "You are currently hidden from search"),
            value: isAvailable,
            onChanged: _toggleAvailability,
            activeThumbColor: Colors.green,
            activeColor: Colors.green.withAlpha(50),
            secondary: Icon(
              isAvailable ? Icons.check_circle : Icons.do_not_disturb_on, 
              color: isAvailable ? Colors.green : Colors.grey
            ),
          ),
        ),
        const SizedBox(height: 25),
        const _ProfileStatRow(),
        const SizedBox(height: 30),
        _buildProfileItem(context, Icons.bloodtype, "My Blood Group", bloodGroup),
        _buildProfileItem(context, Icons.history, "Donation History", "Check History", onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()));
        }),
        _buildProfileItem(context, Icons.settings, "Account Settings", "", onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
        }),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage())),
          icon: const Icon(Icons.logout, color: Colors.red),
          label: const Text("Sign Out", style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  Widget _buildProfileItem(BuildContext context, IconData icon, String title, String value, {VoidCallback? onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      child: ListTile(
        leading: Icon(icon, color: Colors.red.shade800),
        title: Text(title),
        onTap: onTap,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value.isNotEmpty) Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _ProfileStatRow extends StatelessWidget {
  const _ProfileStatRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStat("Donated", "3"),
        _buildStat("Requested", "1"),
        _buildStat("Lives Saved", "9"),
      ],
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red)),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}

class Donor {
  final String name;
  final String bloodGroup;
  final String location;
  final String phone;
  final String email;
  final bool isAvailable;
  final String profilePic;

  const Donor(this.name, this.bloodGroup, this.location, this.phone, 
      {this.email = "", this.isAvailable = true, this.profilePic = ""});

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'bloodGroup': bloodGroup,
      'location': location,
      'phone': phone,
      'email': email,
      'isAvailable': isAvailable,
      'profilePic': profilePic,
    };
  }

  factory Donor.fromMap(Map<String, dynamic> map) {
    return Donor(
      map['name'] ?? '',
      map['bloodGroup'] ?? '',
      map['location'] ?? '',
      map['phone'] ?? '',
      email: map['email'] ?? '',
      isAvailable: map['isAvailable'] ?? true,
      profilePic: map['profilePic'] ?? '',
    );
  }
}

// ---------------- NEW PAGES FOR QUICK SERVICES ----------------

class EmergencyPage extends StatelessWidget {
  const EmergencyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Emergency Contacts")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildEmergencyCard(context, "Ambulance", "999", Colors.red),
          _buildEmergencyCard(context, "Red Cross", "1199", Colors.red),
          _buildEmergencyCard(context, "Police", "911", Colors.blue),
          const SizedBox(height: 20),
          const Card(
            color: Colors.orangeAccent,
            child: Padding(
              padding: EdgeInsets.all(15),
              child: Text(
                "In case of a medical emergency, please call the ambulance immediately.",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyCard(BuildContext context, String title, String phone, Color color) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, child: const Icon(Icons.phone, color: Colors.white)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(phone),
        trailing: ElevatedButton(
          onPressed: () async {
            final Uri url = Uri.parse('tel:$phone');
            if (await canLaunchUrl(url)) {
              await launchUrl(url);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: color),
          child: const Text("Call"),
        ),
      ),
    );
  }
}

class BloodBankPage extends StatelessWidget {
  const BloodBankPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Blood Banks")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildBankTile("National Blood Transfusion Center", "Nairobi", "Open 24/7"),
          _buildBankTile("Regional Blood Bank", "Mombasa", "8 AM - 5 PM"),
          _buildBankTile("Central Blood Bank", "Kisumu", "8 AM - 6 PM"),
        ],
      ),
    );
  }

  Widget _buildBankTile(String name, String location, String hours) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.local_hospital, color: Colors.red),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("$location • $hours"),
        trailing: const Icon(Icons.directions),
        onTap: () {},
      ),
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Donation History")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseService.getRequestHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final history = snapshot.data ?? [];
          if (history.isEmpty) {
            return const Center(child: Text("No history found."));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final item = history[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red.shade100,
                    child: Text(item['blood'] ?? '?', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(item['location'] ?? 'Unknown Location', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${item['type'] ?? 'Request'} • ${item['date'] ?? _formatTimestamp(item['timestamp'])}"),
                      if (item['message'] != null && item['message'].toString().isNotEmpty)
                        Text(
                          item['message'],
                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                  trailing: const Icon(Icons.check_circle, color: Colors.green),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return "Recent";
    if (timestamp is String) {
      try {
        final dt = DateTime.parse(timestamp);
        return "${dt.day}/${dt.month} ${dt.hour}:${dt.minute}";
      } catch (_) {
        return timestamp;
      }
    }
    return "Recent";
  }
}

// ---------------- SETTINGS PAGE ----------------
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _oldPassController = TextEditingController();
  final _newPassController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final themeWrapper = ThemeWrapper.of(context);
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text("Account Settings")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("Appearance", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: const Text("Dark Mode"),
            subtitle: const Text("Enable dark theme for the app"),
            secondary: const Icon(Icons.dark_mode_rounded),
            value: isDark,
            onChanged: (val) => themeWrapper.toggleTheme(val),
          ),
          const Divider(height: 40),
          const Text("Security", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ListTile(
            title: const Text("Change Password"),
            subtitle: const Text("Update your login credentials"),
            leading: const Icon(Icons.lock_reset_rounded),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showChangePasswordDialog,
          ),
          const Divider(height: 40),
          const Text("About", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const ListTile(
            title: Text("Version"),
            trailing: Text("1.0.0"),
            leading: Icon(Icons.info_outline),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Change Password"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _oldPassController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Old Password"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _newPassController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "New Password"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              // Password changes should be handled securely via Firebase Auth
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Security update requested.")),
              );
              _oldPassController.clear();
              _newPassController.clear();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final bloodController = TextEditingController();
  final locationController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController(text: "123456");
  bool isAvailable = true;
  bool isLoading = false;

  @override
  void dispose() {
    nameController.dispose();
    bloodController.dispose();
    locationController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Donor Registration")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const AppLogo(size: 80, color: Colors.red),
              const SizedBox(height: 30),
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Full Name", prefixIcon: Icon(Icons.person)),
                validator: (v) => v!.isEmpty ? "Enter your name" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(labelText: "Email Address", prefixIcon: Icon(Icons.email)),
                validator: (v) => v!.contains('@') ? null : "Enter a valid email",
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Create Password", prefixIcon: Icon(Icons.lock)),
                validator: (v) => v!.length >= 6 ? null : "6+ characters required",
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: bloodController,
                decoration: const InputDecoration(labelText: "Blood Group (e.g. O+)", prefixIcon: Icon(Icons.bloodtype)),
                validator: (v) => v!.isEmpty ? "Enter blood group" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: locationController,
                decoration: const InputDecoration(labelText: "Location/City", prefixIcon: Icon(Icons.location_city)),
                validator: (v) => v!.isEmpty ? "Enter location" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: "Phone Number", prefixIcon: Icon(Icons.phone)),
                keyboardType: TextInputType.phone,
                validator: (v) => v!.length >= 10 ? null : "Enter valid phone",
              ),
              const SizedBox(height: 15),
              SwitchListTile(
                title: const Text("Available for donation?"),
                value: isAvailable,
                onChanged: (v) => setState(() => isAvailable = v),
                secondary: const Icon(Icons.event_available),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _handleRegister,
                  child: isLoading 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text("Register as Donor"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleRegister() async {
    if (_formKey.currentState!.validate()) {
      setState(() => isLoading = true);
      
      // Duplicate prevention (Check local & could check Firebase)
      final existing = await DatabaseService.getAllDonors();
      if (existing.any((d) => d.phone == phoneController.text.trim())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Phone number already registered!")),
        );
        setState(() => isLoading = false);
        return;
      }

      // 1. Firebase Auth Signup
      String? authError = await DatabaseService.signUp(emailController.text, passwordController.text);
      if (authError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(authError), backgroundColor: Colors.red),
        );
        setState(() => isLoading = false);
        return;
      }
      
      // 2. Save Donor Info
      final donor = Donor(
        nameController.text.trim(),
        bloodController.text.trim().toUpperCase(),
        locationController.text.trim(),
        phoneController.text.trim(),
        email: emailController.text.trim(),
        isAvailable: isAvailable,
      );
      await DatabaseService.saveDonor(donor);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Registration Successful!")),
        );
        Navigator.pop(context);
      }
      setState(() => isLoading = false);
    }
  }
}
