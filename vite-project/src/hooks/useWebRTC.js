import { useState, useRef, useCallback, useEffect } from "react";
import { playRingtone, playCallEnd } from "@/utils/sounds";
import { getProfileData } from "@/utils/storage";

const TURN_HOST = import.meta.env.VITE_TURN_HOST || "jamshiddin.uz";
const TURN_USERNAME = import.meta.env.VITE_TURN_USERNAME || "bootchat";
const TURN_CREDENTIAL = import.meta.env.VITE_TURN_CREDENTIAL || "Bootchat2024!";

const ICE_SERVERS = {
  sdpSemantics: "unified-plan",
  iceCandidatePoolSize: 10, // Pool size oshirildi tezroq ulanish uchun
  iceServers: [
    { urls: "stun:stun.l.google.com:19302" },
    { urls: "stun:stun1.l.google.com:19302" },
    { urls: "stun:stun2.l.google.com:19302" },
    {
      urls: `turn:${TURN_HOST}:3478?transport=udp`,
      username: TURN_USERNAME,
      credential: TURN_CREDENTIAL,
    },
    {
      urls: `turn:${TURN_HOST}:3478?transport=tcp`,
      username: TURN_USERNAME,
      credential: TURN_CREDENTIAL,
    }
  ],
};

const AUDIO_CONSTRAINTS = {
  echoCancellation: true,
  noiseSuppression: true,
  autoGainControl: true,
};

const VIDEO_CONSTRAINTS = {
  facingMode: "user",
  width: { ideal: 640 }, // Mobil va bitta Wi-Fi uchun ideal o'lcham
  height: { ideal: 480 },
};

export function useWebRTC(socket, currentUser) {
  const [callState, setCallState] = useState(null);
  const [remoteUser, setRemoteUser] = useState(null);
  const [callStartedAt, setCallStartedAt] = useState(null);
  const [isVideo, setIsVideo] = useState(false);
  const [isMuted, setIsMuted] = useState(false);
  const [isCameraOff, setIsCameraOff] = useState(false);
  const [incomingCall, setIncomingCall] = useState(null);
  const [callError, setCallError] = useState(null);
  const [localStream, setLocalStream] = useState(null);
  const [remoteStream, setRemoteStream] = useState(null);

  const pcRef = useRef(null);
  const localStreamRef = useRef(null);
  const remoteStreamRef = useRef(null);
  const iceCandidateQueue = useRef([]);
  const remoteDescriptionSet = useRef(false);
  const callIdRef = useRef(null);
  const targetUsernameRef = useRef(null);
  const isVideoRef = useRef(false);
  const offerInFlightRef = useRef(false);

  const cleanup = useCallback(() => {
    if (pcRef.current) {
        pcRef.current.close();
        pcRef.current = null;
    }
    localStreamRef.current?.getTracks().forEach(t => t.stop());
    localStreamRef.current = null;
    remoteStreamRef.current = null;
    remoteDescriptionSet.current = false;
    iceCandidateQueue.current = [];
    setCallState(null);
    setLocalStream(null);
    setRemoteStream(null);
    setIncomingCall(null);
    setCallError(null);
  }, []);

  const createPeerConnection = useCallback((target) => {
    if (pcRef.current) pcRef.current.close();
    
    const pc = new RTCPeerConnection(ICE_SERVERS);

    pc.onicecandidate = (event) => {
      if (event.candidate && socket) {
        socket.emit("ICE_CANDIDATE", {
          target,
          candidate: event.candidate,
          callId: callIdRef.current,
        });
      }
    };

    pc.ontrack = (event) => {
      if (event.streams && event.streams[0]) {
        setRemoteStream(event.streams[0]);
      }
    };

    pc.oniceconnectionstatechange = () => {
        if (pc.iceConnectionState === 'connected') {
            setCallState('connected');
            setCallError(null);
        }
        if (pc.iceConnectionState === 'failed') {
            setCallError("Ulanish muvaffaqiyatsiz (ICE Error)");
        }
    };

    pcRef.current = pc;
    return pc;
  }, [socket]);

  // --- SIGNALLING HANDLERS ---

  useEffect(() => {
    if (!socket) return;

    socket.on("CALL_OFFER", async (data) => {
      if (callState) return; // Band bo'lsa qabul qilma
      callIdRef.current = data.callId;
      targetUsernameRef.current = data.caller.username;
      setIsVideo(data.isVideo);
      isVideoRef.current = data.isVideo;
      setRemoteUser(data.caller);
      setIncomingCall(data);
    });

    socket.on("CALL_ANSWER", async (data) => {
      if (!pcRef.current) return;
      await pcRef.current.setRemoteDescription(new RTCSessionDescription(data.answer));
      remoteDescriptionSet.current = true;
      
      // Navbatdagi candidate-larni qo'shish
      while (iceCandidateQueue.current.length > 0) {
        const cand = iceCandidateQueue.current.shift();
        await pcRef.current.addIceCandidate(new RTCIceCandidate(cand));
      }
      setCallState("connected");
    });

    socket.on("ICE_CANDIDATE", async (data) => {
      if (pcRef.current && remoteDescriptionSet.current) {
        await pcRef.current.addIceCandidate(new RTCIceCandidate(data.candidate));
      } else {
        iceCandidateQueue.current.push(data.candidate);
      }
    });

    socket.on("CALL_END", cleanup);
    socket.on("CALL_REJECT", cleanup);

    return () => {
      socket.off("CALL_OFFER");
      socket.off("CALL_ANSWER");
      socket.off("ICE_CANDIDATE");
      socket.off("CALL_END");
      socket.off("CALL_REJECT");
    };
  }, [socket, callState, cleanup]);

  const startCall = useCallback(async (targetUser, video = false) => {
    cleanup();
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: AUDIO_CONSTRAINTS,
      video: video ? VIDEO_CONSTRAINTS : false
    });
    
    localStreamRef.current = stream;
    setLocalStream(stream);
    setIsVideo(video);
    isVideoRef.current = video;
    setRemoteUser(targetUser);
    setCallState("calling");
    
    callIdRef.current = generateCallId();
    const pc = createPeerConnection(targetUser.username);
    stream.getTracks().forEach(track => pc.addTrack(track, stream));

    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    socket.emit("CALL_OFFER", {
      target: targetUser.username,
      offer,
      isVideo: video,
      callId: callIdRef.current,
      caller: buildSelfInfo(currentUser)
    });
  }, [socket, currentUser, createPeerConnection, cleanup]);

  const acceptCall = useCallback(async () => {
    if (!incomingCall) return;
    
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: AUDIO_CONSTRAINTS,
      video: incomingCall.isVideo ? VIDEO_CONSTRAINTS : false
    });

    localStreamRef.current = stream;
    setLocalStream(stream);
    setCallState("connected");

    const pc = createPeerConnection(incomingCall.caller.username);
    stream.getTracks().forEach(track => pc.addTrack(track, stream));

    await pc.setRemoteDescription(new RTCSessionDescription(incomingCall.offer));
    remoteDescriptionSet.current = true;

    // Navbatni bo'shatish
    while (iceCandidateQueue.current.length > 0) {
        const cand = iceCandidateQueue.current.shift();
        await pc.addIceCandidate(new RTCIceCandidate(cand));
    }

    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    socket.emit("CALL_ANSWER", {
      target: incomingCall.caller.username,
      answer,
      callId: callIdRef.current
    });
    setIncomingCall(null);
  }, [incomingCall, createPeerConnection, socket]);

  const hangUp = useCallback(() => {
    socket.emit("CALL_END", { target: targetUsernameRef.current, callId: callIdRef.current });
    cleanup();
  }, [socket, cleanup]);

  const toggleMute = () => {
    if (localStreamRef.current) {
        const audioTrack = localStreamRef.current.getAudioTracks()[0];
        audioTrack.enabled = !audioTrack.enabled;
        setIsMuted(!audioTrack.enabled);
    }
  };

  const toggleCamera = () => {
    if (localStreamRef.current && isVideo) {
        const videoTrack = localStreamRef.current.getVideoTracks()[0];
        videoTrack.enabled = !videoTrack.enabled;
        setIsCameraOff(!videoTrack.enabled);
    }
  };

  const switchCallMode = async (toVideo) => {
    // Rejimni o'zgartirish signali
    setIsVideo(toVideo);
    isVideoRef.current = toVideo;
    // Bu yerda yangi offer yuborish mantiqi
    startCall(remoteUser, toVideo);
  };

  return {
    callState, callError, remoteUser, isVideo, isMuted, isCameraOff,
    localStream, remoteStream, incomingCall,
    startCall, acceptCall, hangUp, toggleMute, toggleCamera, switchCallMode,
    rejectCall: cleanup
  };
}

// Yordamchi funksiyalar
function generateCallId() { return Math.random().toString(36).substring(7); }
function buildSelfInfo(user) { 
    return { username: user, full_name: localStorage.getItem('full_name'), avatar: localStorage.getItem('app_avatar') }; 
}