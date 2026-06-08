import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const BloodApp());
}

class BloodApp extends StatelessWidget {
  const BloodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blood Donation App',
      debugShowCheckedModeBanner: false,
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
      home: const SplashScreen(),
    );
  }
}

// ---------------- STORAGE SERVICE ----------------
class StorageService {
  static const String _historyKey = 'donation_history';
  static const String _donorsKey = 'registered_donors';

  static Future<void> saveRequest(Map<String, String> request) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList(_historyKey) ?? [];
    history.insert(0, jsonEncode({
      ...request,
      'date': DateTime.now().toString().split(' ')[0],
    }));
    await prefs.setStringList(_historyKey, history);
  }

  static Future<List<Map<String, dynamic>>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList(_historyKey) ?? [];
    return history.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  static Future<void> saveDonor(Donor donor) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> donors = prefs.getStringList(_donorsKey) ?? [];
    donors.add(jsonEncode({
      'name': donor.name,
      'bloodGroup': donor.bloodGroup,
      'location': donor.location,
      'phone': donor.phone,
    }));
    await prefs.setStringList(_donorsKey, donors);
  }

  static Future<List<Donor>> getDonors() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> donorsJson = prefs.getStringList(_donorsKey) ?? [];
    return donorsJson.map((e) {
      final map = jsonDecode(e) as Map<String, dynamic>;
      return Donor(
        map['name'] ?? '',
        map['bloodGroup'] ?? '',
        map['location'] ?? '',
        map['phone'] ?? '',
      );
    }).toList();
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
  final TextEditingController nameController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
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
                "Every drop counts Start here",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
              const SizedBox(height: 50),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: "Full Name",
                  hintText: "Enter your name",
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (nameController.text.trim().isNotEmpty) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HomePage(userName: nameController.text.trim()),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Please enter your name to proceed"),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: const Text("Continue", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
    );
  }
}

// ---------------- HOME PAGE ----------------
class HomePage extends StatefulWidget {
  final String userName;

  const HomePage({super.key, required this.userName});

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
      ProfilePage(userName: widget.userName),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _updatePages(); // Ensure pages are updated if needed
    return Scaffold(
      appBar: AppBar(
        title: Text("Hello, ${widget.userName}"),
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
class Dashboard extends StatelessWidget {
  final Function(int)? onTabRequested;
  const Dashboard({super.key, this.onTabRequested});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          "Quick Services",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 15),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 1.1,
          children: [
            _buildActionCard(context, "Find Donor", Icons.person_search_rounded, Colors.red, () {
              onTabRequested?.call(1); // Switch to Search tab
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Urgent Requests",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            TextButton(onPressed: () {}, child: const Text("View All")),
          ],
        ),
        _buildRequestTile("O+", "Kenyatta Hospital", "2.5 km away"),
        _buildRequestTile("A-", "Aga Khan Hospital", "5.0 km away"),
        _buildRequestTile("B+", "Nairobi Hospital", "1.2 km away"),
      ],
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

  Widget _buildRequestTile(String blood, String location, String dist) {
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
        subtitle: Text(dist),
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
  List<Donor> donorsList = [
    const Donor("Anna Itotiah W.", "O+", "Nairobi", "+254 700 111 222"),
    const Donor("Sharon Kendi.", "B-", "Nakuru", "+254 700 333 444"),
    const Donor("Faith Mueni.", "A+", "Mombasa", "+254 700 555 666"),
    const Donor("Roy Gichinga.", "AB+", "Kisumu", "+254 700 777 888"),
    const Donor("Michelle Njogu.", "O-", "Eldoret", "+254 700 999 000"),
  ];

  @override
  void initState() {
    super.initState();
    _loadDonors();
  }

  Future<void> _loadDonors() async {
    final savedDonors = await StorageService.getDonors();
    setState(() {
      donorsList.addAll(savedDonors);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = donorsList
        .where((d) => d.bloodGroup.toLowerCase().contains(search.toLowerCase()))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: const InputDecoration(
              labelText: "Search Blood Group",
              hintText: "e.g. O+, A-",
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text("No donors found for this group"))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final d = filtered[i];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.red.shade800,
                            child: Text(d.bloodGroup, style: const TextStyle(color: Colors.white)),
                          ),
                          title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(d.location),
                          trailing: IconButton(
                            icon: const Icon(Icons.phone_enabled_rounded, color: Colors.green),
                            onPressed: () {},
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
  final TextEditingController bloodController = TextEditingController();
  final TextEditingController locationController = TextEditingController();

  @override
  void dispose() {
    bloodController.dispose();
    locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Create Blood Request",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text("Fill the details below to notify nearby donors.", style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 35),
          TextField(
            controller: bloodController,
            decoration: const InputDecoration(
              labelText: "Blood Group",
              prefixIcon: Icon(Icons.bloodtype_rounded),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: locationController,
            decoration: const InputDecoration(
              labelText: "Hospital Name",
              prefixIcon: Icon(Icons.location_on_rounded),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            maxLines: 4,
            decoration: InputDecoration(
              labelText: "Message",
              alignLabelWithHint: true,
              hintText: "Why do you need blood? (Optional)",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
          const SizedBox(height: 35),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                if (bloodController.text.isNotEmpty && locationController.text.isNotEmpty) {
                  await StorageService.saveRequest({
                    'blood': bloodController.text,
                    'location': locationController.text,
                    'type': 'Request',
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Request broadcasted and saved!")),
                    );
                    bloodController.clear();
                    locationController.clear();
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please fill in blood group and location")),
                  );
                }
              },
              child: const Text("Broadcast Request"),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- PROFILE PAGE ----------------
class ProfilePage extends StatelessWidget {
  final String userName;
  const ProfilePage({super.key, required this.userName});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(25),
      children: [
        Center(
          child: Stack(
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red.shade800, width: 3),
                  image: const DecorationImage(
                    image: NetworkImage("https://ui-avatars.com/api/?name=User&background=random"),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: const Icon(Icons.edit, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              Text(userName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Text("Verified Donor", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 35),
        const _ProfileStatRow(),
        const SizedBox(height: 35),
        _buildProfileItem(context, Icons.bloodtype, "My Blood Group", "A+"),
        _buildProfileItem(context, Icons.history, "Donation History", "3 Times", onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()));
        }),
        _buildProfileItem(context, Icons.settings, "Account Settings", ""),
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
  const Donor(this.name, this.bloodGroup, this.location, this.phone);
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
          _buildEmergencyCard("Ambulance", "999", Colors.red),
          _buildEmergencyCard("Red Cross", "1199", Colors.red),
          _buildEmergencyCard("Police", "911", Colors.blue),
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

  Widget _buildEmergencyCard(String title, String phone, Color color) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, child: const Icon(Icons.phone, color: Colors.white)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(phone),
        trailing: ElevatedButton(
          onPressed: () {},
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
        future: StorageService.getHistory(),
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
                  title: Text(item['location'] ?? 'Unknown Location'),
                  subtitle: Text("${item['type']} • ${item['date']}"),
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

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nameController = TextEditingController();
  final bloodController = TextEditingController();
  final locationController = TextEditingController();
  final phoneController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    bloodController.dispose();
    locationController.dispose();
    phoneController.dispose();
    super.dispose();
  }

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
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Full Name", prefixIcon: Icon(Icons.person)),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: bloodController,
              decoration: const InputDecoration(labelText: "Blood Group (e.g. O+)", prefixIcon: Icon(Icons.bloodtype)),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(labelText: "Location/City", prefixIcon: Icon(Icons.location_city)),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: "Phone Number", prefixIcon: Icon(Icons.phone)),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isNotEmpty &&
                      bloodController.text.isNotEmpty &&
                      locationController.text.isNotEmpty &&
                      phoneController.text.isNotEmpty) {
                    final donor = Donor(
                      nameController.text.trim(),
                      bloodController.text.trim().toUpperCase(),
                      locationController.text.trim(),
                      phoneController.text.trim(),
                    );
                    await StorageService.saveDonor(donor);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Registration Successful!")),
                      );
                      Navigator.pop(context);
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please fill all fields")),
                    );
                  }
                },
                child: const Text("Register as Donor"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
