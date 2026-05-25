import { useEffect, useRef, useState } from "react";
import { formatCallDuration } from "@/utils/formatters";
import Avatar from "@/components/common/Avatar";

export default function CallScreen({
  callState,
  remoteUser,
  localUser,
  callStartedAt,
  isVideo,
  localStream,
  remoteStream,
  onHangUp,
  onToggleMute,
  onToggleCamera,
  onSwitchCallMode,
  onMinimize,
  onOpenMessages,
  onOpenUsers,
  canOpenMessages,
  isMuted,
  isCameraOff,
}) {
  const localVideoRef = useRef(null);
  const remoteVideoRef = useRef(null);
  const remoteAudioRef = useRef(null);
  const [duration, setDuration] = useState(0);
  const [hasRemoteVideoTrack, setHasRemoteVideoTrack] = useState(false);

  // 1. Local Video ulanishi
  useEffect(() => {
    if (localVideoRef.current && localStream && !isCameraOff) {
      localVideoRef.current.srcObject = localStream;
    }
  }, [localStream, isCameraOff, isVideo]);

  // 2. Remote Audio ulanishi
  useEffect(() => {
    if (!remoteAudioRef.current || !remoteStream) return;
    const audio = remoteAudioRef.current;
    audio.srcObject = remoteStream;

    const tryPlay = () => {
      if (audio.paused && audio.srcObject) {
        audio.play().catch(e => {
          if (e.name !== 'AbortError') {
            console.warn("Audio play error:", e.name, e.message);
          }
        });
      }
    };

    tryPlay();

    const tracks = remoteStream.getAudioTracks();
    tracks.forEach(t => t.addEventListener('unmute', tryPlay));
    return () => tracks.forEach(t => t.removeEventListener('unmute', tryPlay));
  }, [remoteStream]);

  // 2.5. ICE connected bo'lganda audio qayta urinish
  useEffect(() => {
    if (callState !== 'connected' || !remoteAudioRef.current?.srcObject) return;
    const audio = remoteAudioRef.current;
    if (audio.paused) {
      audio.play().catch(e => {
        if (e.name !== 'AbortError') console.warn("Audio retry:", e.name);
      });
    }
  }, [callState]);

  // 3. Remote Video ulanishi va Tracklarni kuzatish
  useEffect(() => {
    if (!remoteStream) {
      setHasRemoteVideoTrack(false);
      return;
    }

    const checkTracks = () => {
      const videoTracks = remoteStream.getVideoTracks();
      const hasActiveVideo = videoTracks.some(t => t.enabled && t.readyState === 'live');
      setHasRemoteVideoTrack(hasActiveVideo);
    };

    checkTracks();

    remoteStream.onaddtrack = checkTracks;
    remoteStream.onremovetrack = checkTracks;

    const trackInterval = setInterval(checkTracks, 1000);

    return () => {
      remoteStream.onaddtrack = null;
      remoteStream.onremovetrack = null;
      clearInterval(trackInterval);
    };
  }, [remoteStream]);

  // 4. Video element mount bo'lganda srcObject ni darhol o'rnatish
  useEffect(() => {
    if (hasRemoteVideoTrack && isVideo && remoteVideoRef.current && remoteStream) {
      if (remoteVideoRef.current.srcObject !== remoteStream) {
        remoteVideoRef.current.srcObject = remoteStream;
      }
    }
  }, [hasRemoteVideoTrack, isVideo, remoteStream]);

  // 4. Qo'ng'iroq davomiyligi (Taymer)
  useEffect(() => {
    if (callState !== "connected" || !callStartedAt) {
      setDuration(0);
      return;
    }
    const interval = setInterval(() => {
      setDuration(Math.floor((Date.now() - callStartedAt) / 1000));
    }, 1000);
    return () => clearInterval(interval);
  }, [callStartedAt, callState]);

  if (!callState) return null;

  return (
    <div className="fixed inset-0 z-[100] bg-gray-900 flex flex-col overflow-hidden text-white font-sans select-none">
      <audio ref={remoteAudioRef} autoPlay playsInline />

      {/* Header */}
      <div className="relative z-20 flex items-center justify-between px-6 pt-6">
        <div className="flex items-center gap-3">
          {canOpenMessages && (
            <button onClick={onOpenMessages} className="rounded-full bg-white/10 p-3 hover:bg-white/20 transition-all active:scale-90">
              <i className="fas fa-comments text-lg" />
            </button>
          )}
          <button onClick={onOpenUsers} className="rounded-full bg-white/10 p-3 hover:bg-white/20 transition-all active:scale-90">
            <i className="fas fa-users text-lg" />
          </button>
        </div>

        <div className="text-center">
            <p className="text-[10px] uppercase tracking-[0.2em] text-blue-400 font-bold mb-1">
                {callState === "connected" ? "Aloqada" : "Ulanmoqda..."}
            </p>
            {callState === "connected" && (
                <p className="text-xl font-mono font-medium drop-shadow-lg">
                    {formatCallDuration(duration)}
                </p>
            )}
        </div>

        <button onClick={onMinimize} className="rounded-full bg-white/10 px-4 py-2 text-sm hover:bg-white/20 transition-all flex items-center gap-2 border border-white/5 active:scale-95">
          <i className="fas fa-compress-alt" /> <span>Yig'ish</span>
        </button>
      </div>

      {/* Main View Area */}
      <div className="absolute inset-0 z-0 bg-black">
        {isVideo && hasRemoteVideoTrack ? (
          <video
            ref={remoteVideoRef}
            autoPlay
            playsInline
            className="h-full w-full object-cover transition-opacity duration-500"
          />
        ) : (
          <div className="flex h-full w-full flex-col items-center justify-center gap-8 bg-gradient-to-b from-gray-800 to-gray-950">
            <div className="relative">
                <div className="absolute inset-0 bg-blue-500/20 blur-3xl rounded-full animate-pulse"></div>
                <Avatar src={remoteUser?.avatar} name={remoteUser?.username || "?"} size={160} className="relative z-10 border-4 border-white/10 shadow-2xl" />
            </div>
            <div className="text-center z-10 px-6">
              <h2 className="text-3xl md:text-4xl font-bold tracking-tight">{remoteUser?.full_name || remoteUser?.username || "Noma'lum"}</h2>
              <p className="text-gray-400 text-lg mt-2">@{remoteUser?.username}</p>
              {callState !== "connected" && (
                <div className="mt-6 flex items-center justify-center gap-2 text-blue-400 font-medium italic">
                    <span className="w-2 h-2 bg-blue-500 rounded-full animate-bounce" style={{animationDelay: '0ms'}}></span>
                    <span className="w-2 h-2 bg-blue-500 rounded-full animate-bounce" style={{animationDelay: '200ms'}}></span>
                    <span className="w-2 h-2 bg-blue-500 rounded-full animate-bounce" style={{animationDelay: '400ms'}}></span>
                </div>
              )}
            </div>
          </div>
        )}
      </div>

      {/* Local Video Preview (PiP) */}
      {isVideo && localStream && (
        <div className={`absolute top-24 right-6 z-30 w-32 h-44 md:w-48 md:h-64 rounded-2xl overflow-hidden shadow-2xl border-2 border-white/20 bg-gray-900 transition-all duration-300 transform ${isCameraOff ? 'scale-90 opacity-80' : 'scale-100 opacity-100'}`}>
          {!isCameraOff ? (
            <video ref={localVideoRef} autoPlay playsInline muted className="h-full w-full object-cover -scale-x-100" />
          ) : (
            <div className="flex h-full w-full items-center justify-center bg-gray-800">
              <Avatar src={localUser?.avatar} name={localUser?.username} size={60} />
            </div>
          )}
        </div>
      )}

      {/* Bottom Controls */}
      <div className="relative z-20 mt-auto pb-12 flex justify-center items-center gap-4 md:gap-8 bg-gradient-to-t from-black/80 via-black/40 to-transparent pt-24 px-4">

        {/* Mikrofon */}
        <button
            onClick={onToggleMute}
            className={`w-14 h-14 md:w-16 md:h-16 rounded-full flex items-center justify-center transition-all shadow-lg active:scale-90 ${isMuted ? "bg-red-500 text-white" : "bg-white/10 text-white hover:bg-white/20 border border-white/10"}`}
            title={isMuted ? "Ovozni yoqish" : "Ovozni o'chirish"}
        >
          <i className={`fas ${isMuted ? "fa-microphone-slash" : "fa-microphone"} text-xl`} />
        </button>

        {/* Videoga o'tish (faqat audio rejimida) */}
        {!isVideo && (
            <button
                onClick={() => onSwitchCallMode?.()}
                className="w-14 h-14 md:w-16 md:h-16 rounded-full flex items-center justify-center bg-white/10 text-white hover:bg-white/20 transition-all border border-white/10 shadow-lg active:scale-90"
                title="Videoga o'tish"
            >
                <i className="fas fa-video text-xl" />
            </button>
        )}

        {/* Kamerani yoqish/o'chirish (faqat video rejimida) */}
        {isVideo && (
            <button
                onClick={onToggleCamera}
                className={`w-14 h-14 md:w-16 md:h-16 rounded-full flex items-center justify-center transition-all shadow-lg active:scale-90 ${isCameraOff ? "bg-red-500 text-white" : "bg-white/10 text-white hover:bg-white/20 border border-white/10"}`}
                title={isCameraOff ? "Kamerani yoqish" : "Kamerani o'chirish"}
            >
                <i className={`fas ${isCameraOff ? "fa-video-slash" : "fa-video"} text-xl`} />
            </button>
        )}

        {/* Yakunlash */}
        <button
            onClick={onHangUp}
            className="w-16 h-16 md:w-20 md:h-20 rounded-full bg-red-600 hover:bg-red-700 text-white flex items-center justify-center shadow-2xl transition-all active:scale-75 ring-4 ring-red-600/20"
            title="Qo'ng'iroqni tugatish"
        >
          <i className="fas fa-phone-slash text-2xl md:text-3xl" />
        </button>
      </div>
    </div>
  );
}
