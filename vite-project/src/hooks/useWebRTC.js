import { useState, useRef, useCallback, useEffect } from "react";

const TURN_HOST = import.meta.env.VITE_TURN_HOST || "jamshiddin.uz";
const TURN_USERNAME = import.meta.env.VITE_TURN_USERNAME || "bootchat";
const TURN_CREDENTIAL = import.meta.env.VITE_TURN_CREDENTIAL || "Bootchat2024!";

const ICE_SERVERS = {
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
  const iceQueue = useRef([]);
  const remoteDescSet = useRef(false);
  const callIdRef = useRef(null);
  const targetUserRef = useRef(null);
  const localStreamRef = useRef(null);

  const cleanup = useCallback(() => {
    if (pcRef.current) {
        pcRef.current.close();
        pcRef.current = null;
    }
    if (localStreamRef.current) {
        localStreamRef.current.getTracks().forEach(t => t.stop());
        localStreamRef.current = null;
    }
    remoteDescSet.current = false;
    iceQueue.current = [];
    setCallState(null);
    setLocalStream(null);
    setRemoteStream(null);
    setIncomingCall(null);
    setCallStartedAt(null);
    setCallError(null);
  }, []);

  const createPeerConnection = useCallback((target) => {
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
        console.log("ICE Connection State:", pc.iceConnectionState);
        if (pc.iceConnectionState === 'connected' || pc.iceConnectionState === 'completed') {
            setCallState('connected');
            setCallStartedAt(prev => prev || Date.now());
        }
        if (pc.iceConnectionState === 'failed') {
            setCallError("Ulanish muvaffaqiyatsiz tugadi");
        }
    };

    pcRef.current = pc;
    return pc;
  }, [socket]);

  useEffect(() => {
    if (!socket) return;

    socket.on("CALL_OFFER", async (data) => {
      if (callState && callState !== "incoming") {
          socket.emit("CALL_REJECT", { target: data.caller.username, reason: "busy" });
          return;
      }
      callIdRef.current = data.callId;
      targetUserRef.current = data.caller.username;
      setIsVideo(data.isVideo);
      setRemoteUser(data.caller);
      setIncomingCall(data);
    });

    socket.on("CALL_ANSWER", async (data) => {
      try {
        if (!pcRef.current) return;
        
        // --- MUHIM: Signaling state tekshiruvi ---
        if (pcRef.current.signalingState === "stable") {
            console.log("Ulanish allaqachon barqaror, ANSWER e'tiborsiz qoldirildi.");
            return;
        }

        await pcRef.current.setRemoteDescription(new RTCSessionDescription(data.answer));
        remoteDescSet.current = true;
        
        while (iceQueue.current.length > 0) {
          const cand = iceQueue.current.shift();
          await pcRef.current.addIceCandidate(new RTCIceCandidate(cand));
        }
      } catch (e) { console.error("CALL_ANSWER xatosi:", e); }
    });

    socket.on("ICE_CANDIDATE", async (data) => {
      try {
        if (pcRef.current && remoteDescSet.current) {
          await pcRef.current.addIceCandidate(new RTCIceCandidate(data.candidate));
        } else {
          iceQueue.current.push(data.candidate);
        }
      } catch (e) { console.warn("ICE Candidate qo'shish xatosi:", e); }
    });

    socket.on("CALL_END", cleanup);
    socket.on("CALL_REJECT", () => {
        setCallError("Rad etildi");
        setTimeout(cleanup, 2000);
    });

    return () => {
      socket.off("CALL_OFFER");
      socket.off("CALL_ANSWER");
      socket.off("ICE_CANDIDATE");
      socket.off("CALL_END");
      socket.off("CALL_REJECT");
    };
  }, [socket, callState, cleanup]);

  const startCall = useCallback(async (targetUser, video = false) => {
    try {
        cleanup();
        const stream = await navigator.mediaDevices.getUserMedia({
            audio: true,
            video: video
        });
        
        localStreamRef.current = stream;
        setLocalStream(stream);
        setIsVideo(video);
        setRemoteUser(targetUser);
        setCallState("calling");
        targetUserRef.current = targetUser.username;
        callIdRef.current = Math.random().toString(36).substring(7);

        const pc = createPeerConnection(targetUser.username);
        stream.getTracks().forEach(track => pc.addTrack(track, stream));

        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        socket.emit("CALL_OFFER", {
            target: targetUser.username,
            offer,
            isVideo: video,
            callId: callIdRef.current,
            caller: { 
                username: currentUser, 
                full_name: localStorage.getItem('full_name') || currentUser, 
                avatar: localStorage.getItem('app_avatar') 
            }
        });
    } catch (e) {
        setCallError("Media ruxsati rad etildi");
        console.error(e);
    }
  }, [socket, currentUser, createPeerConnection, cleanup]);

  const acceptCall = useCallback(async () => {
    if (!incomingCall) return;
    try {
        const stream = await navigator.mediaDevices.getUserMedia({
            audio: true,
            video: incomingCall.isVideo
        });

        localStreamRef.current = stream;
        setLocalStream(stream);
        setCallState("connected");

        const pc = createPeerConnection(incomingCall.caller.username);
        stream.getTracks().forEach(track => pc.addTrack(track, stream));

        await pc.setRemoteDescription(new RTCSessionDescription(incomingCall.offer));
        remoteDescSet.current = true;

        while (iceQueue.current.length > 0) {
            const cand = iceQueue.current.shift();
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
    } catch (e) {
        console.error("Qabul qilish xatosi:", e);
        socket.emit("CALL_REJECT", { target: incomingCall.caller.username });
        cleanup();
    }
  }, [incomingCall, createPeerConnection, socket, cleanup]);

  const switchCallMode = async (toVideo) => {
    if (!pcRef.current || !localStreamRef.current) return;

    try {
        if (toVideo) {
            const newStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
            const videoTrack = newStream.getVideoTracks()[0];
            
            const sender = pcRef.current.getSenders().find(s => s.track?.kind === 'video');
            if (sender) {
                await sender.replaceTrack(videoTrack);
            } else {
                pcRef.current.addTrack(videoTrack, localStreamRef.current);
            }
            
            localStreamRef.current.addTrack(videoTrack);
            // State-ni majburan yangilash
            setLocalStream(new MediaStream(localStreamRef.current.getTracks()));
            setIsVideo(true);
            setIsCameraOff(false);
        } else {
            localStreamRef.current.getVideoTracks().forEach(t => {
                t.stop();
                localStreamRef.current.removeTrack(t);
            });
            setLocalStream(new MediaStream(localStreamRef.current.getTracks()));
            setIsVideo(false);
        }
        socket.emit("CALL_MODE_SWITCH", { target: targetUserRef.current, isVideo: toVideo });
    } catch (e) {
        console.error("Rejim almashtirish xatosi:", e);
    }
  };

  const hangUp = useCallback(() => {
    if (targetUserRef.current) {
        socket.emit("CALL_END", { target: targetUserRef.current, callId: callIdRef.current });
    }
    cleanup();
  }, [socket, cleanup]);

  const toggleMute = () => {
    if (localStreamRef.current) {
        const track = localStreamRef.current.getAudioTracks()[0];
        if (track) {
            track.enabled = !track.enabled;
            setIsMuted(!track.enabled);
        }
    }
  };

  const toggleCamera = () => {
    if (localStreamRef.current && isVideo) {
        const track = localStreamRef.current.getVideoTracks()[0];
        if (track) {
            track.enabled = !track.enabled;
            setIsCameraOff(!track.enabled);
        }
    }
  };

  return {
    callState, callError, remoteUser, isVideo, isMuted, isCameraOff,
    localStream, remoteStream, incomingCall, callStartedAt,
    startCall, acceptCall, hangUp, toggleMute, toggleCamera, switchCallMode,
    rejectCall: () => {
        if (incomingCall) socket.emit("CALL_REJECT", { target: incomingCall.caller.username });
        cleanup();
    }
  };
}