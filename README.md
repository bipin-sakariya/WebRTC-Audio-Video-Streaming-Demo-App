# Audio BroadCasting Demo
## Video calling App Peer to Peer using WebRTC

	WebRTC plugin for Flutter (flutter_webrtc)
	Firebase 

# What
- WebRTC is mainly used for real time communication like video/Audio call and chat on Peer-to-Peer and Data channel communication.
- In this app, we have implmented Peer-to-Peer video calling using RTCPeerConnection.

# Why 
- WebRTC provides custom friendly channeling mechanism for connections.

# How
## WebRTC
- Configuration of WebRTC  : https://pub.dev/packages/flutter_webrtc
- Flutter_webrtc flutter plugin is responsible for integrating WebRTC API to our app.
- getUserMedia is responsible for transmitting video/audio with constraints.

# Firebase
- Firebase configuration
- FIrebase is used as a channeling mechanism to store generated SDP and ICECandidate from Offer and Answer of Peers.
- These SDP and ICECandidate are then delivered to those peers who wants to establish the connection.



https://user-images.githubusercontent.com/36040972/152733217-467ee5f8-ff17-4569-9a14-05e21f993cc8.MOV

https://user-images.githubusercontent.com/36040972/152733319-03c4e35b-253b-498c-a333-5307d2c21207.MOV

https://user-images.githubusercontent.com/36040972/152733340-5463d6ca-8b49-48d7-8c19-bea5905a1101.MOV


