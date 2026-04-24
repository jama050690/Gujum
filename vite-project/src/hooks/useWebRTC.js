import { useState, useRef, useCallback, useEffect } from "react";
import { playRingtone, playCallEnd } from "@/utils/sounds";
import { getProfileData } from "@/utils/storage";

const ICE_SERVERS = {
  sdpSemantics: "unified-plan",
  bundlePolicy: "max-bundle",
  rtcpMuxPolicy: "require",
  iceCandidatePoolSize: 4,
  iceServers: [
    { urls: "stun:stun.l.google.com:19302" },
    { urls: "stun:stun1.l.google.com:19302" },
    { urls: "stun:stun2.l.google.com:19302" },
    { urls: "stun:stun3.l.google.com:19302" },
    { urls: "stun:stun4.l.google.com:19302" },
    { urls: "stun:stun.cloudflare.com:3478" },
    { urls: "stun:global.stun.twilio.com:3478" },
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
    {
      urls: "turn:63.183.168.37:3478?transport=udp",
      username: "bootchat",
      credential: "Bootchat2024!",
    },
    {
      urls: "turn:63.183.168.37:3478?transport=tcp",
      username: "bootchat",
      credential: "Bootchat2024!",
    },
    {
      urls: "turns:63.183.168.37:5349?transport=tcp",
      username: "bootchat",
      credential: "Bootchat2024!",
    },
  ],
};

const AUDIO_CONSTRAINTS = {
  echoCancellation: { ideal: true },
  noiseSuppression: { ideal: true },
  autoGainControl: { ideal: true },
  channelCount: { ideal: 1 },
};

const VIDEO_CONSTRAINTS = {
  facingMode: "user",
  width: { ideal: 1280 },
  height: { ideal: 720 },
  frameRate: { ideal: 24, max: 30 },
};

const ACTIVE_CALL_STORAGE_KEY = "app_active_call_session";
const CALL_RECONNECT_GRACE_MS = 45000;
const isDebugEnabled = import.meta.env.DEV;

function debugLog(...args) {
  if (isDebugEnabled) {
    console.log(...args);
  }
}

function generateCallId() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return `call_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
}

function readPersistedCallSession() {
  if (typeof window === "undefined") return null;

  try {
    const raw = window.sessionStorage.getItem(ACTIVE_CALL_STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed?.callId || !parsed?.peer?.username) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

function writePersistedCallSession(session) {
  if (typeof window === "undefined" || !session?.callId || !session?.peer?.username) return;

  window.sessionStorage.setItem(
    ACTIVE_CALL_STORAGE_KEY,
    JSON.stringify({
      ...session,
      updatedAt: Date.now(),
    }),
  );
}

function clearPersistedCallSession() {
  if (typeof window === "undefined") return;
  window.sessionStorage.removeItem(ACTIVE_CALL_STORAGE_KEY);
}

function buildSelfInfo(currentUser) {
  const profile = typeof window !== "undefined" ? getProfileData() : { fullName: null };
  return {
    username: currentUser,
    avatar: typeof window !== "undefined" ? localStorage.getItem("app_avatar") : null,
    full_name: profile.fullName || null,
  };
}

function getMediaAccessErrorMessage(error, isVideo) {
  const message = String(error?.message || "").toLowerCase();
  const deviceLabel = isVideo ? "Mikrofon/kamera" : "Mikrofon";

  if (error?.name === "NotAllowedError" || error?.name === "PermissionDeniedError") {
    if (message.includes("dismissed")) {
      return `${deviceLabel} ruxsati oynasi yopildi. Qo'ng'iroqni qayta boshlang va ruxsat bering.`;
    }
    return `${deviceLabel} ruxsati berilmadi. Brauzer sozlamalaridan ruxsatni yoqing.`;
  }

  if (error?.name === "NotFoundError" || error?.name === "DevicesNotFoundError") {
    return `${deviceLabel} qurilmasi topilmadi.`;
  }

  if (error?.name === "NotReadableError" || error?.name === "TrackStartError") {
    return `${deviceLabel} hozir boshqa dastur tomonidan band.`;
  }

  if (error?.name === "AbortError") {
    return `${deviceLabel} ishga tushmadi. Qurilmani qayta tanlab yana urinib ko'ring.`;
  }

  return `Qo'ng'iroqni boshlashda xato: ${error?.message || "Noma'lum xato"}`;
}

function shouldFallbackToAudio(error) {
  return [
    "NotReadableError",
    "TrackStartError",
    "AbortError",
    "NotFoundError",
    "DevicesNotFoundError",
    "OverconstrainedError",
  ].includes(error?.name);
}

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
  const targetUsernameRef = useRef(null);
  const iceCandidateQueue = useRef([]);
  const remoteDescriptionSet = useRef(false);
  const isCallerRef = useRef(false);
  const isVideoRef = useRef(false);
  const callStartTimeRef = useRef(null);
  const ringtoneRef = useRef(null);
  const ringingTimeoutRef = useRef(null);
  const reconnectTimeoutRef = useRef(null);
  const callIdRef = useRef(null);
  const remoteUserRef = useRef(null);
  const callStateRef = useRef(null);

  const syncLocalTrackState = useCallback((stream, { muted = false, cameraOff = false, videoEnabled = false } = {}) => {
    if (!stream) return;
    stream.getAudioTracks().forEach((track) => {
      track.enabled = !muted;
    });
    stream.getVideoTracks().forEach((track) => {
      track.enabled = videoEnabled ? !cameraOff : false;
    });
  }, []);

  const syncRemoteTrackState = useCallback((stream) => {
    if (!stream) return;
    stream.getAudioTracks().forEach((track) => {
      track.enabled = true;
    });
    stream.getVideoTracks().forEach((track) => {
      track.enabled = true;
    });
  }, []);

  useEffect(() => {
    remoteUserRef.current = remoteUser;
  }, [remoteUser]);

  useEffect(() => {
    callStateRef.current = callState;
  }, [callState]);

  const clearRingingTimeout = useCallback(() => {
    if (ringingTimeoutRef.current) {
      clearTimeout(ringingTimeoutRef.current);
      ringingTimeoutRef.current = null;
    }
  }, []);

  const clearReconnectTimeout = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
  }, []);

  const persistCallSession = useCallback((peer = remoteUserRef.current, overrides = {}) => {
    const callId = overrides.callId || callIdRef.current;
    const peerInfo = overrides.peer || peer;
    if (!currentUser || !callId || !peerInfo?.username) return;

    writePersistedCallSession({
      username: currentUser,
      callId,
      peer: {
        username: peerInfo.username,
        avatar: peerInfo.avatar || null,
        full_name: peerInfo.full_name || null,
      },
      startedAt: overrides.startedAt ?? callStartTimeRef.current ?? null,
      isVideo: overrides.isVideo ?? isVideoRef.current,
      direction: overrides.direction || (isCallerRef.current ? "outgoing" : "incoming"),
    });
  }, [currentUser]);

  const restoreCallSession = useCallback((session) => {
    if (!session?.callId || !session?.peer?.username) return null;

    callIdRef.current = session.callId;
    targetUsernameRef.current = session.peer.username;
    isVideoRef.current = Boolean(session.isVideo);
    isCallerRef.current = session.direction === "outgoing";
    callStartTimeRef.current = session.startedAt || null;

    setRemoteUser((prev) => ({
      username: session.peer.username,
      avatar: session.peer.avatar || prev?.avatar || null,
      full_name: session.peer.full_name || prev?.full_name || null,
    }));
    setCallStartedAt(session.startedAt || null);
    setIsVideo(Boolean(session.isVideo));
    persistCallSession(session.peer, session);

    return {
      username: session.peer.username,
      avatar: session.peer.avatar || null,
      full_name: session.peer.full_name || null,
    };
  }, [persistCallSession]);

  const resetPeerConnection = useCallback(() => {
    if (pcRef.current) {
      try {
        pcRef.current.ontrack = null;
        pcRef.current.onicecandidate = null;
        pcRef.current.oniceconnectionstatechange = null;
        pcRef.current.onconnectionstatechange = null;
        pcRef.current.close();
      } catch {
        // noop
      }
    }

    pcRef.current = null;
    remoteDescriptionSet.current = false;
    iceCandidateQueue.current = [];
    remoteStreamRef.current = null;
    setRemoteStream(null);
  }, []);

  const cleanup = useCallback(() => {
    clearRingingTimeout();
    clearReconnectTimeout();
    ringtoneRef.current?.stop();
    ringtoneRef.current = null;
    resetPeerConnection();
    localStreamRef.current?.getTracks().forEach((track) => track.stop());
    localStreamRef.current = null;
    targetUsernameRef.current = null;
    isCallerRef.current = false;
    isVideoRef.current = false;
    callStartTimeRef.current = null;
    callIdRef.current = null;
    setCallStartedAt(null);
    setLocalStream(null);
    setRemoteStream(null);
    setCallState(null);
    setRemoteUser(null);
    setIncomingCall(null);
    setIsVideo(false);
    setIsMuted(false);
    setIsCameraOff(false);
    setCallError(null);
    clearPersistedCallSession();
  }, [clearReconnectTimeout, clearRingingTimeout, resetPeerConnection]);

  const prepareLocalStream = useCallback(async (videoEnabled) => {
    const currentStream = localStreamRef.current;
    const hasAudio = currentStream?.getAudioTracks().some((track) => track.readyState === "live");
    const hasVideo = currentStream?.getVideoTracks().some((track) => track.readyState === "live");

    if (currentStream && hasAudio && (!videoEnabled || hasVideo)) {
      syncLocalTrackState(currentStream, {
        muted: false,
        cameraOff: false,
        videoEnabled,
      });
      setLocalStream(currentStream);
      setIsMuted(false);
      setIsCameraOff(false);
      return currentStream;
    }

    if (currentStream) {
      currentStream.getTracks().forEach((track) => track.stop());
      localStreamRef.current = null;
    }

    const stream = await navigator.mediaDevices.getUserMedia({
      audio: AUDIO_CONSTRAINTS,
      video: videoEnabled ? VIDEO_CONSTRAINTS : false,
    });

    syncLocalTrackState(stream, {
      muted: false,
      cameraOff: false,
      videoEnabled,
    });
    localStreamRef.current = stream;
    setLocalStream(stream);
    setIsMuted(false);
    setIsCameraOff(false);
    return stream;
  }, [syncLocalTrackState]);

  const prepareNegotiationStream = useCallback(async (requestedVideo) => {
    try {
      const stream = await prepareLocalStream(requestedVideo);
      return { stream, videoEnabled: requestedVideo };
    } catch (error) {
      if (!requestedVideo || !shouldFallbackToAudio(error)) {
        throw error;
      }

      console.warn("Video source unavailable, falling back to audio call:", error);
      const stream = await prepareLocalStream(false);
      return {
        stream,
        videoEnabled: false,
        downgradedFromVideo: true,
      };
    }
  }, [prepareLocalStream]);

  const flushQueuedCandidates = useCallback(async (pc) => {
    const queued = [...iceCandidateQueue.current];
    iceCandidateQueue.current = [];

    for (const candidate of queued) {
      try {
        await pc.addIceCandidate(new RTCIceCandidate(candidate));
      } catch (err) {
        console.error("Buffered ICE candidate xato:", err);
      }
    }
  }, []);

  const syncPeerConnectionTracks = useCallback(async (stream, videoEnabled) => {
    const pc = pcRef.current;
    if (!pc || !stream) return;

    const senders = pc.getSenders();
    const audioTrack = stream.getAudioTracks()[0] || null;
    const videoTrack = videoEnabled ? stream.getVideoTracks()[0] || null : null;

    const audioSender = senders.find((sender) => sender.track?.kind === "audio");
    if (audioSender) {
      await audioSender.replaceTrack(audioTrack);
    } else if (audioTrack) {
      pc.addTrack(audioTrack, stream);
    }

    const videoSenders = senders.filter((sender) => sender.track?.kind === "video");
    if (videoTrack) {
      if (videoSenders.length > 0) {
        await videoSenders[0].replaceTrack(videoTrack);
        for (const extraSender of videoSenders.slice(1)) {
          try {
            pc.removeTrack(extraSender);
          } catch {
            // noop
          }
        }
      } else {
        pc.addTrack(videoTrack, stream);
      }
    } else {
      for (const sender of videoSenders) {
        try {
          pc.removeTrack(sender);
        } catch {
          // noop
        }
      }
    }
  }, []);

  const createPeerConnection = useCallback((targetUsername, wantsVideo = false) => {
    resetPeerConnection();

    const pc = new RTCPeerConnection(ICE_SERVERS);

    pc.ontrack = (event) => {
      const incomingTrack = event.track;
      incomingTrack.enabled = true;
      debugLog("Remote track received:", incomingTrack.kind, incomingTrack.readyState);

      if (!remoteStreamRef.current) {
        remoteStreamRef.current = new MediaStream();
      }

      const existingStream = remoteStreamRef.current;
      const sameKindTracks = existingStream
        .getTracks()
        .filter((track) => track.kind === incomingTrack.kind);
      const duplicateTrack = existingStream
        .getTracks()
        .some((track) => track.id === incomingTrack.id);

      for (const track of sameKindTracks) {
        if (track.id !== incomingTrack.id) {
          existingStream.removeTrack(track);
        }
      }

      if (!duplicateTrack) {
        existingStream.addTrack(incomingTrack);
      }

      syncRemoteTrackState(existingStream);
      setRemoteStream(new MediaStream(existingStream.getTracks()));

      incomingTrack.onmute = () => {
        if (remoteStreamRef.current) {
          setRemoteStream(new MediaStream(remoteStreamRef.current.getTracks()));
        }
      };
      incomingTrack.onunmute = () => {
        if (remoteStreamRef.current) {
          syncRemoteTrackState(remoteStreamRef.current);
          setRemoteStream(new MediaStream(remoteStreamRef.current.getTracks()));
        }
      };
      incomingTrack.onended = () => {
        if (!remoteStreamRef.current) return;
        remoteStreamRef.current.removeTrack(incomingTrack);
        setRemoteStream(new MediaStream(remoteStreamRef.current.getTracks()));
      };
    };

    pc.onicecandidate = (event) => {
      if (event.candidate && socket) {
        debugLog("ICE candidate:", event.candidate.type, event.candidate.protocol);
        socket.emit("ICE_CANDIDATE", {
          target: targetUsername,
          candidate: event.candidate,
          callId: callIdRef.current,
        });
      } else {
        debugLog("ICE gathering complete");
      }
    };

    pc.onicecandidateerror = (event) => {
      console.warn("ICE candidate error:", event);
    };

    pc.oniceconnectionstatechange = () => {
      debugLog("ICE connection state:", pc.iceConnectionState);

      if (pc.iceConnectionState === "connected" || pc.iceConnectionState === "completed") {
        clearReconnectTimeout();
        setCallError(null);
        setCallState("connected");
        callStartTimeRef.current = callStartTimeRef.current || Date.now();
        setCallStartedAt(callStartTimeRef.current);
      } else if (pc.iceConnectionState === "failed") {
        setCallState("reconnecting");
        setCallError("Ulanish xatosi — qayta ulanmoqda...");
        try {
          pc.restartIce();
        } catch (error) {
          console.error("ICE restart failed:", error);
          setCallError("Ulanib bo'lmadi. Internet yoki TURN serverni tekshiring.");
          clearReconnectTimeout();
          reconnectTimeoutRef.current = setTimeout(() => cleanup(), 3000);
        }
      } else if (pc.iceConnectionState === "disconnected") {
        setCallState("reconnecting");
        setCallError("Aloqa uzildi — qayta ulanmoqda...");
        clearReconnectTimeout();
        reconnectTimeoutRef.current = setTimeout(() => {
          setCallError("Aloqa tiklana olmadi.");
          cleanup();
        }, CALL_RECONNECT_GRACE_MS);
      }
    };

    pc.onconnectionstatechange = () => {
      debugLog("Connection state:", pc.connectionState);
      if (pc.connectionState === "failed") {
        setCallState("reconnecting");
        setCallError("Ulanish muvaffaqiyatsiz tugadi.");
      } else if (pc.connectionState === "connected") {
        clearReconnectTimeout();
        setCallError(null);
        setCallState("connected");
        callStartTimeRef.current = callStartTimeRef.current || Date.now();
        setCallStartedAt(callStartTimeRef.current);
      }
    };

    pcRef.current = pc;
    return pc;
  }, [clearReconnectTimeout, cleanup, resetPeerConnection, socket, syncRemoteTrackState]);

  const applyOfferAsAnswerer = useCallback(async ({ callId, caller, offer, nextIsVideo }) => {
    const media = await prepareNegotiationStream(nextIsVideo);
    const negotiatedVideoEnabled = media.videoEnabled;

    callIdRef.current = callId;
    targetUsernameRef.current = caller.username;
    isCallerRef.current = false;
    isVideoRef.current = negotiatedVideoEnabled;
    setRemoteUser(caller);
    setIsVideo(negotiatedVideoEnabled);
    setIncomingCall(null);
    setCallState("connecting");
    setCallError(
      media.downgradedFromVideo
        ? "Kamera ishga tushmadi, audio qo'ng'iroq qabul qilindi."
        : null,
    );
    persistCallSession(caller, {
      callId,
      peer: caller,
      isVideo: negotiatedVideoEnabled,
      direction: "incoming",
    });

    const stream = media.stream;
    const pc = createPeerConnection(caller.username, negotiatedVideoEnabled);
    stream.getTracks().forEach((track) => pc.addTrack(track, stream));

    await pc.setRemoteDescription(new RTCSessionDescription(offer));
    remoteDescriptionSet.current = true;
    await flushQueuedCandidates(pc);

    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    socket?.emit("CALL_ANSWER", {
      target: caller.username,
      answer,
      callId,
      user: buildSelfInfo(currentUser),
    });
  }, [createPeerConnection, currentUser, flushQueuedCandidates, persistCallSession, prepareNegotiationStream, socket]);

  const sendOffer = useCallback(async ({ targetUser, video = false, resume = false, callId = generateCallId() }) => {
    if (!socket || !targetUser?.username) return;

    const peer = {
      username: targetUser.username,
      avatar: targetUser.avatar || remoteUserRef.current?.avatar || null,
      full_name: targetUser.full_name || remoteUserRef.current?.full_name || null,
    };

    callIdRef.current = callId;
    targetUsernameRef.current = peer.username;
    if (!resume) {
      isCallerRef.current = true;
    }
    const media = await prepareNegotiationStream(video);
    const negotiatedVideoEnabled = media.videoEnabled;

    isVideoRef.current = negotiatedVideoEnabled;
    setRemoteUser(peer);
    setIsVideo(negotiatedVideoEnabled);
    setCallError(
      media.downgradedFromVideo
        ? "Kamera ishga tushmadi, audio qo'ng'iroqqa o'tildi."
        : null,
    );
    setCallState(resume ? "reconnecting" : "calling");
    persistCallSession(peer, {
      callId,
      peer,
      isVideo: negotiatedVideoEnabled,
      direction: resume ? (isCallerRef.current ? "outgoing" : "incoming") : "outgoing",
    });

    const stream = media.stream;
    const pc = createPeerConnection(peer.username, negotiatedVideoEnabled);
    stream.getTracks().forEach((track) => pc.addTrack(track, stream));

    const offer = await pc.createOffer({
      offerToReceiveAudio: true,
      offerToReceiveVideo: negotiatedVideoEnabled,
    });
    await pc.setLocalDescription(offer);

    socket.emit("CALL_OFFER", {
      callId,
      target: peer.username,
      caller: buildSelfInfo(currentUser),
      offer,
      isVideo: negotiatedVideoEnabled,
      resume,
    });

    if (resume) {
      clearRingingTimeout();
      return;
    }

    ringtoneRef.current?.stop();
    ringtoneRef.current = playRingtone();
    setCallState("ringing");

    clearRingingTimeout();
    ringingTimeoutRef.current = setTimeout(() => {
      debugLog("Ringing timeout — javob berilmadi");
      ringtoneRef.current?.stop();
      ringtoneRef.current = null;
      setCallError("Javob berilmadi.");
      socket.emit("CALL_END", {
        target: peer.username,
        duration: 0,
        isVideo: negotiatedVideoEnabled,
        callerUsername: currentUser,
        callId,
        reason: "timeout",
      });
      setTimeout(() => cleanup(), 2000);
    }, 30000);
  }, [cleanup, clearRingingTimeout, createPeerConnection, currentUser, persistCallSession, prepareNegotiationStream, socket]);

  useEffect(() => {
    if (!socket || !currentUser) return undefined;

    const requestSessionSync = () => {
      const persisted = readPersistedCallSession();
      if (!persisted || persisted.username !== currentUser) return;

      restoreCallSession(persisted);
      socket.emit("CALL_SESSION_SYNC_REQUEST", {
        username: currentUser,
        callId: persisted.callId,
      });
    };

    let syncTimer = null;
    const scheduleSessionSync = () => {
      if (syncTimer) {
        clearTimeout(syncTimer);
      }
      syncTimer = setTimeout(requestSessionSync, 0);
    };

    if (socket.connected) {
      scheduleSessionSync();
    }

    socket.on("connect", scheduleSessionSync);
    return () => {
      socket.off("connect", scheduleSessionSync);
      if (syncTimer) {
        clearTimeout(syncTimer);
      }
    };
  }, [currentUser, restoreCallSession, socket]);

  useEffect(() => {
    if (!socket) return undefined;

    const handleCallOffer = async (data) => {
      try {
        const nextCallId = data.callId || generateCallId();
        const caller = data.caller || { username: targetUsernameRef.current };
        const sameActiveCall = callIdRef.current && nextCallId === callIdRef.current;
        const canAutoResumeEstablishedCall =
          sameActiveCall &&
          !incomingCall &&
          (callStateRef.current === "connecting" ||
            callStateRef.current === "connected" ||
            callStateRef.current === "reconnecting");
        const shouldAutoResume =
          Boolean(data.resume) ||
          canAutoResumeEstablishedCall ||
          callStateRef.current === "reconnecting";

        if (shouldAutoResume) {
          ringtoneRef.current?.stop();
          ringtoneRef.current = null;
          await applyOfferAsAnswerer({
            callId: nextCallId,
            caller,
            offer: data.offer,
            nextIsVideo: data.isVideo,
          });
          return;
        }

        if (callStateRef.current && callIdRef.current && callIdRef.current !== nextCallId) {
          socket.emit("CALL_REJECT", {
            target: caller.username,
            isVideo: data.isVideo,
            callId: nextCallId,
          });
          return;
        }

        debugLog("CALL_OFFER keldi:", caller.username);
        setIncomingCall({
          caller,
          isVideo: data.isVideo,
          offer: data.offer,
          callId: nextCallId,
        });
        ringtoneRef.current?.stop();
        ringtoneRef.current = playRingtone();
      } catch (err) {
        console.error("CALL_OFFER handler xato:", err);
      }
    };

    const handleCallAnswer = async (data) => {
      try {
        if (data.callId && callIdRef.current && data.callId !== callIdRef.current) return;

        clearRingingTimeout();
        ringtoneRef.current?.stop();
        ringtoneRef.current = null;

        if (pcRef.current) {
          const { signalingState, currentRemoteDescription } = pcRef.current;
          const alreadyAppliedAnswer =
            currentRemoteDescription?.type === "answer" ||
            signalingState === "stable";

          if (alreadyAppliedAnswer) {
            debugLog("Duplicate CALL_ANSWER ignored:", signalingState);
            return;
          }

          if (signalingState !== "have-local-offer") {
            console.warn("CALL_ANSWER skipped due to unexpected signaling state:", signalingState);
            return;
          }

          await pcRef.current.setRemoteDescription(new RTCSessionDescription(data.answer));
          remoteDescriptionSet.current = true;
          await flushQueuedCandidates(pcRef.current);
          setCallState("connecting");
          setCallError(null);
        }
      } catch (err) {
        console.error("CALL_ANSWER handler xato:", err);
      }
    };

    const handleIceCandidate = async (data) => {
      if (!data.candidate) return;
      if (data.callId && callIdRef.current && data.callId !== callIdRef.current) return;

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

    const handleCallReject = (data) => {
      if (data.callId && callIdRef.current && data.callId !== callIdRef.current) return;
      clearRingingTimeout();
      ringtoneRef.current?.stop();
      ringtoneRef.current = null;
      cleanup();
    };

    const handleCallEnd = (data) => {
      if (data.callId && callIdRef.current && data.callId !== callIdRef.current) return;
      clearRingingTimeout();
      clearReconnectTimeout();
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
            callId: callIdRef.current,
            reason: "not_delivered",
          });
        }
        cleanup();
      }, 3000);
    };

    const handleParticipantReconnecting = ({ callId, username }) => {
      if (!callIdRef.current || callId !== callIdRef.current) return;
      if (!targetUsernameRef.current || username !== targetUsernameRef.current) return;

      setCallState("reconnecting");
      setCallError("Foydalanuvchi qayta ulanmoqda...");
      resetPeerConnection();
    };

    const handleParticipantRejoined = ({ callId, username }) => {
      if (!callIdRef.current || callId !== callIdRef.current) return;
      if (!targetUsernameRef.current || username !== targetUsernameRef.current) return;
      if (callStateRef.current === null) return;

      setCallState("reconnecting");
      setCallError("Aloqa qayta tiklanmoqda...");

      sendOffer({
        targetUser: remoteUserRef.current || { username },
        video: isVideoRef.current,
        resume: true,
        callId,
      }).catch((err) => {
        console.error("Qo'ng'iroqni tiklashda xato:", err);
        setCallError("Qo'ng'iroqni qayta ulashda xato.");
      });
    };

    const handleCallSessionSync = async (data) => {
      try {
        if (!data?.callId || !data?.peer?.username) return;

        const peer = restoreCallSession({
          callId: data.callId,
          peer: data.peer,
          startedAt: data.startedAt,
          isVideo: data.isVideo,
          direction: data.direction,
        });

        ringtoneRef.current?.stop();
        ringtoneRef.current = null;
        clearRingingTimeout();

        const isIncomingRinging = data.direction === "incoming" && data.status !== "connected";
        setCallError(data.status === "connected" ? "Aloqa tiklanmoqda..." : null);

        if (isIncomingRinging) {
          setCallState(null);
          setIncomingCall((prev) => ({
            caller: data.peer,
            isVideo: Boolean(data.isVideo),
            offer: prev?.callId === data.callId ? prev.offer : null,
            callId: data.callId,
          }));
          if (peer) {
            setRemoteUser(peer);
          }
          return;
        }

        setIncomingCall(null);
        setCallState(data.status === "connected" ? "reconnecting" : "ringing");

        await prepareLocalStream(Boolean(data.isVideo));
        if (peer) {
          setRemoteUser(peer);
        }
      } catch (err) {
        console.error("CALL_SESSION_SYNC handler xato:", err);
      }
    };

    socket.on("CALL_OFFER", handleCallOffer);
    socket.on("CALL_ANSWER", handleCallAnswer);
    socket.on("ICE_CANDIDATE", handleIceCandidate);
    socket.on("CALL_REJECT", handleCallReject);
    socket.on("CALL_END", handleCallEnd);
    socket.on("CALL_BLOCKED", handleCallBlocked);
    socket.on("CALL_NOT_DELIVERED", handleCallNotDelivered);
    socket.on("CALL_PARTICIPANT_RECONNECTING", handleParticipantReconnecting);
    socket.on("CALL_PARTICIPANT_REJOINED", handleParticipantRejoined);
    socket.on("CALL_SESSION_SYNC", handleCallSessionSync);

    return () => {
      socket.off("CALL_OFFER", handleCallOffer);
      socket.off("CALL_ANSWER", handleCallAnswer);
      socket.off("ICE_CANDIDATE", handleIceCandidate);
      socket.off("CALL_REJECT", handleCallReject);
      socket.off("CALL_END", handleCallEnd);
      socket.off("CALL_BLOCKED", handleCallBlocked);
      socket.off("CALL_NOT_DELIVERED", handleCallNotDelivered);
      socket.off("CALL_PARTICIPANT_RECONNECTING", handleParticipantReconnecting);
      socket.off("CALL_PARTICIPANT_REJOINED", handleParticipantRejoined);
      socket.off("CALL_SESSION_SYNC", handleCallSessionSync);
    };
  }, [
    applyOfferAsAnswerer,
    cleanup,
    clearReconnectTimeout,
    clearRingingTimeout,
    currentUser,
    flushQueuedCandidates,
    incomingCall,
    prepareLocalStream,
    resetPeerConnection,
    restoreCallSession,
    sendOffer,
    socket,
  ]);

  useEffect(() => {
    if (!callState || !remoteUser?.username || !callIdRef.current) return;
    persistCallSession(remoteUser, {
      callId: callIdRef.current,
      peer: remoteUser,
      isVideo: isVideoRef.current,
      startedAt: callStartTimeRef.current,
      direction: isCallerRef.current ? "outgoing" : "incoming",
    });
  }, [callState, persistCallSession, remoteUser]);

  const startCall = useCallback(async (targetUser, video = false) => {
    if (!socket || !targetUser) return;
    if (callStateRef.current || incomingCall) {
      debugLog("startCall skipped because a call session is already active");
      return;
    }

    try {
      await sendOffer({
        targetUser,
        video,
        callId: generateCallId(),
      });
    } catch (err) {
      console.error("Qo'ng'iroq boshlashda xato:", err);
      setCallError(getMediaAccessErrorMessage(err, video));
      setTimeout(() => cleanup(), 3000);
    }
  }, [cleanup, incomingCall, sendOffer, socket]);

  const acceptCall = useCallback(async () => {
    if (!incomingCall || !socket) return;
    if (callStateRef.current && callStateRef.current !== "reconnecting") {
      debugLog("acceptCall skipped because another call state is active");
      return;
    }
    if (!incomingCall.offer) {
      setCallError("Qo'ng'iroq signali hali tayyor emas. Bir ozdan keyin yana urinib ko'ring.");
      return;
    }

    ringtoneRef.current?.stop();
    ringtoneRef.current = null;

    try {
      await applyOfferAsAnswerer({
        callId: incomingCall.callId,
        caller: incomingCall.caller,
        offer: incomingCall.offer,
        nextIsVideo: incomingCall.isVideo,
      });
    } catch (err) {
      console.error("Qo'ng'iroqni qabul qilishda xato:", err);
      setCallError(getMediaAccessErrorMessage(err, incomingCall?.isVideo));
      setTimeout(() => cleanup(), 3000);
    }
  }, [applyOfferAsAnswerer, cleanup, incomingCall, socket]);

  const rejectCall = useCallback(() => {
    if (!incomingCall || !socket) return;
    ringtoneRef.current?.stop();
    ringtoneRef.current = null;
    socket.emit("CALL_REJECT", {
      target: incomingCall.caller.username,
      isVideo: incomingCall.isVideo,
      callId: incomingCall.callId,
    });
    setIncomingCall(null);
  }, [incomingCall, socket]);

  const hangUp = useCallback(() => {
    ringtoneRef.current?.stop();
    ringtoneRef.current = null;
    playCallEnd();

    const target = targetUsernameRef.current || remoteUserRef.current?.username;
    if (socket && target) {
      const duration = callStartTimeRef.current
        ? Math.round((Date.now() - callStartTimeRef.current) / 1000)
        : 0;

      socket.emit("CALL_END", {
        target,
        duration,
        isVideo: isVideoRef.current,
        callerUsername: isCallerRef.current ? currentUser : target,
        callId: callIdRef.current,
        reason: "hangup",
      });
    }

    cleanup();
  }, [cleanup, currentUser, socket]);

  const toggleMute = useCallback(() => {
    if (localStreamRef.current) {
      const nextMuted = !isMuted;
      localStreamRef.current.getAudioTracks().forEach((track) => {
        track.enabled = !nextMuted;
      });
      setIsMuted(nextMuted);
    }
  }, [isMuted]);

  const toggleCamera = useCallback(() => {
    if (localStreamRef.current) {
      const nextCameraOff = !isCameraOff;
      localStreamRef.current.getVideoTracks().forEach((track) => {
        track.enabled = !nextCameraOff;
      });
      setIsCameraOff(nextCameraOff);
    }
  }, [isCameraOff]);

  const switchCallMode = useCallback(async (nextVideoEnabled) => {
    const pc = pcRef.current;
    const target = targetUsernameRef.current || remoteUserRef.current?.username;
    if (!socket || !pc || !target || !callIdRef.current) return;
    if (!callStateRef.current || callStateRef.current === "ringing" || callStateRef.current === "calling") {
      return;
    }

    try {
      const media = await prepareNegotiationStream(nextVideoEnabled);
      const negotiatedVideoEnabled = media.videoEnabled;
      const stream = media.stream;
      await syncPeerConnectionTracks(stream, negotiatedVideoEnabled);

      if (pc.signalingState !== "stable") {
        debugLog("switchCallMode skipped due to signaling state:", pc.signalingState);
        return;
      }

      isVideoRef.current = negotiatedVideoEnabled;
      setIsVideo(negotiatedVideoEnabled);
      setIsCameraOff(false);
      setCallState("connecting");
      setCallError(
        media.downgradedFromVideo
          ? "Kamera ishga tushmadi, audio qo'ng'iroqda qoldi."
          : null,
      );
      persistCallSession(remoteUserRef.current, {
        callId: callIdRef.current,
        peer: remoteUserRef.current,
        isVideo: negotiatedVideoEnabled,
        startedAt: callStartTimeRef.current,
        direction: isCallerRef.current ? "outgoing" : "incoming",
      });

      const offer = await pc.createOffer({
        offerToReceiveAudio: true,
        offerToReceiveVideo: negotiatedVideoEnabled,
      });
      await pc.setLocalDescription(offer);

      socket.emit("CALL_OFFER", {
        callId: callIdRef.current,
        target,
        caller: buildSelfInfo(currentUser),
        offer,
        isVideo: negotiatedVideoEnabled,
        resume: true,
      });
    } catch (err) {
      console.error("Call mode switch xato:", err);
      setCallError(getMediaAccessErrorMessage(err, nextVideoEnabled));
    }
  }, [callStateRef, currentUser, persistCallSession, prepareNegotiationStream, socket, syncPeerConnectionTracks]);

  return {
    callState,
    callError,
    remoteUser,
    callStartedAt,
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
    switchCallMode,
  };
}
