import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:sdp_transform/sdp_transform.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Flutter Demo',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: MyHomePage(title: 'WebRTC Demo App'));
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // Peer Connection and Mediastream
  RTCPeerConnection _peerConnection;
  RTCPeerConnection _peerConnectionBroadcast;
  MediaStream _localStream;
  MediaStream _localStreamBroadcast;

  // Stream to be displayed on screen
  RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _localRendererBroadcast = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRendererBroadcast = new RTCVideoRenderer();

  final sdpController = TextEditingController();
  final sdpControllerBroadcast = TextEditingController();

  // Real Time Database
  final database = FirebaseDatabase.instance.reference();

  // Firebase Firestore
  final firestore = FirebaseFirestore.instance;

  // Others
  SharedPreferences prefs;
  bool _offer = false;

  // Media Constaints
  final Map<String, dynamic> mediaConstraints = {
    "audio": {
      "sampleSize": 8,
      "echoCancellation": true,
    },
    // Set "Video":false if we want audio only
    "video": {
      "mandatory": {
        "minWidth": '640',
        "minHeight": '480',
        "minFrameRate": '30',
      },
      "facingMode": "user",
      "optional": [],
    }
  };

  // This STUN server is responsible for delivering Public IP Address of peer
  // to establish the connection if we have a NAT or Firewall in between.
  Map<String, dynamic> configuration = {
    "iceServers": [
      {"url": "stun:stun.l.google.com:19302"},
    ]
  };

  final Map<String, dynamic> offerSdpConstraints = {
    "mandatory": {
      "OfferToReceiveAudio": true,
      "OfferToReceiveVideo": true,
    },
    "optional": [],
  };

  // Offer and Answer Options
  final Map<String, dynamic> options = {
    "offerToReceiveAudio": 1,
    "offerToReceiveVideo": 1
  };

  @override
  dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localRendererBroadcast.dispose();
    _remoteRendererBroadcast.dispose();
    sdpController.dispose();
    sdpControllerBroadcast.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    initRenderers();
    _createPeerConnection().then((pc) {
      _peerConnection = pc;
    });

    _createPeerConnectionBroadcast().then((pc) {
      _peerConnectionBroadcast = pc;
    });
  }

  // Methods
  initRenderers() async {
    await _localRenderer.initialize();
    await _localRendererBroadcast.initialize();
    await _remoteRenderer.initialize();
    await _remoteRendererBroadcast.initialize();
  }

  _getUserMedia() async {
    // getUserMedia will return stream of media(audio/video) which we have set as MediaConstraints
    MediaStream stream = await navigator.getUserMedia(mediaConstraints);

    // Stream will be rendered using RTCVideoRenderer
    _localRenderer.srcObject = stream;
    _localRenderer.mirror = true;

    return stream;
  }

  _createPeerConnection() async {
    prefs = await SharedPreferences.getInstance();

    _localStream = await _getUserMedia();

    RTCPeerConnection pc =
        await createPeerConnection(configuration, offerSdpConstraints);

    // This Stream will be send from peer A (peerConnection.addStream(stream))
    // and will be received by peer B (peerConnection.onAddStream)
    // pc.onAddTrack = (_localStream, track) {};

    pc.addStream(_localStream);

    pc.onSignalingState = (signalingState) {
      developer.log(signalingState.toString(), name: "rtc_SignalingState");
    };

    // This callback will generate ICECandidate when any peer request for offer or Answer
    // to establish connection.
    pc.onIceCandidate = (e) {
      if (e.candidate != null) {
        developer.log(
            json.encode({
              'candidate': e.candidate.toString(),
              'sdpMid': e.sdpMid.toString(),
              'sdpMlineIndex': e.sdpMlineIndex,
            }),
            name: "rtc_onIceCandidate");
        // Save Candidate from offer or Answer
        prefs.setString(
            'candidate',
            json.encode({
              'candidate': e.candidate.toString(),
              'sdpMid': e.sdpMid.toString(),
              'sdpMlineIndex': e.sdpMlineIndex,
            }).toString());
      }
    };

    // This callback will occur when SDP from Offer of peer A & SDP from Answer of peer B
    // is set as Remote Discription in opposite device and the generated ICECandidate from peer A
    // or peer B has set to any of peer for establishing the successfull connection state.
    // This callback will notify whether connection state is waiting, failed or successfull.
    pc.onIceConnectionState = (e) {
      developer.log(e.toString(), name: "rtc_onIceConnectionState");
    };

    // This callback will receive stream from peer B whose connection is
    // established with peer A and has Answer Stream with it. Once we receive
    // this stream we can allocate it to remote Video rendrer to display peer B.
    pc.onAddStream = (stream) {
      developer.log('addStream: ' + stream.id, name: "rtc_onAddStream");
      _remoteRenderer.srcObject = stream;
    };

    return pc;
  }

  _createPeerConnectionBroadcast() async {
    prefs = await SharedPreferences.getInstance();

    _localStreamBroadcast = await _getUserMedia();
    // _localRendererBroadcast.mirror = true;
    RTCPeerConnection pc =
        await createPeerConnection(configuration, offerSdpConstraints);

    pc.addStream(_localStreamBroadcast);
    pc.onIceCandidate = (e) {
      if (e.candidate != null) {
        developer.log(
            json.encode({
              'candidate': e.candidate.toString(),
              'sdpMid': e.sdpMid.toString(),
              'sdpMlineIndex': e.sdpMlineIndex,
            }),
            name: "rtc_onIceCandidate");
        // Save Candidate from offer or Answer
        prefs.setString(
            'candidate',
            json.encode({
              'candidate': e.candidate.toString(),
              'sdpMid': e.sdpMid.toString(),
              'sdpMlineIndex': e.sdpMlineIndex,
            }).toString());
      }
    };
    pc.onIceConnectionState = (e) {
      developer.log(e.toString(), name: "rtc_onIceConnectionState");
    };
    pc.onAddStream = (stream) {
      developer.log('addStream: ' + stream.id, name: "rtc_onAddStream");
      _remoteRendererBroadcast.srcObject = stream;
    };
    return pc;
  }

  void _createOffer() async {
    RTCSessionDescription description =
        await _peerConnection.createOffer(options);
    var session = parse(description.sdp);

    developer.log(json.encode(session), name: "rtc_session Offer");
    _offer = true;

    _peerConnection.setLocalDescription(description);

    _saveToDatabase(json.encode(session), "");
  }

  void _createOfferBroadcast() async {
    RTCSessionDescription description =
        await _peerConnectionBroadcast.createOffer(options);
    var session = parse(description.sdp);
    developer.log(json.encode(session), name: "rtc_session Offer");
    _offer = true;
    _peerConnectionBroadcast.setLocalDescription(description);
    _saveToDatabase(json.encode(session), "");
  }

  void _createAnswer() async {
    RTCSessionDescription description =
        await _peerConnection.createAnswer(options);

    var session = parse(description.sdp);

    developer.log(json.encode(session), name: "rtc_session Answer");

    _peerConnection.setLocalDescription(description);

    _saveToDatabase(json.encode(session), "");
  }

  void _createAnswerBroadcast() async {
    RTCSessionDescription description =
        await _peerConnectionBroadcast.createAnswer(options);
    var session = parse(description.sdp);
    developer.log(json.encode(session), name: "rtc_session Answer");
    _peerConnectionBroadcast.setLocalDescription(description);
    _saveToDatabase(json.encode(session), "");
  }

  void _setRemoteDescription() async {
    String jsonString = sdpController.text;
    dynamic session = await jsonDecode('$jsonString');

    String sdp = write(session, null);

    RTCSessionDescription description =
        new RTCSessionDescription(sdp, _offer ? 'answer' : 'offer');
    developer.log(description.toMap().toString(),
        name: "rtc_RTCSessionDescription");

    await _peerConnection.setRemoteDescription(description);
  }

  void _setRemoteDescriptionBroadcast() async {
    String jsonString = sdpControllerBroadcast.text;
    dynamic session = await jsonDecode('$jsonString');
    String sdp = write(session, null);
    RTCSessionDescription description =
        new RTCSessionDescription(sdp, _offer ? 'answer' : 'offer');
    developer.log(description.toMap().toString(),
        name: "rtc_RTCSessionDescription");
    await _peerConnectionBroadcast.setRemoteDescription(description);
  }

  void _addCandidate() async {
    String jsonString = sdpController.text;
    dynamic session = await jsonDecode('$jsonString');

    developer.log(session['candidate'].toString(),
        name: "rtc_session['candidate']");

    dynamic candidate = new RTCIceCandidate(
        session['candidate'], session['sdpMid'], session['sdpMlineIndex']);
    await _peerConnection.addCandidate(candidate);
  }

  void _addCandidateBroadcast() async {
    String jsonString = sdpControllerBroadcast.text;
    dynamic session = await jsonDecode('$jsonString');
    developer.log(session['candidate'].toString(),
        name: "rtc_session['candidate']");
    dynamic candidate = new RTCIceCandidate(
        session['candidate'], session['sdpMid'], session['sdpMlineIndex']);
    await _peerConnectionBroadcast.addCandidate(candidate);
  }

  // Widget
  // Video Screen
  Container videoRendererCall() => Container(
        height: 200.0,
        child: Row(
          children: [
            Expanded(
              child: Container(
                key: new Key("local"),
                margin: new EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
                decoration: new BoxDecoration(color: Colors.black),
                child: new RTCVideoView(_localRenderer),
              ),
            ),
            Expanded(
              child: Container(
                key: new Key("remote"),
                margin: new EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
                decoration: new BoxDecoration(color: Colors.black),
                child: new RTCVideoView(_remoteRenderer),
              ),
            ),
            Expanded(
              child: Container(
                key: new Key("remoteBroadcast"),
                margin: new EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
                decoration: new BoxDecoration(color: Colors.black),
                child: new RTCVideoView(_remoteRendererBroadcast),
              ),
            ),
          ],
        ),
      );

  // Offer and Answer & ICECandidate
  Row offerAndAnswerPeerB() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              children: [
                RaisedButton(
                  onPressed: _createOffer,
                  child: Text(
                    'Offer & Save SDP(B)',
                    textAlign: TextAlign.center,
                  ),
                  color: Colors.amber,
                ),
                RaisedButton(
                  onPressed: _saveICECandidateToFirebase,
                  child: Text(
                    'Save ICECandidate(B)',
                    textAlign: TextAlign.center,
                  ),
                  color: Colors.amber,
                ),
              ],
            ),
          ),
          SizedBox(width: 5.0),
          Expanded(
            child: Column(
              children: [
                RaisedButton(
                  onPressed: _createAnswer,
                  child: Text(
                    'Answer & Svae SDP(B)',
                    textAlign: TextAlign.center,
                  ),
                  color: Colors.amber,
                ),
                RaisedButton(
                    onPressed: _saveICECandidateToFirebase,
                    child: Text(
                      'Save ICECandidate(B)',
                      textAlign: TextAlign.center,
                    ),
                    color: Colors.amber),
              ],
            ),
          )
        ],
      );

  Row offerAndAnswerPeerC() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              children: [
                RaisedButton(
                  onPressed: _createOfferBroadcast,
                  child: Container(
                    child: Text(
                      'Offer & Save SDP(C)',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  color: Colors.amber,
                ),
                RaisedButton(
                  onPressed: _saveICECandidateToFirebase,
                  child: Container(
                    child: Text(
                      'Save ICECandidate(C)',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  color: Colors.amber,
                ),
              ],
            ),
          ),
          SizedBox(width: 5.0),
          Expanded(
            child: Column(
              children: [
                RaisedButton(
                  onPressed: _createAnswerBroadcast,
                  child: Container(
                    child: Text(
                      'Answer & Svae SDP(C)',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  color: Colors.amber,
                ),
                RaisedButton(
                  onPressed: _saveICECandidateToFirebase,
                  child: Container(
                    child: Text(
                      'Save ICECandidate(C)',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  color: Colors.amber,
                ),
              ],
            ),
          ),
        ],
      );

  // Text-field for Two Peer Connections
  Padding sdpCandidatesTFPeerConnectionWithB() => Padding(
        padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 5.0),
        child: TextField(
          controller: sdpController,
          keyboardType: TextInputType.multiline,
          maxLines: 4,
          maxLength: TextField.noMaxLength,
          decoration: InputDecoration(
            contentPadding: EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 10.0),
            hintText: "Session Description & ICECandidates (Peer B) ",
            border: OutlineInputBorder(),
          ),
        ),
      );

  Padding sdpCandidatesTFPeerConnectionWithC() => Padding(
        padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 5.0),
        child: TextField(
          controller: sdpControllerBroadcast,
          keyboardType: TextInputType.multiline,
          maxLines: 4,
          maxLength: TextField.noMaxLength,
          decoration: InputDecoration(
              contentPadding: EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 10.0),
              hintText: "Session Description & ICECandidates (Peer C)",
              border: OutlineInputBorder()),
        ),
      );

  // Set remote description
  Row sdpCandidateButtonsToB() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: <Widget>[
        RaisedButton(
            onPressed: _setRemoteDescription,
            child: Text('Set Remote Desc(B)'),
            color: Colors.amber),
        RaisedButton(
            onPressed: _addCandidate,
            child: Text('Add Candidate(B)'),
            color: Colors.amber)
      ]);

  Row sdpCandidateButtonsToC() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: <Widget>[
        RaisedButton(
          onPressed: _setRemoteDescriptionBroadcast,
          child: Text('Set Remote Desc(C)'),
          color: Colors.amber,
        ),
        RaisedButton(
          onPressed: _addCandidateBroadcast,
          child: Text('Add Candidate(C)'),
          color: Colors.amber,
        )
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Container(
        child: ListView(
          children: [
            Column(
              children: [
                videoRendererCall(),
                // Peer B
                Container(
                  margin: EdgeInsets.fromLTRB(10.0, 5.0, 10.0, 5.0),
                  padding: EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5.0),
                      border: Border.all(color: Colors.black54, width: 2.0)),
                  child: Column(
                    children: [
                      offerAndAnswerPeerB(),
                      sdpCandidatesTFPeerConnectionWithB(),
                      sdpCandidateButtonsToB(),
                    ],
                  ),
                ),
                // Peer C
                Container(
                  margin: EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 10.0),
                  padding: EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5.0),
                      border: Border.all(color: Colors.black54, width: 2.0)
                      //color: Color(0xFFD6E4FF),
                      ),
                  child: Column(
                    children: [
                      offerAndAnswerPeerC(),
                      sdpCandidatesTFPeerConnectionWithC(),
                      sdpCandidateButtonsToC(),
                    ],
                  ),
                ),
                SizedBox(height: 30.0),
              ],
            )
          ],
        ),
      ),
    );
  }

  // Database Methods
  // Save Session Description offer to Firebase
  _saveToDatabase(String session, String candidate) async {
    prefs = await SharedPreferences.getInstance();
    // Cloud Fire-store
    firestore.collection("users").add({
      "session": session.toString(),
      "candidate": candidate.toString(),
    }).then((value) {
      prefs.setString('id', value.id);
      // Real Time Database
      database.child(value.id).set({
        'session': session,
        'candidate': candidate,
      });
    });
  }

  // Save ICECandidate of Offer/Answer to Firebase
  _saveICECandidateToFirebase() async {
    prefs = await SharedPreferences.getInstance();
    String id = prefs.getString('id');
    String candidate = prefs.getString('candidate');
    developer.log(candidate, name: "rtc_");
    firestore.collection("users").doc("$id").update({
      "candidate": candidate,
    });
  }
}
