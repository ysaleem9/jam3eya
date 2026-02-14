import 'dart:math';
import 'package:characters/characters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jam3eya/MembersScreen.dart';
import 'firebase_options.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'LoginScreen.dart';

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

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snap.data;
        if (user == null) {
          return const LoginScreen();
        }

        return HomeScreen(uid: user.uid);
      },
    );
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
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
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
                                    await Clipboard.setData(
                                      ClipboardData(text: code),
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('تم نسخ الكود ✅'),
                                        ),
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
  final _amountCtrl = TextEditingController(
    text: '200',
  ); // الدفعة الشهرية لكل عضو
  int _payDay = 5; // يوم الدفع (1..28)
  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
    _amountCtrl.dispose();
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);

    final db = FirebaseFirestore.instance;
    final groupRef = db.collection('groups').doc();
    final invite = makeInviteCode();
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final startMonth = '${now.year}-$m';
    final batch = db.batch();

    batch.set(groupRef, {
      'name': _nameCtrl.text.trim(),
      'inviteCode': invite,
      'adminUid': widget.uid,
      'amountPerMember': int.tryParse(_amountCtrl.text.trim()) ?? 0,
      'payDay': _payDay,
      'startMonth': startMonth,
      'memberOrder': [widget.uid], // الأدمن أول واحد مبدئيًا
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.set(groupRef.collection('members').doc(widget.uid), {
      'uid': widget.uid,
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
    });

    // إذا مطبقين حل myGroups (الحل الثاني)
    batch.set(
      db
          .collection('users')
          .doc(widget.uid)
          .collection('myGroups')
          .doc(groupRef.id),
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
            const SizedBox(height: 12),

            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'الدفعة الشهرية لكل عضو',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            DropdownButtonFormField<int>(
              value: _payDay,
              items: List.generate(28, (i) => i + 1)
                  .map((d) => DropdownMenuItem(value: d, child: Text('يوم $d')))
                  .toList(),
              onChanged: (v) => setState(() => _payDay = v ?? 5),
              decoration: const InputDecoration(
                labelText: 'يوم الدفع الشهري',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            Builder(
              builder: (_) {
                final amount = int.tryParse(_amountCtrl.text.trim()) ?? 0;
                // final membersCount =
                //     _members.length; // إذا عندك قائمة أعضاء محلية
                // final pot = amount * membersCount;
                // final months = membersCount;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Text('عدد الأعضاء الحالي: $membersCount'),
                        // Text('صندوق الشهر: $pot'),
                        // Text('عدد الشهور للدورة: $months'),
                      ],
                    ),
                  ),
                );
              },
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
      final me = await db.collection('users').doc(widget.uid).get();
      final myName = (me.data()?['displayName'] ?? 'بدون اسم') as String;

      // 2) Create / update join request
      await db
          .collection('groups')
          .doc(groupId)
          .collection('joinRequests')
          .doc(widget.uid)
          .set({
            'uid': widget.uid,
            'displayName': myName,
            'status': 'pending',
            'requestedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // 3) Inbox notification for the requester (you)
      await db.collection('users').doc(widget.uid).collection('inbox').add({
        'titleAr': 'طلب الانضمام للجمعية :$groupName قيد المراجعة',
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
        'requesterUid': widget.uid,
        'requesterName': myName,
        'titleAr': 'طلب انضمام جديد',
        'bodyAr': '$myName طلب ينضم إلى جمعية: $groupId',
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
    final me = await db.collection('users').doc(widget.uid).get();
    final myName = (me.data()?['displayName'] ?? 'بدون اسم') as String;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ====== كرت الحساب ======
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('groups')
                  .doc(groupId)
                  .snapshots(),
              builder: (_, gSnap) {
                if (!gSnap.hasData) {
                  return const SizedBox();
                }

                final g = gSnap.data!;
                if (!g.exists) return const SizedBox();

                final data = g.data()!;
                final amountPerMember = (data['amountPerMember'] ?? 0) as int;
                final payDay = (data['payDay'] ?? 5) as int;

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('groups')
                      .doc(groupId)
                      .collection('members')
                      .snapshots(),
                  builder: (_, mSnap) {
                    if (!mSnap.hasData) {
                      return const SizedBox();
                    }

                    final membersCount = mSnap.data!.docs.length;
                    final pot = amountPerMember * membersCount;
                    final months = membersCount;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('الدفعة الشهرية لكل عضو: $amountPerMember'),
                            Text('يوم الدفع الشهري: $payDay'),
                            const SizedBox(height: 8),
                            Text('عدد الأعضاء: $membersCount'),
                            Text('صندوق الشهر: $pot'),
                            Text('عدد الشهور للدورة: $months'),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 16),

            // ====== زر الأعضاء ======
            isAdmin
                ? FilledButton(
                    child: const Text('الأعضاء'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MembersScreen(
                            groupId: groupId,
                            groupName: groupName,
                            adminUid: adminUid,
                            currentUid: uid,
                          ),
                        ),
                      );
                    },
                  )
                : const Text('الأعضاء'),

            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScheduleScreen(
                      groupId: groupId,
                      groupName: groupName,
                      currentUid: uid,
                      adminUid: adminUid,
                    ),
                  ),
                );
              },
              child: const Text('جدول الاستلام'),
            ),
          ],
        ),
      ),
    );
  }
}

class ScheduleScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String currentUid;
  final String adminUid;

  const ScheduleScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.currentUid,
    required this.adminUid,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  bool get isAdmin => widget.currentUid == widget.adminUid;

  DateTime _parseMonth(String ym) {
    final parts = ym.split('-');
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    return DateTime(y, m, 1);
  }

  DateTime _addMonths(DateTime d, int months) {
    return DateTime(d.year, d.month + months, 1);
  }

  String _fmtYM(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    return '${d.year}-$m';
  }

  Future<void> _saveOrder(List<String> newOrder) async {
    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .update({'memberOrder': newOrder});

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ ترتيب الاستلام ✅')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text('جدول الاستلام - ${widget.groupName}')),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db.collection('groups').doc(widget.groupId).snapshots(),
          builder: (_, gSnap) {
            if (gSnap.hasError) {
              return Center(child: Text('ERROR: ${gSnap.error}'));
            }
            if (!gSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final g = gSnap.data!;
            if (!g.exists) {
              return const Center(child: Text('الجمعية غير موجودة'));
            }

            final data = g.data()!;
            final payDay = (data['payDay'] ?? 5) as int;
            final startMonthStr = (data['startMonth'] ?? '') as String;
            final order = (data['memberOrder'] ?? []) as List<dynamic>;
            final memberOrder = order.map((e) => e.toString()).toList();

            if (startMonthStr.isEmpty) {
              return const Center(child: Text('startMonth غير موجود'));
            }
            if (memberOrder.isEmpty) {
              return const Center(child: Text('لا يوجد أعضاء في الدور'));
            }

            final startMonth = _parseMonth(startMonthStr);
            final d = payDay.clamp(1, 28);

            // نجمع بيانات المستخدمين لأسماءهم
            return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: db.collection('users').get(),
              builder: (_, uSnap) {
                final nameByUid = <String, String>{};
                final emailByUid = <String, String>{};

                if (uSnap.hasData) {
                  for (final doc in uSnap.data!.docs) {
                    final u = doc.data();
                    nameByUid[doc.id] = (u['displayName'] ?? doc.id).toString();
                    emailByUid[doc.id] = (u['email'] ?? '').toString();
                  }
                }

                // ✅ للأدمن: ترتيب بالسحب
                if (isAdmin) {
                  return ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: memberOrder.length,
                    buildDefaultDragHandles: false, // ✅ مهم
                    onReorder: (oldIndex, newIndex) async {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = memberOrder.removeAt(oldIndex);
                        memberOrder.insert(newIndex, item);
                      });
                      await _saveOrder(memberOrder);
                    },
                    itemBuilder: (_, i) {
                      final uid = memberOrder[i];

                      final monthDate = _addMonths(startMonth, i);
                      final ym = _fmtYM(monthDate);

                      final receiverName = nameByUid[uid] ?? uid;
                      final receiverEmail = emailByUid[uid] ?? '';

                      return ListTile(
                        key: ValueKey('member-$uid'), // ✅ key واضح
                        leading: CircleAvatar(
                          child: Text(avatarLetter(receiverName)),
                        ),
                        title: Text('$ym • يوم الدفع $d'),
                        subtitle: Text(
                          receiverEmail.isEmpty
                              ? 'المستلم: $receiverName'
                              : 'المستلم: $receiverName • $receiverEmail',
                        ),
                        // ✅ هذي اللي تخليك تسحب من الأيقونة
                        trailing: ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_handle),
                        ),
                      );
                    },
                  );
                }

                // ✅ لغير الأدمن: عرض فقط
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: memberOrder.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final uid = memberOrder[i];

                    final monthDate = _addMonths(startMonth, i);
                    final ym = _fmtYM(monthDate);

                    final receiverName = nameByUid[uid] ?? uid;
                    final receiverEmail = emailByUid[uid] ?? '';

                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(avatarLetter(receiverName)),
                      ),
                      title: Text('$ym • يوم الدفع $d'),
                      subtitle: Text(
                        receiverEmail.isEmpty
                            ? 'المستلم: $receiverName'
                            : 'المستلم: $receiverName • $receiverEmail',
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () async {
                        final db = FirebaseFirestore.instance;
                        final userId = d.id;

                        // 1) حدّث الطلب مرفوض (أو احذفه)
                        await d.reference.update({'status': 'rejected'});

                        // 2) إشعار داخلي لليوزر
                        await db
                            .collection('users')
                            .doc(userId)
                            .collection('inbox')
                            .add({
                              'titleAr': 'تم رفض الطلب',
                              'bodyAr': 'تم رفض طلب انضمامك إلى $groupName',
                              'read': false,
                              'createdAt': FieldValue.serverTimestamp(),
                              'type': 'join_rejected',
                              'groupId': groupId,
                            });

                        // (اختياري) احذف الطلب بعد الرفض بدل ما يضل بالسجل:
                        // await d.reference.delete();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: () async {
                        final db = FirebaseFirestore.instance;
                        final userId = d.id;

                        // 1) أضف العضو
                        await db
                            .collection('groups')
                            .doc(groupId)
                            .collection('members')
                            .doc(userId)
                            .set({
                              'uid': userId,
                              'role': 'member',
                              'joinedAt': FieldValue.serverTimestamp(),
                            });
                        await FirebaseFirestore.instance
                            .collection('groups')
                            .doc(groupId)
                            .update({
                              'memberOrder': FieldValue.arrayUnion([
                                userId,
                              ]), // يضيفه آخر القائمة (بدون تكرار)
                            });

                        // 2) حدّث الطلب approved
                        await d.reference.update({'status': 'approved'});

                        // 3) جيب inviteCode
                        final gDoc = await db
                            .collection('groups')
                            .doc(groupId)
                            .get();
                        final gData = gDoc.data() as Map<String, dynamic>;
                        final inviteCode =
                            (gData['inviteCode'] ?? '') as String;

                        // 4) اكتب myGroups للعضو
                        await db
                            .collection('users')
                            .doc(userId)
                            .collection('myGroups')
                            .doc(groupId)
                            .set({
                              'groupId': groupId,
                              'groupName': groupName,
                              'inviteCode': inviteCode,
                              'adminUid': adminUid,
                              'role': 'member',
                              'joinedAt': FieldValue.serverTimestamp(),
                            });

                        // 5) إشعار قبول
                        await db
                            .collection('users')
                            .doc(userId)
                            .collection('inbox')
                            .add({
                              'titleAr': 'تم قبولك',
                              'bodyAr': 'تمت إضافتك إلى $groupName',
                              'read': false,
                              'createdAt': FieldValue.serverTimestamp(),
                              'type': 'join_approved',
                              'groupId': groupId,
                            });
                      },
                    ),
                  ],
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
                  final n = d.data(); // Map<String, dynamic>
                  final type = (n['type'] ?? '') as String;
                  final groupId = (n['groupId'] ?? '') as String;

                  // علّم الإشعار مقروء (مرة واحدة)
                  await d.reference.update({'read': true});

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

                    return;
                  }
                  if (type == 'join_approved' && groupId.isNotEmpty) {
                    final g = await FirebaseFirestore.instance
                        .collection('groups')
                        .doc(groupId)
                        .get();
                    final gd = g.data() ?? {};

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupDashboardScreen(
                          uid: uid,
                          groupId: groupId,
                          groupName: (gd['name'] ?? '') as String,
                          adminUid: (gd['adminUid'] ?? '') as String,
                        ),
                      ),
                    );
                    return;
                  }

                  // ✅ إذا تم رفض الطلب: بس اعرض رسالة
                  if (type == 'join_rejected') {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم رفض طلب الانضمام')),
                      );
                    }
                    return;
                  }

                  // (اختياري) أنواع ثانية لاحقًا...
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
