import { useState, useRef, useCallback, useEffect } from "react";
import { playRingtone, playCallEnd } from "@/utils/sounds";

const ICE_SERVERS = {
  iceServers: [
    { urls: "stun:stun.l.google.com:19302" },
    { urls: "stun:stun1.l.google.com:19302" },
    {
      urls: "turn:3.77.233.184:3478",
      username: "bootchat",
      credential: "Bootchat2024!",
    },
    {
      urls: "turn:3.77.233.184:3478?transport=tcp",
      username: "bootchat",
      credential: "Bootchat2024!",
    },
  ],
};

// Stronger mic constraints to reduce feedback/echo in voice calls.
const AUDIO_CONSTRAINTS = {
  echoCancellation: { ideal: true },
  noiseSuppression: { ideal: true },
  autoGainControl: { ideal: true },
  channelCount: { ideal: 1 },
};

export function useWebRTC(socket, currentUser) {
  const [callState, setCallState] = useState(null);
  const [remoteUser, setRemoteUser] = useState(null);
  const [isVideo, setIsVideo] = useState(false);
  const [isMuted, setIsMuted] = useState(false);
  const [isCameraOff, setIsCameraOff] = useState(false);
  const [incomingCall, setIncomingCall] = useState(null);
  const [callError, setCallError] = useState(null);

  const pcRef = useRef(null);
  const localStreamRef = useRef(null);
  const remoteStreamRef = useRef(null);
  const targetUsernameRef = useRef(null);
  const iceCandidateQueue = useRef([]);
  const remoteDescriptionSet = useRef(false);
  const isCallerRef = useRef(false);
  const isVideoRef = useRef(false);
  const callStartTimeRef = useRef(null);
  const [localStream, setLocalStream] = useState(null);
  const [remoteStream, setRemoteStream] = useState(null);
  const ringtoneRef = useRef(null);
  const ringingTimeoutRef = useRef(null);

  const clearRingingTimeout = useCallback(() => {
    if (ringingTimeoutRef.current) {
      clearTimeout(ringingTimeoutRef.current);
      ringingTimeoutRef.current = null;
    }
  }, []);

  useEffect(() => {
    if (!socket) return;

    const handleCallOffer = (data) => {
      try {
        console.log("CALL_OFFER keldi:", data.caller?.username);
        setIncomingCall({ caller: data.caller, isVideo: data.isVideo, offer: data.offer });
        ringtoneRef.current?.stop();
        ringtoneRef.current = playRingtone();
      } catch (err) {
        console.error("CALL_OFFER handler xato:", err);
      }
    };

    const handleCallAnswer = async (data) => {
      try {
        clearRingingTimeout();
        ringtoneRef.current?.stop();
        ringtoneRef.current = null;
        if (pcRef.current) {
          await pcRef.current.setRemoteDescription(new RTCSessionDescription(data.answer));
          remoteDescriptionSet.current = true;
          for (const candidate of iceCandidateQueue.current) {
            try {
              await pcRef.current.addIceCandidate(new RTCIceCandidate(candidate));
            } catch (err) {
              console.error("Buffered ICE candidate xato:", err);
            }
          }
          iceCandidateQueue.current = [];
        }
      } catch (err) {
        console.error("CALL_ANSWER handler xato:", err);
      }
    };

    const handleIceCandidate = async (data) => {
      if (!data.candidate) return;
      if (pcRef.current && remoteDescriptionSet.current) {
        try {
          await pcRef.current.addIceCandidate(new RTCIceCandidate(data.candidate));
        } catch (err) {
          console.error("ICE candidate qo'shishda xato:", err);
        }
      } else {
        iceCandidateQueue.current.push(data.candidate);
      }
    };

    const handleCallReject = () => {
      clearRingingTimeout();
      ringtoneRef.current?.stop();
      ringtoneRef.current = null;
      cleanup();
    };

    const handleCallEnd = () => {
      clearRingingTimeout();
      ringtoneRef.current?.stop();
      ringtoneRef.current = null;
      playCallEnd();
      cleanup();
    };

    const handleCallBlocked = () => {
      clearRingingTimeout();
      ringtoneRef.current?.stop();
      ringtoneRef.current = null;
      setCallError("Qo'ng'iroq amalga oshmadi.");
      setTimeout(() => cleanup(), 3000);
    };

    const handleCallNotDelivered = () => {
      clearRingingTimeout();
      ringtoneRef.current?.stop();
      ringtoneRef.current = null;
      setCallError("Foydalanuvchi hozir tarmoqda emas.");
      setTimeout(() => {
        const target = targetUsernameRef.current;
        if (socket && target) {
          socket.emit("CALL_END", {
            target,
            duration: 0,
            isVideo: isVideoRef.current,
            callerUsername: currentUser,
          });
        }
        cleanup();
      }, 3000);
    };

    socket.on("CALL_OFFER", handleCallOffer);
    socket.on("CALL_ANSWER", handleCallAnswer);
    socket.on("ICE_CANDIDATE", handleIceCandidate);
    socket.on("CALL_REJECT", handleCallReject);
    socket.on("CALL_END", handleCallEnd);
    socket.on("CALL_BLOCKED", handleCallBlocked);
    socket.on("CALL_NOT_DELIVERED", handleCallNotDelivered);

    return () => {
      socket.off("CALL_OFFER", handleCallOffer);
      socket.off("CALL_ANSWER", handleCallAnswer);
      socket.off("ICE_CANDIDATE", handleIceCandidate);
      socket.off("CALL_REJECT", handleCallReject);
      socket.off("CALL_END", handleCallEnd);
      socket.off("CALL_BLOCKED", handleCallBlocked);
      socket.off("CALL_NOT_DELIVERED", handleCallNotDelivered);
    };
  }, [socket, currentUser, clearRingingTimeout]);

  const cleanup = useCallback(() => {
    clearRingingTimeout();
    pcRef.current?.close();
    pcRef.current = null;
    localStreamRef.current?.getTracks().forEach((t) => t.stop());
    localStreamRef.current = null;
    remoteStreamRef.current = null;
    targetUsernameRef.current = null;
    iceCandidateQueue.current = [];
    remoteDescriptionSet.current = false;
    isCallerRef.current = false;
    isVideoRef.current = false;
    callStartTimeRef.current = null;
    setLocalStream(null);
    setRemoteStream(null);
    setCallState(null);
    setRemoteUser(null);
    setIncomingCall(null);
    setIsMuted(false);
    setIsCameraOff(false);
    setCallError(null);
  }, [clearRingingTimeout]);

  const createPeerConnection = useCallback((targetUsername) => {
    const pc = new RTCPeerConnection(ICE_SERVERS);

    pc.ontrack = (event) => {
      const incomingTrack = event.track;
      console.log("Remote track received:", incomingTrack.kind, incomingTrack.readyState);

      if (!remoteStreamRef.current) {
        remoteStreamRef.current = new MediaStream();
      }

      const alreadyAdded = remoteStreamRef.current
        .getTracks()
        .some((t) => t.id === incomingTrack.id);

      if (!alreadyAdded) {
        remoteStreamRef.current.addTrack(incomingTrack);
      }

      // Emit a fresh stream instance so React and media elements pick up changes reliably.
      setRemoteStream(new MediaStream(remoteStreamRef.current.getTracks()));

      incomingTrack.onended = () => {
        if (!remoteStreamRef.current) return;
        remoteStreamRef.current.removeTrack(incomingTrack);
        setRemoteStream(new MediaStream(remoteStreamRef.current.getTracks()));
      };
    };

    pc.onicecandidate = (event) => {
      if (event.candidate) {
        console.log("ICE candidate:", event.candidate.type, event.candidate.protocol);
        if (socket) {
          socket.emit("ICE_CANDIDATE", {
            target: targetUsername,
            candidate: event.candidate,
          });
        }
      } else {
        console.log("ICE gathering complete");
      }
    };

    pc.oniceconnectionstatechange = () => {
      console.log("ICE connection state:", pc.iceConnectionState);
      if (pc.iceConnectionState === "connected" || pc.iceConnectionState === "completed") {
        callStartTimeRef.current = Date.now();
        setCallState("connected");
      } else if (pc.iceConnectionState === "failed") {
        console.log("ICE failed, attempting restart...");
        setCallError("Ulanish xatosi — qayta ulanmoqda...");
        try {
          pc.restartIce();
        } catch (e) {
          console.error("ICE restart failed:", e);
          setCallError("Ulanib bo'lmadi. Internet yoki TURN serverni tekshiring.");
          setTimeout(() => cleanup(), 3000);
        }
      } else if (pc.iceConnectionState === "disconnected") {
        setCallError("Aloqa uzildi — qayta ulanmoqda...");
        setTimeout(() => {
          if (pcRef.current && pcRef.current.iceConnectionState === "disconnected") {
            setCallError("Aloqa tiklana olmadi.");
            setTimeout(() => cleanup(), 2000);
          }
        }, 5000);
      }
    };

    pc.onconnectionstatechange = () => {
      console.log("Connection state:", pc.connectionState);
      if (pc.connectionState === "failed") {
        setCallError("Ulanish muvaffaqiyatsiz tugadi.");
        setTimeout(() => cleanup(), 2000);
      }
    };

    pcRef.current = pc;
    return pc;
  }, [socket, cleanup]);

  const startCall = useCallback(async (targetUser, video = false) => {
    if (!socket || !targetUser) return;

    const targetUsername = targetUser.username;
    targetUsernameRef.current = targetUsername;
    isCallerRef.current = true;
    isVideoRef.current = video;
    setRemoteUser(targetUser);
    setIsVideo(video);
    setCallState("calling");

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: AUDIO_CONSTRAINTS,
        video: video ? { facingMode: "user" } : false,
      });
      localStreamRef.current = stream;
      setLocalStream(stream);

      const pc = createPeerConnection(targetUsername);
      stream.getTracks().forEach((track) => pc.addTrack(track, stream));

      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      socket.emit("CALL_OFFER", {
        target: targetUsername,
        caller: { username: currentUser, avatar: localStorage.getItem("app_avatar") },
        offer,
        isVideo: video,
      });

      ringtoneRef.current?.stop();
      ringtoneRef.current = playRingtone();
      setCallState("ringing");

      // 30 sekund javob bo'lmasa auto-hangup
      clearRingingTimeout();
      ringingTimeoutRef.current = setTimeout(() => {
        console.log("Ringing timeout — javob berilmadi");
        ringtoneRef.current?.stop();
        ringtoneRef.current = null;
        setCallError("Javob berilmadi.");
        if (socket && targetUsername) {
          socket.emit("CALL_END", {
            target: targetUsername,
            duration: 0,
            isVideo: video,
            callerUsername: currentUser,
          });
        }
        setTimeout(() => cleanup(), 2000);
      }, 30000);
    } catch (err) {
      console.error("Qo'ng'iroq boshlashda xato:", err);
      if (err.name === "NotAllowedError") {
        setCallError("Mikrofon/kamera ruxsati berilmadi.");
      } else {
        setCallError("Qo'ng'iroq boshlashda xato: " + err.message);
      }
      setTimeout(() => cleanup(), 3000);
    }
  }, [socket, currentUser, createPeerConnection, cleanup, clearRingingTimeout]);

  const acceptCall = useCallback(async () => {
    if (!incomingCall || !socket) return;
    ringtoneRef.current?.stop();
    ringtoneRef.current = null;

    const callerUsername = incomingCall.caller.username;
    targetUsernameRef.current = callerUsername;
    isCallerRef.current = false;
    isVideoRef.current = incomingCall.isVideo;
    setRemoteUser(incomingCall.caller);
    setIsVideo(incomingCall.isVideo);
    setCallState("connecting");

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: AUDIO_CONSTRAINTS,
        video: incomingCall.isVideo ? { facingMode: "user" } : false,
      });
      localStreamRef.current = stream;
      setLocalStream(stream);

      const pc = createPeerConnection(callerUsername);
      stream.getTracks().forEach((track) => pc.addTrack(track, stream));

      await pc.setRemoteDescription(new RTCSessionDescription(incomingCall.offer));
      remoteDescriptionSet.current = true;
      for (const candidate of iceCandidateQueue.current) {
        try {
          await pc.addIceCandidate(new RTCIceCandidate(candidate));
        } catch (err) {
          console.error("Buffered ICE candidate xato:", err);
        }
      }
      iceCandidateQueue.current = [];
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      socket.emit("CALL_ANSWER", {
        target: callerUsername,
        answer,
      });

      setIncomingCall(null);
    } catch (err) {
      console.error("Qo'ng'iroqni qabul qilishda xato:", err);
      if (err.name === "NotAllowedError") {
        setCallError("Mikrofon/kamera ruxsati berilmadi.");
      } else {
        setCallError("Qo'ng'iroqni qabul qilishda xato: " + err.message);
      }
      setTimeout(() => cleanup(), 3000);
    }
  }, [incomingCall, socket, createPeerConnection, cleanup]);

  const rejectCall = useCallback(() => {
    if (!incomingCall || !socket) return;
    ringtoneRef.current?.stop();
    ringtoneRef.current = null;
    socket.emit("CALL_REJECT", {
      target: incomingCall.caller.username,
      isVideo: incomingCall.isVideo,
    });
    setIncomingCall(null);
  }, [incomingCall, socket]);

  const hangUp = useCallback(() => {
    ringtoneRef.current?.stop();
    ringtoneRef.current = null;
    playCallEnd();
    const target = targetUsernameRef.current || remoteUser?.username;
    if (socket && target) {
      const duration = callStartTimeRef.current
        ? Math.round((Date.now() - callStartTimeRef.current) / 1000)
        : 0;
      socket.emit("CALL_END", {
        target,
        duration,
        isVideo: isVideoRef.current,
        callerUsername: isCallerRef.current ? currentUser : target,
      });
    }
    cleanup();
  }, [socket, remoteUser, currentUser, cleanup]);

  const toggleMute = useCallback(() => {
    if (localStreamRef.current) {
      const audioTrack = localStreamRef.current.getAudioTracks()[0];
      if (audioTrack) {
        audioTrack.enabled = !audioTrack.enabled;
        setIsMuted(!audioTrack.enabled);
      }
    }
  }, []);

  const toggleCamera = useCallback(() => {
    if (localStreamRef.current) {
      const videoTrack = localStreamRef.current.getVideoTracks()[0];
      if (videoTrack) {
        videoTrack.enabled = !videoTrack.enabled;
        setIsCameraOff(!videoTrack.enabled);
      }
    }
  }, []);

  return {
    callState,
    callError,
    remoteUser,
    isVideo,
    isMuted,
    isCameraOff,
    localStream,
    remoteStream,
    incomingCall,
    startCall,
    acceptCall,
    rejectCall,
    hangUp,
    toggleMute,
    toggleCamera,
  };
}
