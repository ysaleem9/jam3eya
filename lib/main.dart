import 'dart:math';
import 'package:characters/characters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Firebase apps: ${Firebase.apps.length}');
  runApp(const Jam3eyaApp());
}

/* =========================
   HELPERS
========================= */

String makeInviteCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random();
  return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
}

String avatarLetter(String name) {
  final t = name.trim();
  if (t.isEmpty) return '?';
  return t.characters.first.toUpperCase();
}

/* =========================
   APP
========================= */

class Jam3eyaApp extends StatelessWidget {
  const Jam3eyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
    );
  }
}

/* =========================
   AUTH (Anonymous)
========================= */

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  User? _user;

  @override
  void initState() {
    super.initState();
    _login();
  }

  Future<void> _login() async {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  // ✅ اطبع الـ UID هون
  debugPrint('AUTH UID = ${FirebaseAuth.instance.currentUser?.uid}');

    _user = FirebaseAuth.instance.currentUser;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return HomeScreen(uid: _user!.uid);
  }
}

/* =========================
   HOME
========================= */

class HomeScreen extends StatelessWidget {
  final String uid;
  const HomeScreen({super.key, required this.uid});

  Stream<int> unreadCount() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('inbox')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((s) => s.size);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myGroups() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('myGroups')
        .orderBy('joinedAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = true;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('جمعياتي'),
          actions: [
            StreamBuilder<int>(
              stream: unreadCount(),
              builder: (_, snap) {
                final c = snap.data ?? 0;
                return IconButton(
                  icon: Stack(
                    children: [
                      const Icon(Icons.notifications),
                      if (c > 0)
                        const Positioned(
                          right: 0,
                          top: 0,
                          child: CircleAvatar(
                            radius: 4,
                            backgroundColor: Colors.red,
                          ),
                        ),
                    ],
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => InboxScreen(uid: uid)),
                    );
                  },
                );
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.add),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CreateGroupScreen(uid: uid)),
            );
          },
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => JoinByCodeScreen(uid: uid),
                    ),
                  );
                },
                child: const Text('انضم بكود'),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: myGroups(),
                builder: (_, snap) {
                  // ✅ أول شي: لو في خطأ
                  if (snap.hasError) {
                    print(Center(child: Text('READ ERROR: ${snap.error}')));

                    return Center(child: Text('READ ERROR: ${snap.error}'));
                  }

                  // ✅ ثاني شي: حالة الانتظار
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // ✅ ثالث شي: لو ما في داتا أو فاضية
                  if (!snap.hasData || snap.data!.docs.isEmpty) {
                    return const Center(child: Text('ما عندك جمعيات'));
                  }

                  // ✅ هون أكيد عندك داتا
                  final docs = snap.data!.docs;

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final groupId = d.id;

                      return FutureBuilder<
                        DocumentSnapshot<Map<String, dynamic>>
                      >(
                        future: FirebaseFirestore.instance
                            .collection('groups')
                            .doc(groupId)
                            .get(),
                        builder: (_, gSnap) {
                          if (gSnap.hasError) return const SizedBox();
                          if (!gSnap.hasData) return const SizedBox();
                          final g = gSnap.data!;
                          if (!g.exists) return const SizedBox();

                          final data = g.data()!;
                         return ListTile(
  leading: CircleAvatar(
    child: Text(avatarLetter(data['name'] ?? '')),
  ),
  title: Text(data['name'] ?? ''),
  subtitle: Text(
    'الكود: ${data['inviteCode'] ?? ''}',
  ),

  // 👇 هون الإضافة
  trailing: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      // زر النسخ
      IconButton(
        icon: const Icon(Icons.copy, size: 20),
        tooltip: 'نسخ الكود',
        onPressed: () async {
          final code = data['inviteCode'] ?? '';
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم نسخ الكود ✅')),
            );
          }
        },
      ),

      // زر المشاركة
      IconButton(
        icon: const Icon(Icons.share, size: 20),
        tooltip: 'مشاركة الكود',
        onPressed: () {
          final code = data['inviteCode'] ?? '';
          final name = data['name'] ?? '';
          Share.share(
            'كود الانضمام لجمعية "$name": $code\nافتح التطبيق ← انضم بكود',
            subject: 'كود جمعية',
          );
        },
      ),
    ],
  ),

  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupDashboardScreen(
          uid: uid,
          groupId: groupId,
          groupName: data['name'] ?? '',
          adminUid: data['adminUid'] ?? '',
        ),
      ),
    );
  },
);

                        },
                      );
                    },
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

/* =========================
   CREATE GROUP
========================= */

class CreateGroupScreen extends StatefulWidget {
  final String uid;
  const CreateGroupScreen({super.key, required this.uid});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);

    final db = FirebaseFirestore.instance;
    final groupRef = db.collection('groups').doc();
    final invite = makeInviteCode();

final batch = db.batch();

batch.set(groupRef, {
  'name': _nameCtrl.text.trim(),
  'inviteCode': invite,
  'adminUid': widget.uid,
  'createdAt': FieldValue.serverTimestamp(),
});

batch.set(groupRef.collection('members').doc(widget.uid), {
  'uid': widget.uid,
  'role': 'admin',
  'joinedAt': FieldValue.serverTimestamp(),
});

// إذا مطبقين حل myGroups (الحل الثاني)
batch.set(
  db.collection('users').doc(widget.uid).collection('myGroups').doc(groupRef.id),
  {
    'groupId': groupRef.id,
    'groupName': _nameCtrl.text.trim(),
    'inviteCode': invite,
    'adminUid': widget.uid,
    'role': 'admin',
    'joinedAt': FieldValue.serverTimestamp(),
  },
);
debugPrint('CREATE uid=${FirebaseAuth.instance.currentUser?.uid}');
final u = FirebaseAuth.instance.currentUser;
if (u == null) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('لسه ما تم تسجيل الدخول، جرّب مرة ثانية')),
  );
  return;
}
await batch.commit();


    setState(() => _saving = false);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء جمعية')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم الجمعية',
                border: OutlineInputBorder(),
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _saving ? null : _create,
              child: _saving
                  ? const CircularProgressIndicator()
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

/* =========================
   JOIN BY CODE (PENDING)
========================= */

class JoinByCodeScreen extends StatefulWidget {
  final String uid;
  const JoinByCodeScreen({super.key, required this.uid});

  @override
  State<JoinByCodeScreen> createState() => _JoinByCodeScreenState();
}

class _JoinByCodeScreenState extends State<JoinByCodeScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() => _loading = true);

    final db = FirebaseFirestore.instance;

    try {
      // 1) Find group by invite code
      final q = await db
          .collection('groups')
          .where('inviteCode', isEqualTo: code)
          .limit(1)
          .get();

      if (q.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('كود غير صحيح')));
        }
        return;
      }

      final groupDoc = q.docs.first;
      final groupId = groupDoc.id;

      final data = groupDoc.data();
      final String groupName = (data['name'] ?? '') as String;
      final String adminUid = (data['adminUid'] ?? '') as String;

      if (adminUid.isEmpty || groupName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('بيانات المجموعة ناقصة')),
          );
        }
        return;
      }

      // 2) Create / update join request
      await db
          .collection('groups')
          .doc(groupId)
          .collection('joinRequests')
          .doc(widget.uid)
          .set({
            'uid': widget.uid,
            'status': 'pending',
            'requestedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // 3) Inbox notification for the requester (you)
      await db.collection('users').doc(widget.uid).collection('inbox').add({
        'titleAr': 'طلبك قيد المراجعة',
        'bodyAr': 'طلب الانضمام إلى $groupName قيد المراجعة',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'join_request_pending',
        'groupId': groupId,
      });

      // 4) Inbox notification for the admin
      await db.collection('users').doc(adminUid).collection('inbox').add({
  'type': 'join_request_new',
  'groupId': groupId,
  'titleAr': 'طلب انضمام جديد',
  'bodyAr': 'مستخدم جديد طلب ينضم إلى جمعية: $groupName',
  'read': false,
  'createdAt': FieldValue.serverTimestamp(),
});


      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم إرسال الطلب ✅')));
        Navigator.pop(context);
      }
    } on FirebaseException catch (e) {
      debugPrint('JOIN ERROR code=${e.code} msg=${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Firestore: ${e.code}')));
      }
    } catch (e) {
      debugPrint('JOIN UNKNOWN ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('انضم بكود')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: 'كود الدعوة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _join,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('إرسال الطلب'),
            ),
          ],
        ),
      ),
    );
  }
}

/* =========================
   GROUP DASHBOARD
========================= */

class GroupDashboardScreen extends StatelessWidget {
  final String uid;
  final String groupId;
  final String groupName;
  final String adminUid;

  const GroupDashboardScreen({
    super.key,
    required this.uid,
    required this.groupId,
    required this.groupName,
    required this.adminUid,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = uid == adminUid;

    return Scaffold(
      appBar: AppBar(title: Text(groupName)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isAdmin
            ? FilledButton(
                child: const Text('طلبات الانضمام'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminRequestsScreen(
                        groupId: groupId,
                        groupName: groupName,
                        adminUid: uid,
                      ),
                    ),
                  );
                },
              )
            : const Text('بانتظار موافقة الأدمن'),
      ),
    );
  }
}

/* =========================
   ADMIN REQUESTS
========================= */

class AdminRequestsScreen extends StatelessWidget {
  final String groupId;
  final String groupName;
  final String adminUid;

  const AdminRequestsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.adminUid,
  });

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('طلبات الانضمام')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db
            .collection('groups')
            .doc(groupId)
            .collection('joinRequests')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.data!.docs.isEmpty) {
            return const Center(child: Text('لا يوجد طلبات'));
          }

          return ListView(
            children: snap.data!.docs.map((d) {
              return ListTile(
                title: Text(d.id),
                trailing: IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: () async {
                    await db
                        .collection('groups')
                        .doc(groupId)
                        .collection('members')
                        .doc(d.id)
                        .set({
                          'uid': d.id,
                          'role': 'member',
                          'joinedAt': FieldValue.serverTimestamp(),
                        });

                    await d.reference.update({'status': 'approved'});

                    await db
                        .collection('users')
                        .doc(d.id)
                        .collection('inbox')
                        .add({
                          'titleAr': 'تم قبولك',
                          'bodyAr': 'تمت إضافتك إلى $groupName',
                          'read': false,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                    await db
                        .collection('users')
                        .doc(d.id)
                        .collection('myGroups')
                        .doc(groupId)
                        .set({
                          'role': 'member',
                          'joinedAt': FieldValue.serverTimestamp(),
                        });

                        
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

/* =========================
   INBOX
========================= */

class InboxScreen extends StatelessWidget {
  final String uid;
  const InboxScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('inbox')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.data!.docs.isEmpty) {
            return const Center(child: Text('ما في إشعارات'));
          }

          return ListView(
            children: snap.data!.docs.map((d) {
              final data = d.data();
              return ListTile(
                title: Text(data['titleAr'] ?? ''),
                subtitle: Text(data['bodyAr'] ?? ''),
                onTap: () async {
                  d.reference.update({'read': true});
                  final n = d.data(); // Map<String, dynamic>

  // 1) علّم الإشعار مقروء
  await d.reference.update({'read': true});

  final type = (n['type'] ?? '') as String;
  final groupId = (n['groupId'] ?? '') as String;

  if (type == 'join_request_new' && groupId.isNotEmpty) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminRequestsScreen(
          groupId: groupId,
          groupName: (data['name'] ?? '') as String,
        adminUid: (data['adminUid'] ?? '') as String,

        ),
      ),
    );
    return;}
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
