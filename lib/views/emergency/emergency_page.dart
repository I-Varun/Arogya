import 'package:background_sms/background_sms.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:local_auth/local_auth.dart';

import '../../db/database_helper.dart';
import '../../services/auth/auth_service.dart';
import 'package:location/location.dart' as location;

class EmergencyPage extends StatefulWidget {
  const EmergencyPage({super.key});

  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> {
  List<String> phoneNo = [];
  final GeolocatorPlatform _geolocatorPlatform = GeolocatorPlatform.instance;
  Position? _currentPosition;
  String? _currentAddress;
  LocationPermission? permission;
  late final _sqlhelper;

  String get userEmail => Authservice.firebase().currentUser!.email!;

  void refreshJournals() async {
    DatabaseUser db = await _sqlhelper.getUser(email: userEmail);

    phoneNo.add(db.phone1);
    phoneNo.add(db.phone2);
  }

  _getCurrentLocation() async {
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      Fluttertoast.showToast(msg: "Permissions denied");
      if (permission == LocationPermission.deniedForever) {
        Fluttertoast.showToast(msg: "Permissions denied Forever");
      }
    } else {
      final position = await _geolocatorPlatform.getLastKnownPosition();
      setState(() {
        _currentPosition = position;
        _getAddressFromLatLon();
      });
      print(_currentAddress);
    }
  }

  _getAddressFromLatLon() async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
          _currentPosition!.latitude, _currentPosition!.longitude);
      Placemark place = placemarks[0];
      setState(() {
        _currentAddress =
            "${place.locality},${place.postalCode},${place.street}";
      });
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString());
    }
  }

  _getPermissions() async => await [Permission.sms].request();
  _isPermissionGranted() async => await Permission.sms.status.isGranted;

  late final LocalAuthentication auth;
  bool _support = false;

  @override
  void initState() {
    _isPermissionGranted();
    _sqlhelper = SQLHelper();
    refreshJournals();
    // TODO: implement initState
    super.initState();
    auth = LocalAuthentication();
    auth.isDeviceSupported().then((bool isSupported) => setState(() {
          _support = isSupported;
        }));
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _showLocationDisabledDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Location Services Disabled'),
          content: Text('Please enable location services to use this feature.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkAndEnableLocation(BuildContext context) async {
    location.Location loc = location.Location();

    bool serviceEnabled = await loc.serviceEnabled();
    if (!serviceEnabled) {
      bool serviceRequested = await loc.requestService();
      if (!serviceRequested) {
        // The user declined to enable location services
        _showLocationDisabledDialog(context);
      }
    } else {
      // Location services are already enabled, proceed with your app logic
      // For example, fetch user's location here
      Fluttertoast.showToast(msg: "Location services Enabled");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      //Optional it is written for testing purpose
      children: <Widget>[
        if (_support)
          const Text('This device supports biometrics')
        else
          const Text('This device is not supported'),

        //  const Divider(height: 100),
        Container(
          margin: EdgeInsets.only(
              left: 20,
              right: 20,
              top: (MediaQuery.of(context).size.height) * 0.40),
          child: FloatingActionButton.extended(
            extendedPadding: EdgeInsets.only(left: 120, right: 120),
            label: const Text(
              'Authenticate',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            icon: const Icon(
              FontAwesomeIcons.fingerprint,
              color: Colors.black,
            ), // <-- Text
            backgroundColor: const Color.fromARGB(255, 8, 100, 176),
            onPressed: () async {
              await _checkAndEnableLocation(context);
              await _getCurrentLocation();
              await _authin();
            },
          ),
        )
      ],
    );
  }

  Future<void> _authin() async {
    try {
      bool authinticate = await auth.authenticate(
          localizedReason: 'use fingerprint to authenticate',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: true,
          ));
      if (authinticate) {
        final ConfirmAction? action = await _asyncConfirmDialog(
            context, _currentPosition, _currentAddress, phoneNo);
        print("Confirm Action $action");
      }
      print("Authenticated : $authinticate");
    } on PlatformException catch (e) {
      print(e);
    }
  }

  Future<void> _getBiometrics() async {
    List<BiometricType> availableBios = await auth.getAvailableBiometrics();
    print("List of availableBios : $availableBios");
    if (!mounted) {
      return;
    }
  }
}

enum ConfirmAction { Cancel, Accept }

_sendSms(String phoneNumber, String message, {int? simSlot}) async {
  await BackgroundSms.sendMessage(
    phoneNumber: phoneNumber,
    message: message,
  ).then((SmsStatus status) {
    if (status == SmsStatus.sent) {
      Fluttertoast.showToast(msg: "sent");
    } else {
      Fluttertoast.showToast(msg: "failed to send message ${status}");
    }
  });
}

Future<ConfirmAction?> _asyncConfirmDialog(
    BuildContext context,
    Position? _currentPosition,
    String? _currentAddress,
    List<String> phoneNo) async {
  return showDialog<ConfirmAction>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Are you sure to access the emergency sevices?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            )),
        content: const Text(
            'If the emergency service is activated for fun,then actions will be taken according to the terms and conditions.\nPress cancel to return back to the page',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            )),
        actions: <Widget>[
          ElevatedButton(
            child: const Text('Cancel',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                )),
            onPressed: () {
              Navigator.of(context).pop(ConfirmAction.Cancel);
            },
          ),
          ElevatedButton(
            child: const Text('Ok',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                )),
            onPressed: () async {
              String message =
                  "https://www.google.com/maps/search/?api=1&query=${_currentPosition?.latitude}%2C${_currentPosition?.longitude}";
              for (String number in phoneNo) {
                _sendSms(number, " Please Help I am at: $message ");
              }

              Navigator.of(context).pop(ConfirmAction.Accept);
            },
          )
        ],
      );
    },
  );
}
