import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserDataProvider with ChangeNotifier {
  bool isSubscribed = false;
  Timestamp? subscriptionEndDate;
  bool isLoading = true;

  StreamSubscription? _userSubscription;

  UserDataProvider() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _listenToUserStatus(user.uid);
      } else {
        _userSubscription?.cancel();
        isSubscribed = false;
        subscriptionEndDate = null;
        isLoading = false;
        notifyListeners();
      }
    });
  }

  void _listenToUserStatus(String uid) {
    isLoading = true;
    notifyListeners();
    
    _userSubscription?.cancel();
    _userSubscription = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data() as Map<String, dynamic>;
          isSubscribed = data['isSubscribed'] ?? false;
          subscriptionEndDate = data['subscriptionEndDate'];
        } else {
          isSubscribed = false;
          subscriptionEndDate = null;
        }
        isLoading = false;
        notifyListeners();
      }, onError: (error) {
        print("Error in UserDataProvider: $error");
        isLoading = false;
        notifyListeners();
      });
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }
}