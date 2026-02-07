import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminRequestsScreen extends StatefulWidget {
  final String groupId;
  const AdminRequestsScreen({super.key, required this.groupId});

  @override
  State<AdminRequestsScreen> createState() => _AdminRequestsScreenState();
}

class _AdminRequestsScreenState extends State<AdminRequestsScreen> {
  final _busy = <String, bool>{}; // requesterUid -> busy

  Future<Map<String, dynamic>> _getGroup() async {
    final doc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .get();
    return doc.data() ?? {};
  }

  Future<void> _approve(String requesterUid) async {
    setState(() => _busy[requesterUid] = true);

    final db = FirebaseFirestore.instance;

    try {
      final g = await _getGroup();
      final groupName = (g['name'] ?? '') as String;
      final adminUid = (g['adminUid'] ?? '') as String;
      final inviteCode = (g['inviteCode'] ?? '') as String;

      final memberRef = db
          .collection('groups')
          .doc(widget.groupId)
          .collection('members')
          .doc(requesterUid);

      final reqRef = db
          .collection('groups')
          .doc(widget.groupId)
          .collection('joinRequests')
          .doc(requesterUid);

      final myGroupRef = db
          .collection('users')
          .doc(requesterUid)
          .collection('myGroups')
          .doc(widget.groupId);

      final inboxRef = db
          .collection('users')
          .doc(requesterUid)
          .collection('inbox')
          .doc();

      final batch = db.batch();

      // add member
      batch.set(memberRef, {
        'uid': requesterUid,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      // add to myGroups so it appears on their app
      batch.set(myGroupRef, {
        'groupId': widget.groupId,
        'groupName': groupName,
        'inviteCode': inviteCode,
        'adminUid': adminUid,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      // delete request
      batch.delete(reqRef);

      // notify requester
      batch.set(inboxRef, {
        'type': 'join_approved',
        'groupId': widget.groupId,
        'titleAr': 'تم قبول طلبك ✅',
        'bodyAr': 'تمت إضافتك إلى جمعية: $groupName',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت الموافقة ✅')),
        );
      }
    } on FirebaseException catch (e) {
      debugPrint('APPROVE ERROR code=${e.code} msg=${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Firestore: ${e.code}')),
        );
      }
    } catch (e) {
      debugPrint('APPROVE ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy[requesterUid] = false);
    }
  }

  Future<void> _reject(String requesterUid) async {
    setState(() => _busy[requesterUid] = true);

    final db = FirebaseFirestore.instance;

    try {
      final g = await _getGroup();
      final groupName = (g['name'] ?? '') as String;

      final reqRef = db
          .collection('groups')
          .doc(widget.groupId)
          .collection('joinRequests')
          .doc(requesterUid);

      final inboxRef = db
          .collection('users')
          .doc(requesterUid)
          .collection('inbox')
          .doc();

      final batch = db.batch();

      // delete request
      batch.delete(reqRef);

      // notify requester
      batch.set(inboxRef, {
        'type': 'join_rejected',
        'groupId': widget.groupId,
        'titleAr': 'تم رفض الطلب',
        'bodyAr': 'تم رفض طلبك للانضمام إلى: $groupName',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الرفض ❌')),
        );
      }
    } on FirebaseException catch (e) {
      debugPrint('REJECT ERROR code=${e.code} msg=${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Firestore: ${e.code}')),
        );
      }
    } catch (e) {
      debugPrint('REJECT ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy[requesterUid] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reqStream = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('joinRequests')
        // إذا خايف من missing field، احذف orderBy
        .orderBy('requestedAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('طلبات الانضمام')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: reqStream,
        builder: (_, snap) {
          if (snap.hasError) {
            return Center(child: Text('ERROR: ${snap.error}'));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('لا يوجد طلبات'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = docs[i];
              final requesterUid = d.id;
              final busy = _busy[requesterUid] == true;

              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text('UID: $requesterUid'),
                subtitle: const Text('طلب انضمام'),
                trailing: busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'رفض',
                            icon: const Icon(Icons.close),
                            onPressed: () => _reject(requesterUid),
                          ),
                          IconButton(
                            tooltip: 'قبول',
                            icon: const Icon(Icons.check),
                            onPressed: () => _approve(requesterUid),
                          ),
                        ],
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
