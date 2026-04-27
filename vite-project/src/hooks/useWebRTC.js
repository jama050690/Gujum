import { useState, useRef, useCallback, useEffect } from "react";
import { playRingtone, playCallEnd } from "@/utils/sounds";

const TURN_HOST = import.meta.env.VITE_TURN_HOST || "jamshiddin.uz";
const TURN_USERNAME = import.meta.env.VITE_TURN_USERNAME || "bootchat";
const TURN_CREDENTIAL = import.meta.env.VITE_TURN_CREDENTIAL || "Bootchat2024!";

const ICE_SERVERS = {
  iceServers: [
    { urls: "stun:stun.l.google.com:19302" },
    {
      urls: `turn:${TURN_HOST}:3478`,
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
  const ringtoneRef = useRef(null);

  const stopRingtone = useCallback(() => {
    if (ringtoneRef.current) {
      ringtoneRef.current.stop();
      ringtoneRef.current = null;
    }
  }, []);

  const cleanup = useCallback(() => {
    stopRingtone();
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
    targetUserRef.current = null;
  }, [stopRingtone]);

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
            stopRingtone();
            setCallState('connected');
            setCallStartedAt(prev => prev || Date.now());
        }
        if (pc.iceConnectionState === 'failed' || pc.iceConnectionState === 'disconnected') {
            setCallError("Aloqa uzildi");
            cleanup();
        }
    };

    pcRef.current = pc;
    return pc;
  }, [socket, stopRingtone, cleanup]);

  useEffect(() => {
    if (!socket) return;

    // MUHIM: ICE_CANDIDATE tinglovchisi qo'shildi
    socket.on("ICE_CANDIDATE", async (data) => {
        try {
            if (pcRef.current) {
                const candidate = new RTCIceCandidate(data.candidate);
                if (remoteDescSet.current) {
                    await pcRef.current.addIceCandidate(candidate);
                } else {
                    iceQueue.current.push(candidate);
                }
            }
        } catch (e) {
            console.error("ICE Candidate qo'shishda xato:", e);
        }
    });

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
      setCallState("incoming");
      
      stopRingtone();
      ringtoneRef.current = playRingtone();
    });

    socket.on("CALL_ANSWER", async (data) => {
      stopRingtone();
      try {
        if (!pcRef.current) return;
        
        await pcRef.current.setRemoteDescription(new RTCSessionDescription(data.answer));
        remoteDescSet.current = true;
        
        // Navbatda turgan ICE nomzodlarni qo'shish
        while (iceQueue.current.length > 0) {
          const cand = iceQueue.current.shift();
          await pcRef.current.addIceCandidate(cand);
        }
      } catch (e) { console.error("CALL_ANSWER xatosi:", e); }
    });

    socket.on("CALL_END", () => {
        playCallEnd();
        cleanup();
    });

    socket.on("CALL_REJECT", () => {
        stopRingtone();
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
  }, [socket, callState, cleanup, stopRingtone]);

  const startCall = useCallback(async (targetUser, video = false) => {
    try {
        cleanup();
        const stream = await navigator.mediaDevices.getUserMedia({
            audio: true, video: video
        });
        
        localStreamRef.current = stream;
        setLocalStream(stream);
        setIsVideo(video);
        setRemoteUser(targetUser);
        setCallState("calling");
        targetUserRef.current = targetUser.username;
        callIdRef.current = Math.random().toString(36).substring(7);

        stopRingtone();
        ringtoneRef.current = playRingtone();

        const pc = createPeerConnection(targetUser.username);
        stream.getTracks().forEach(track => pc.addTrack(track, stream));

        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        socket.emit("CALL_OFFER", {
            target: targetUser.username,
            offer, isVideo: video,
            callId: callIdRef.current,
            caller: { 
                username: currentUser, 
                full_name: localStorage.getItem('full_name') || currentUser, 
                avatar: localStorage.getItem('app_avatar') 
            }
        });
    } catch (e) {
        setCallError("Media ruxsati berilmadi");
        cleanup();
    }
  }, [socket, currentUser, createPeerConnection, cleanup, stopRingtone]);

  const acceptCall = useCallback(async () => {
    stopRingtone();
    if (!incomingCall) return;
    try {
        const stream = await navigator.mediaDevices.getUserMedia({
            audio: true, video: incomingCall.isVideo
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
            await pc.addIceCandidate(cand);
        }

        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);

        socket.emit("CALL_ANSWER", {
            target: incomingCall.caller.username,
            answer, callId: callIdRef.current
        });
        setIncomingCall(null);
    } catch (e) {
        socket.emit("CALL_REJECT", { target: incomingCall.caller.username });
        cleanup();
    }
  }, [incomingCall, createPeerConnection, socket, cleanup, stopRingtone]);

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

  const hangUp = useCallback(() => {
    if (targetUserRef.current) {
        socket.emit("CALL_END", { target: targetUserRef.current, callId: callIdRef.current });
    }
    cleanup();
  }, [socket, cleanup]);

  return {
    callState, callError, remoteUser, isVideo, isMuted, isCameraOff,
    localStream, remoteStream, incomingCall, callStartedAt,
    startCall, acceptCall, hangUp, toggleMute, toggleCamera,
    rejectCall: () => {
        if (incomingCall) socket.emit("CALL_REJECT", { target: incomingCall.caller.username });
        cleanup();
    }
  };
}