import { useState, useRef, useCallback, useEffect } from "react";
import { playRingtone, playCallEnd } from "@/utils/sounds";
 
const TURN_HOST = import.meta.env.VITE_TURN_HOST || "jamshiddin.uz";
const TURN_USERNAME = import.meta.env.VITE_TURN_USERNAME || "bootchat";
const TURN_CREDENTIAL = import.meta.env.VITE_TURN_CREDENTIAL || "Bootchat2024!";
 
const ICE_SERVERS = {
  iceServers: [
    { urls: "stun:stun.l.google.com:19302" },
    { urls: `stun:${TURN_HOST}:3478` },
    {
      urls: [
        `turn:${TURN_HOST}:3478?transport=udp`,
        `turn:${TURN_HOST}:3478?transport=tcp`,
        `turns:${TURN_HOST}:5349`,
      ],
      username: TURN_USERNAME,
      credential: TURN_CREDENTIAL,
    }
  ],
  iceTransportPolicy: "relay"
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
  const callStateRef = useRef(null);
  const callIdRef = useRef(null);
  const targetUserRef = useRef(null);
  const localStreamRef = useRef(null);
  const ringtoneRef = useRef(null);
  const answeredCallIdsRef = useRef(new Set());
  const connectedCallIdsRef = useRef(new Set());

  const logStreamTracks = useCallback((label, stream) => {
    if (!stream) {
      console.log(`${label}: stream yo'q`);
      return;
    }
    console.log(
      `${label}: id=${stream.id} audio=${stream.getAudioTracks().length} video=${stream.getVideoTracks().length}`,
      {
        audioTracks: stream.getAudioTracks().map((track) => ({
          id: track.id,
          enabled: track.enabled,
          muted: track.muted,
          readyState: track.readyState,
        })),
        videoTracks: stream.getVideoTracks().map((track) => ({
          id: track.id,
          enabled: track.enabled,
          muted: track.muted,
          readyState: track.readyState,
        })),
      },
    );
  }, []);

  useEffect(() => {
    callStateRef.current = callState;
  }, [callState]);
 
  const stopRingtone = useCallback(() => {
    if (ringtoneRef.current) {
      ringtoneRef.current.stop();
      ringtoneRef.current = null;
    }
  }, []);
 
  const cleanup = useCallback(() => {
    stopRingtone();
    if (pcRef.current) {
      pcRef.current.onicecandidate = null;
      pcRef.current.ontrack = null;
      pcRef.current.oniceconnectionstatechange = null;
      pcRef.current.onconnectionstatechange = null;
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
    setIsMuted(false);
    setIsCameraOff(false);
    targetUserRef.current = null;
    callIdRef.current = null;
    answeredCallIdsRef.current.clear();
    connectedCallIdsRef.current.clear();
  }, [stopRingtone]);
 
  const createPeerConnection = useCallback((target) => {
    // Eski PC yopilgan bo'lsa yangi yasat
    if (pcRef.current && pcRef.current.connectionState !== "closed") {
      return pcRef.current;
    }
    if (pcRef.current) {
      pcRef.current.onicecandidate = null;
      pcRef.current.ontrack = null;
      pcRef.current.oniceconnectionstatechange = null;
      pcRef.current.onconnectionstatechange = null;
      pcRef.current.close();
      pcRef.current = null;
    }

    const pc = new RTCPeerConnection(ICE_SERVERS);

    const markCallConnected = () => {
      if (
        socket &&
        targetUserRef.current &&
        callIdRef.current &&
        !connectedCallIdsRef.current.has(callIdRef.current)
      ) {
        connectedCallIdsRef.current.add(callIdRef.current);
        socket.emit("CALL_CONNECTED", {
          target: targetUserRef.current,
          callId: callIdRef.current,
        });
      }
      stopRingtone();
      setCallState("connected");
      setCallStartedAt(prev => prev || Date.now());
    };

    pc.onicecandidate = (event) => {
      if (event.candidate && socket && callIdRef.current) {
        socket.emit("ICE_CANDIDATE", {
          target,
          candidate: event.candidate,
          callId: callIdRef.current,
        });
      }
    };
 
    pc.ontrack = (event) => {
      const [firstStream] = event.streams || [];
      const incomingTrack = event.track;
      console.log("Remote track keldi:", {
        kind: incomingTrack?.kind,
        id: incomingTrack?.id,
        enabled: incomingTrack?.enabled,
        muted: incomingTrack?.muted,
        readyState: incomingTrack?.readyState,
        streamId: firstStream?.id,
      });

      const stream = firstStream || new MediaStream();
      if (!firstStream && incomingTrack) {
        stream.addTrack(incomingTrack);
      }

      if (incomingTrack) {
        incomingTrack.onmute = () => {
          console.log("Remote track muted:", incomingTrack.kind, incomingTrack.id);
        };
        incomingTrack.onunmute = () => {
          console.log("Remote track unmuted:", incomingTrack.kind, incomingTrack.id);
        };
        incomingTrack.onended = () => {
          console.log("Remote track ended:", incomingTrack.kind, incomingTrack.id);
        };
      }

      logStreamTracks("Remote stream update", stream);
      setRemoteStream((previous) => {
        if (!previous) {
          return stream;
        }
        const merged = new MediaStream(previous.getTracks());
        for (const track of stream.getTracks()) {
          const exists = merged.getTracks().some((item) => item.id === track.id);
          if (!exists) {
            merged.addTrack(track);
          }
        }
        logStreamTracks("Remote stream merged", merged);
        return merged;
      });
      markCallConnected();
    };

    pc.oniceconnectionstatechange = () => {
      console.log("ICE Connection State:", pc.iceConnectionState);
      if (pc.iceConnectionState === "connected" || pc.iceConnectionState === "completed") {
        markCallConnected();
      }
      if (pc.iceConnectionState === "failed") {
        setCallError("Ulanish muvaffaqiyatsiz");
        if (socket && targetUserRef.current && callIdRef.current) {
          socket.emit("CALL_END", { target: targetUserRef.current, callId: callIdRef.current, reason: "connection_lost" });
        }
        cleanup();
      }
    };

    pc.onconnectionstatechange = () => {
      console.log("Peer Connection State:", pc.connectionState);
      if (pc.connectionState === "connected") {
        markCallConnected();
      }
      if (pc.connectionState === "failed") {
        setCallError("Ulanish muvaffaqiyatsiz");
        if (socket && targetUserRef.current && callIdRef.current) {
          socket.emit("CALL_END", { target: targetUserRef.current, callId: callIdRef.current, reason: "connection_lost" });
        }
        cleanup();
      }
    };
 
    pcRef.current = pc;
    return pc;
  }, [socket, stopRingtone, cleanup, logStreamTracks]);
 
  // Socket tinglovchilari
  useEffect(() => {
    if (!socket) return;
 
    const handleIceCandidate = async (data) => {
      try {
        if (!data.candidate) return;
        if (pcRef.current && remoteDescSet.current) {
          await pcRef.current.addIceCandidate(new RTCIceCandidate(data.candidate));
        } else {
          // Queue even if PC not created yet (user hasn't accepted call)
          iceQueue.current.push(data.candidate);
        }
      } catch (e) {
        console.error("ICE Candidate qo'shishda xato:", e);
      }
    };
 
    const handleCallAnswer = async (data) => {
      stopRingtone();
      try {
        if (!pcRef.current) return;

        // 1. Begona callId — e'tiborsiz qoldir
        if (data.callId && data.callId !== callIdRef.current) {
          console.log("Begona CALL_ANSWER e'tiborsiz qoldirildi:", data.callId);
          return;
        }

        // 2. Dublikat — faqat answeredCallIds va remoteDescSet tekshir
        if (answeredCallIdsRef.current.has(data.callId) || remoteDescSet.current) {
          console.log("Dublikat CALL_ANSWER e'tiborsiz qoldirildi:", data.callId);
          return;
        }

        // 3. signalingState noto'g'ri bo'lsa qayta urinma
        if (pcRef.current.signalingState !== "have-local-offer") {
          console.warn("CALL_ANSWER: signalingState noto'g'ri:", pcRef.current.signalingState);
          return;
        }

        await pcRef.current.setRemoteDescription(new RTCSessionDescription(data.answer));
        answeredCallIdsRef.current.add(data.callId);
        remoteDescSet.current = true;
        setCallState(prev => prev === "connected" ? prev : "connecting");
 
        // ICE queue ni bo'shat
        while (iceQueue.current.length > 0) {
          const cand = iceQueue.current.shift();
          await pcRef.current.addIceCandidate(cand);
        }
 
        if (data.answeredAt) {
          setCallStartedAt(data.answeredAt);
        } else if (data.connectedAt) {
          setCallStartedAt(data.connectedAt);
        }
      } catch (e) {
        console.error("CALL_ANSWER xatosi:", e);
      }
    };

    const handleCallOffer = async (data) => {
      if (callStateRef.current && callStateRef.current !== "incoming") {
        socket.emit("CALL_REJECT", {
          target: data.caller.username,
          reason: "busy",
          callId: data.callId,
          isVideo: data.isVideo,
        });
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
    };

    const handleCallEnd = () => {
      playCallEnd();
      cleanup();
    };

    const handleCallReject = () => {
      stopRingtone();
      setCallError("Rad etildi");
      setTimeout(cleanup, 2000);
    };

    const handleCallConnected = (data) => {
      if (data.callId && data.callId !== callIdRef.current) return;
      stopRingtone();
      setCallState("connected");
      setCallStartedAt((previous) => previous || data.connectedAt || Date.now());
    };

    const handleRenegotiateAnswer = async (data) => {
      const pc = pcRef.current;
      if (!pc || !data.answer) return;
      if (data.callId && data.callId !== callIdRef.current) return;
      try {
        if (pc.signalingState === "have-local-offer") {
          await pc.setRemoteDescription(new RTCSessionDescription(data.answer));
          console.log("CALL_RENEGOTIATE_ANSWER: video upgrade qo'llandi");
        }
      } catch (e) {
        console.error("CALL_RENEGOTIATE_ANSWER xatosi:", e);
      }
    };

    const handleRenegotiate = async (data) => {
      const pc = pcRef.current;
      if (!pc || !data.offer) return;
      if (data.callId && data.callId !== callIdRef.current) return;
      try {
        // Agar video track yo'q bo'lsa — kamera qo'shamiz
        if (data.isVideo) {
          let stream;
          try {
            stream = await navigator.mediaDevices.getUserMedia({ audio: false, video: true });
          } catch (_) {}
          if (stream) {
            const [videoTrack] = stream.getVideoTracks();
            if (videoTrack) {
              pc.addTrack(videoTrack, localStreamRef.current || new MediaStream([videoTrack]));
              if (localStreamRef.current) localStreamRef.current.addTrack(videoTrack);
              setLocalStream(prev => {
                if (!prev) return stream;
                const merged = new MediaStream(prev.getTracks());
                merged.addTrack(videoTrack);
                return merged;
              });
              setIsVideo(true);
              setIsCameraOff(false);
            }
          }
        }
        await pc.setRemoteDescription(new RTCSessionDescription(data.offer));
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        socket.emit("CALL_RENEGOTIATE_ANSWER", {
          target: targetUserRef.current,
          answer,
          callId: callIdRef.current,
        });
        console.log("CALL_RENEGOTIATE: video upgrade answer yuborildi");
      } catch (e) {
        console.error("CALL_RENEGOTIATE xatosi:", e);
      }
    };

    socket.on("ICE_CANDIDATE", handleIceCandidate);
    socket.on("CALL_ANSWER", handleCallAnswer);
    socket.on("CALL_CONNECTED", handleCallConnected);
    socket.on("CALL_OFFER", handleCallOffer);
    socket.on("CALL_END", handleCallEnd);
    socket.on("CALL_REJECT", handleCallReject);
    socket.on("CALL_RENEGOTIATE", handleRenegotiate);
    socket.on("CALL_RENEGOTIATE_ANSWER", handleRenegotiateAnswer);

    return () => {
      socket.off("ICE_CANDIDATE", handleIceCandidate);
      socket.off("CALL_ANSWER", handleCallAnswer);
      socket.off("CALL_CONNECTED", handleCallConnected);
      socket.off("CALL_OFFER", handleCallOffer);
      socket.off("CALL_END", handleCallEnd);
      socket.off("CALL_REJECT", handleCallReject);
      socket.off("CALL_RENEGOTIATE", handleRenegotiate);
      socket.off("CALL_RENEGOTIATE_ANSWER", handleRenegotiateAnswer);
    };
  }, [socket, cleanup, stopRingtone]);
 
  const startCall = useCallback(async (targetUser, video = false) => {
    if (callStateRef.current) return;
    try {
      cleanup();
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: true, video: video
      });
      logStreamTracks("Local outgoing stream", stream);
 
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
        offer,
        isVideo: video,
        callId: callIdRef.current,
        caller: {
          username: currentUser,
          full_name: localStorage.getItem("full_name") || currentUser,
          avatar: localStorage.getItem("app_avatar"),
        }
      });
    } catch (e) {
      console.error("startCall xatosi:", e);
      setCallError("Media ruxsati berilmadi");
      cleanup();
    }
  }, [socket, currentUser, createPeerConnection, cleanup, stopRingtone, logStreamTracks]);
 
  const acceptCall = useCallback(async () => {
    stopRingtone();
    if (!incomingCall) return;
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: true, video: incomingCall.isVideo
      });
      logStreamTracks("Local accepted stream", stream);
 
      localStreamRef.current = stream;
      setLocalStream(stream);
      setIsVideo(incomingCall.isVideo);
      setRemoteUser(incomingCall.caller);
      setCallState("connecting");
 
      const pc = createPeerConnection(incomingCall.caller.username);

      // ✅ Track'larni avval qo'sh, keyin setRemoteDescription
      stream.getTracks().forEach(track => pc.addTrack(track, stream));

      await pc.setRemoteDescription(new RTCSessionDescription(incomingCall.offer));
      remoteDescSet.current = true;
 
      // ICE queue ni bo'shat
      while (iceQueue.current.length > 0) {
        const cand = iceQueue.current.shift();
        await pc.addIceCandidate(cand);
      }
 
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
 
      socket.emit("CALL_ANSWER", {
        target: incomingCall.caller.username,
        answer,
        callId: callIdRef.current,
      });

      setCallStartedAt(prev => prev || Date.now());
      setIncomingCall(null);
    } catch (e) {
      console.error("CALL_ACCEPT xatosi:", e);
      socket.emit("CALL_REJECT", {
        target: incomingCall.caller.username,
        callId: callIdRef.current,
        isVideo: incomingCall.isVideo,
      });
      cleanup();
    }
  }, [incomingCall, createPeerConnection, socket, cleanup, stopRingtone, logStreamTracks]);
 
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
 
  const upgradeToVideo = useCallback(async () => {
    const pc = pcRef.current;
    if (!pc || !targetUserRef.current || !callIdRef.current || isVideo) return;
    const iceState = pc.iceConnectionState;
    if (iceState !== "connected" && iceState !== "completed") {
      console.warn("upgradeToVideo: ICE hali ulanmagan, bekor qilindi:", iceState);
      return;
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: false, video: true });
      const [videoTrack] = stream.getVideoTracks();
      if (!videoTrack) return;

      const baseStream = localStreamRef.current || new MediaStream();
      pc.addTrack(videoTrack, baseStream);

      if (localStreamRef.current) {
        localStreamRef.current.addTrack(videoTrack);
      } else {
        localStreamRef.current = stream;
      }

      setLocalStream(prev => {
        if (!prev) return stream;
        const merged = new MediaStream(prev.getTracks());
        merged.addTrack(videoTrack);
        return merged;
      });

      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      socket.emit("CALL_RENEGOTIATE", {
        target: targetUserRef.current,
        offer,
        callId: callIdRef.current,
        isVideo: true,
      });

      setIsVideo(true);
      setIsCameraOff(false);
      console.log("upgradeToVideo: renegotiation offer yuborildi");
    } catch (e) {
      console.error("upgradeToVideo xatosi:", e);
      setCallError("Kamera ochilmadi");
    }
  }, [socket, isVideo]);

  const hangUp = useCallback(() => {
    if (targetUserRef.current) {
      socket.emit("CALL_END", {
        target: targetUserRef.current,
        callId: callIdRef.current,
      });
    }
    cleanup();
  }, [socket, cleanup]);
 
  return {
    callState, callError, remoteUser, isVideo, isMuted, isCameraOff,
    localStream, remoteStream, incomingCall, callStartedAt,
    startCall, acceptCall, hangUp, toggleMute, toggleCamera,
    switchCallMode: upgradeToVideo,
    rejectCall: () => {
      if (incomingCall) {
        socket.emit("CALL_REJECT", {
          target: incomingCall.caller.username,
          callId: callIdRef.current,
          isVideo: incomingCall.isVideo,
        });
      }
      cleanup();
    }
  };
}
