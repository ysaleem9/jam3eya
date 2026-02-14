import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MembersScreen extends StatelessWidget {
  final String groupId;
  final String groupName;
  final String adminUid;
  final String currentUid;

  const MembersScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.adminUid,
    required this.currentUid,
  });

  bool get isAdmin => currentUid == adminUid;
  String avatarLetter(String s) {
    final t = s.trim();
    if (t.isEmpty) return '?';
    return t.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text('أعضاء $groupName')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('groups')
              .doc(groupId)
              .collection('members')
              .orderBy('joinedAt', descending: true)
              .snapshots(),
          builder: (_, snap) {
            if (snap.hasError) {
              return Center(child: Text('ERROR: ${snap.error}'));
            }
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              return const Center(child: Text('لا يوجد أعضاء'));
            }

            final members = snap.data!.docs;

            return ListView.separated(
              itemCount: members.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final mDoc = members[i];
                final m = mDoc.data();
                final memberUid = (m['uid'] ?? mDoc.id) as String;
                final role = (m['role'] ?? 'member') as String;

                return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: db.collection('users').doc(memberUid).get(),
                  builder: (_, uSnap) {
                    String name = memberUid;
                    String email = '';
                    if (uSnap.hasData && uSnap.data!.exists) {
                      final u = uSnap.data!.data()!;
                      name = (u['displayName'] ?? memberUid) as String;
                      email = (u['email'] ?? '') as String;
                    }

                    final canRemove = isAdmin && memberUid != adminUid;

                    return ListTile(
                      leading: CircleAvatar(child: Text(avatarLetter(name))),
                      title: Text(name),
                      subtitle: Text(
                        email.isEmpty
                            ? 'الدور: $role'
                            : '$email • الدور: $role',
                      ),
                      trailing: canRemove
                          ? IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('حذف عضو'),
                                    content: Text(
                                      'متأكد بدك تحذف "$name" من الجمعية؟',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('إلغاء'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('حذف'),
                                      ),
                                    ],
                                  ),
                                );

                                if (ok != true) return;

                                // 1) احذف العضوية من المجموعة
                                await db
                                    .collection('groups')
                                    .doc(groupId)
                                    .collection('members')
                                    .doc(memberUid)
                                    .delete();

                                await FirebaseFirestore.instance
                                    .collection('groups')
                                    .doc(groupId)
                                    .update({
                                      'memberOrder': FieldValue.arrayRemove([
                                        memberUid,
                                      ]),
                                    });

                                // 2) احذف من myGroups عند العضو (عشان تختفي عنده)
                                await db
                                    .collection('users')
                                    .doc(memberUid)
                                    .collection('myGroups')
                                    .doc(groupId)
                                    .delete();

                                // 3) إشعار داخلي للعضو (اختياري)
                                await db
                                    .collection('users')
                                    .doc(memberUid)
                                    .collection('inbox')
                                    .add({
                                      'titleAr': 'تمت إزالتك',
                                      'bodyAr':
                                          'تمت إزالتك من جمعية: $groupName',
                                      'read': false,
                                      'createdAt': FieldValue.serverTimestamp(),
                                      'type': 'member_removed',
                                      'groupId': groupId,
                                    });

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('تم حذف العضو'),
                                    ),
                                  );
                                }
                              },
                            )
                          : (role == 'admin'
                                ? const Icon(Icons.verified, size: 20)
                                : null),
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
