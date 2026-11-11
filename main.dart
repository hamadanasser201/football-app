import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase init: $e");
  }
  runApp(const MasterFootballApp());
}

class MasterFootballApp extends StatelessWidget {
  const MasterFootballApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'منصة الذكاء الاصطناعي الرياضية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.tealAccent,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: const ColorScheme.dark(primary: Colors.tealAccent),
      ),
      home: const AuthGate(),
    );
  }
}

// ---------------- بوابة التحقق وتوجيه المستخدم ----------------
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LoginRegisterScreen();

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(snapshot.data!.uid).get(),
          builder: (context, userSnap) {
            if (!userSnap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            
            final data = userSnap.data!.data() as Map<String, dynamic>?;
            if (data == null) return const LoginRegisterScreen();
            
            if (data['isBanned'] == true) {
              return const Scaffold(
                body: Center(child: Text('تم حظر هذا الحساب من استخدام التطبيق بأمر الإدارة', style: TextStyle(color: Colors.red, fontSize: 16))),
              );
            }
            if (data['isApproved'] == false) {
              return const Scaffold(
                body: Center(child: Text('حسابك قيد المراجعة والموافقة من قِبل الأدمن', style: TextStyle(color: Colors.orange, fontSize: 16))),
              );
            }

            return HomeScreen(userData: data, uid: snapshot.data!.uid);
          },
        );
      },
    );
  }
}

// ---------------- شاشة تسجيل الدخول والتسجيل مع شرط السن (+18) ----------------
class LoginRegisterScreen extends StatefulWidget {
  const LoginRegisterScreen({super.key});

  @override
  State<LoginRegisterScreen> createState() => _LoginRegisterScreenState();
}

class _LoginRegisterScreenState extends State<LoginRegisterScreen> {
  bool isLogin = true;
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  DateTime? birthDate;
  String gender = 'ذكر';
  bool loading = false;

  void submit() async {
    setState(() => loading = true);
    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailCtrl.text.trim(),
          password: passCtrl.text.trim(),
        );
      } else {
        if (nameCtrl.text.trim().isEmpty) throw 'يرجى كتابة الاسم';
        if (birthDate == null) throw 'يرجى تحديد تاريخ الميلاد';
        
        final age = DateTime.now().difference(birthDate!).inDays ~/ 365;
        if (age < 18) throw 'عذراً، يجب أن يكون عمرك 18 عاماً فما فوق للانضمام للتطبيق.';

        UserCredential creds = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailCtrl.text.trim(),
          password: passCtrl.text.trim(),
        );

        await FirebaseFirestore.instance.collection('users').doc(creds.user!.uid).set({
          'uid': creds.user!.uid,
          'email': emailCtrl.text.trim(),
          'name': nameCtrl.text.trim(),
          'gender': gender,
          'age': age,
          'role': 'user',
          'isApproved': true,
          'isBanned': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.sports_soccer, size: 70, color: Colors.tealAccent),
              const SizedBox(height: 15),
              Text(
                isLogin ? 'تسجيل الدخول' : 'إنشاء حساب جديد (+18)',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.tealAccent),
              ),
              const SizedBox(height: 25),
              if (!isLogin) ...[
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'الاسم الكامل', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: gender,
                  decoration: const InputDecoration(labelText: 'الجنس', border: OutlineInputBorder()),
                  items: ['ذكر', 'أنثى'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setState(() => gender = v!),
                ),
                const SizedBox(height: 12),
                ListTile(
                  tileColor: Colors.grey[900],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  title: Text(birthDate == null ? 'اضغط لتحديد تاريخ الميلاد' : DateFormat('yyyy-MM-dd').format(birthDate!)),
                  trailing: const Icon(Icons.calendar_month, color: Colors.tealAccent),
                  onTap: () async {
                    DateTime? d = await showDatePicker(
                      context: context,
                      initialDate: DateTime(2005),
                      firstDate: DateTime(1940),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => birthDate = d);
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'البريد الإلكتروني', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: loading ? null : submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: loading ? const CircularProgressIndicator(color: Colors.black) : Text(isLogin ? 'تسجيل الدخول' : 'إنشاء الحساب', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () => setState(() => isLogin = !isLogin),
                child: Text(isLogin ? 'ليس لديك حساب؟ أنشئ حساباً جديداً' : 'لديك حساب بالفعل؟ سجل دخولك'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- الشاشة الرئيسية ----------------
class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String uid;
  const HomeScreen({super.key, required this.userData, required this.uid});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    bool isAdmin = widget.userData['role'] == 'admin';

    final screens = [
      const PredictorView(),
      const PublicChatView(),
      AdminOrFriendsView(isAdmin: isAdmin, uid: widget.uid),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Football AI Predictor'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: screens[_tab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        selectedItemColor: Colors.tealAccent,
        unselectedItemColor: Colors.grey,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'التحليل'),
          const BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'الشات العام'),
          BottomNavigationBarItem(
            icon: Icon(isAdmin ? Icons.admin_panel_settings : Icons.people),
            label: isAdmin ? 'لوحة الأدمن' : 'المشتركون',
          ),
        ],
      ),
    );
  }
}

// ---------------- واجهة التحليل الدقيق بالذكاء الاصطناعي ----------------
class PredictorView extends StatefulWidget {
  const PredictorView({super.key});

  @override
  State<PredictorView> createState() => _PredictorViewState();
}

class _PredictorViewState extends State<PredictorView> {
  final teamACtrl = TextEditingController();
  final teamBCtrl = TextEditingController();
  File? imgA;
  File? imgB;
  bool loading = false;
  String result = '';
  final picker = ImagePicker();

  // ضع هنا مفتاح Gemini API
  final String geminiApiKey = "AQ.Ab8RN6KVthQdYplODscPT_KZpCq9m5upk9WJyE_s5DkbnHrjmQ";

  Future<void> pickImg(bool isA) async {
    final x = await picker.pickImage(source: ImageSource.gallery);
    if (x != null) setState(() => isA ? imgA = File(x.path) : imgB = File(x.path));
  }

  void executeAnalysis() async {
    if (imgA == null && teamACtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدد صورة أو اسم الفريق الأول')));
      return;
    }
    if (imgB == null && teamBCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدد صورة أو اسم الفريق الثاني')));
      return;
    }

    setState(() {
      loading = true;
      result = '';
    });

    try {
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: geminiApiKey);
      final prompt = TextPart('''
أنت محلل بيانات رياضية وخبير إحصائي ومحاكي مباريات دولي (Football Data Analyst & Match Simulator).
المطلوب إجراء تحليل تقييمي دقيق وصارم يستند إلى مقياس نقطي واضح يؤكد ويثبت النسبة المئوية النهائية لفوز أحد الفريقين.

خطوات التحليل الإلزامية:
1. التعرف على الفريقين بدقة من الصور المرفقة أو الأسماء المكتوبة.
2. تقييم الزخم والنتائج الحالية (Recent Form - الوزن: 30%):
   - فحص نتائج آخر 5 إلى 8 مباريات خاضها كل فريق ضد الفرق الأخرى قبل هذه المواجهة مباشرة (سلسلة الانتصارات، التعادلات، الهزائم، ومعدل تسجيل واستقبال الأهداف).
3. تقييم المواجهات المباشرة التاريخية (Head-to-Head - الوزن: 25%):
   - تحليل اللقاءات السابقة بين الفريقين معاً وتفوق طرف على الآخر نفسياً وتكتيكياً.
4. تقييم كفاءة الخطوط الحالية (Squad Strength & Lines - الوزن: 30%):
   - مقارنة مباشرة وجهاً لوجه بين:
     * خط الهجوم (الفريق أ) ضد خط دفاع وحارس (الفريق ب).
     * معركة خط الوسط والسيطرة على الكرة بين الفريقين.
     * خط الهجوم (الفريق ب) ضد خط دفاع وحارس (الفريق أ).
     * تأثير أبرز النجوم والغيابات المؤثرة الحالية.
5. العوامل الظرفية والتكتيكية (Tactical & Situational - الوزن: 15%):
   - أسلوب اللعب، الاستقرار الفني، والمعدل البدني.

شكل المخرجات المطلوبة في التقرير:
- جدول أو قائمة رقمية توضح نقاط كل فريق في كل معيار من المعايير أعلاه.
- النتيجة الرقمية المئوية النهائية بدقة:
  * نسبة فوز الفريق الأول: [ % ]
  * نسبة فوز الفريق الثاني: [ % ]
  * نسبة التعادل: [ % ]
- الخلاصة التحليلية الحاسمة: توضيح المعيار الإحصائي الفاصل الذي رجّح كفة الفريق صاحب النسبة الأعلى وتأكيد سبب تفوقه بلغة رياضية دقيقة ورصينة.
''');

      List<Part> parts = [prompt];
      if (teamACtrl.text.isNotEmpty) parts.add(TextPart("الفريق الأول: ${teamACtrl.text.trim()}"));
      if (teamBCtrl.text.isNotEmpty) parts.add(TextPart("الفريق الثاني: ${teamBCtrl.text.trim()}"));
      if (imgA != null) parts.add(DataPart('image/jpeg', await imgA!.readAsBytes()));
      if (imgB != null) parts.add(DataPart('image/jpeg', await imgB!.readAsBytes()));

      final res = await model.generateContent([Content.multi(parts)]);
      setState(() => result = res.text ?? 'لم يتم استخراج نتيجة.');
    } catch (e) {
      setState(() => result = 'خطأ أثناء المعالجة: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text('الفريق الأول', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => pickImg(true),
                      child: Container(
                        height: 100,
                        width: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          border: Border.all(color: Colors.tealAccent.withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: imgA != null
                            ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(imgA!, fit: BoxFit.cover))
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [Icon(Icons.add_photo_alternate, color: Colors.tealAccent), Text('الشعار', style: TextStyle(fontSize: 11))],
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(controller: teamACtrl, textAlign: TextAlign.center, decoration: const InputDecoration(hintText: 'أو الاسم كتابةً', isDense: true)),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('VS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.redAccent)),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Text('الفريق الثاني', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => pickImg(false),
                      child: Container(
                        height: 100,
                        width: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          border: Border.all(color: Colors.tealAccent.withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: imgB != null
                            ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(imgB!, fit: BoxFit.cover))
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [Icon(Icons.add_photo_alternate, color: Colors.tealAccent), Text('الشعار', style: TextStyle(fontSize: 11))],
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(controller: teamBCtrl, textAlign: TextAlign.center, decoration: const InputDecoration(hintText: 'أو الاسم كتابةً', isDense: true)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),
          ElevatedButton(
            onPressed: loading ? null : executeAnalysis,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: loading ? const CircularProgressIndicator(color: Colors.black) : const Text('بدء التحليل الرياضي الشامل', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 20),
          if (result.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
              ),
              child: Text(result, textDirection: TextDirection.rtl, style: const TextStyle(fontSize: 14, height: 1.6)),
            ),
        ],
      ),
    );
  }
}

// ---------------- غرف الشات العام ----------------
class PublicChatView extends StatefulWidget {
  const PublicChatView({super.key});

  @override
  State<PublicChatView> createState() => _PublicChatViewState();
}

class _PublicChatViewState extends State<PublicChatView> {
  final msgCtrl = TextEditingController();

  void sendMsg() {
    if (msgCtrl.text.trim().isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseFirestore.instance.collection('public_chat').add({
      'senderId': user.uid,
      'senderEmail': user.email,
      'text': msgCtrl.text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    });
    msgCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('public_chat').orderBy('timestamp', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              return ListView.builder(
                reverse: true,
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  return ListTile(
                    title: Text(d['senderEmail'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.tealAccent)),
                    subtitle: Text(d['text'] ?? ''),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: msgCtrl,
                  decoration: const InputDecoration(hintText: 'اكتب رسالة في الشات العام...', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(icon: const Icon(Icons.send, color: Colors.tealAccent), onPressed: sendMsg),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- لوحة تحكم الأدمن وقائمة المشتركين ----------------
class AdminOrFriendsView extends StatelessWidget {
  final bool isAdmin;
  final String uid;
  const AdminOrFriendsView({super.key, required this.isAdmin, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final users = snapshot.data!.docs.where((d) => d.id != uid).toList();

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, i) {
            final userDoc = users[i];
            final u = userDoc.data() as Map<String, dynamic>;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.tealAccent,
                child: Text(u['gender'] == 'ذكر' ? '♂' : '♀', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
              title: Text("${u['name'] ?? 'مستخدم'} (${u['age'] ?? 18} سنة)"),
              subtitle: Text(u['email'] ?? ''),
              trailing: isAdmin
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(u['isBanned'] == true ? Icons.lock_open : Icons.block, color: u['isBanned'] == true ? Colors.green : Colors.red),
                          onPressed: () {
                            FirebaseFirestore.instance.collection('users').doc(userDoc.id).update({
                              'isBanned': !(u['isBanned'] ?? false),
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_forever, color: Colors.grey),
                          onPressed: () {
                            FirebaseFirestore.instance.collection('users').doc(userDoc.id).delete();
                          },
                        ),
                      ],
                    )
                  : IconButton(
                      icon: const Icon(Icons.chat, color: Colors.tealAccent),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PrivateChatRoom(targetUserId: userDoc.id, targetName: u['name'] ?? 'مستخدم'),
                          ),
                        );
                      },
                    ),
            );
          },
        );
      },
    );
  }
}

// ---------------- غرفة الشات الخاص ----------------
class PrivateChatRoom extends StatelessWidget {
  final String targetUserId;
  final String targetName;
  const PrivateChatRoom({super.key, required this.targetUserId, required this.targetName});

  String getChatId(String a, String b) => a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final chatId = getChatId(currentUid, targetUserId);
    final msgCtrl = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: Text('محادثة خاصة: $targetName')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('private_chats')
                  .doc(chatId)
                  .collection('messages')
                  .orderBy('time', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final msgs = snap.data!.docs;
                return ListView.builder(
                  reverse: true,
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i].data() as Map<String, dynamic>;
                    bool isMe = m['sender'] == currentUid;
                    return Container(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.teal[800] : Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(m['msg'] ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: msgCtrl,
                    decoration: const InputDecoration(hintText: 'اكتب رسالة خاصة...', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.tealAccent),
                  onPressed: () {
                    if (msgCtrl.text.trim().isEmpty) return;
                    FirebaseFirestore.instance.collection('private_chats').doc(chatId).collection('messages').add({
                      'sender': currentUid,
                      'msg': msgCtrl.text.trim(),
                      'time': FieldValue.serverTimestamp(),
                    });
                    msgCtrl.clear();
                  },
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
