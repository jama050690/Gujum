import { useEffect, useRef, useState } from "react";
import { formatCallDuration } from "@/utils/formatters";
import Avatar from "@/components/common/Avatar";

export default function CallScreen({
  callState,
  callError,
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

  useEffect(() => {
    if (localVideoRef.current && localStream) {
      localVideoRef.current.srcObject = localStream;
      localVideoRef.current.muted = true;
    }
  }, [localStream]);

  useEffect(() => {
    if (!remoteAudioRef.current || !remoteStream) return;
    if (remoteAudioRef.current.srcObject !== remoteStream) {
      remoteAudioRef.current.srcObject = remoteStream;
    }
    remoteAudioRef.current.play().catch(e => console.warn("Audio play error:", e));
  }, [remoteStream]);

  useEffect(() => {
    if (!remoteStream) {
      setHasRemoteVideoTrack(false);
      return;
    }
    const updateTrack = () => {
      const active = remoteStream.getVideoTracks().some(t => t.enabled && t.readyState === 'live');
      setHasRemoteVideoTrack(active);
      if (active && remoteVideoRef.current && isVideo) {
        remoteVideoRef.current.srcObject = remoteStream;
      }
    };
    updateTrack();
    remoteStream.onaddtrack = updateTrack;
    remoteStream.onremovetrack = updateTrack;
  }, [remoteStream, isVideo]);

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
    <div className="fixed inset-0 z-[100] bg-gray-900 flex flex-col overflow-hidden text-white font-sans">
      <audio ref={remoteAudioRef} autoPlay playsInline />

      {/* Header */}
      <div className="relative z-20 flex items-center justify-between px-4 pt-4">
        <div className="flex items-center gap-2">
          {canOpenMessages && (
            <button onClick={onOpenMessages} className="rounded-full bg-white/10 px-4 py-2 text-sm hover:bg-white/20 transition-all">
              <i className="fas fa-comments mr-2" /> Xabarlar
            </button>
          )}
          <button onClick={onOpenUsers} className="rounded-full bg-white/10 px-4 py-2 text-sm hover:bg-white/20 transition-all">
            <i className="fas fa-users mr-2" /> Userlar
          </button>
        </div>
        <button onClick={onMinimize} className="rounded-full bg-white/10 px-4 py-2 text-sm hover:bg-white/20 transition-all">
          <i className="fas fa-chevron-down mr-2" /> Yig'ish
        </button>
      </div>

      {/* Main View */}
      <div className="absolute inset-0 z-0">
        {isVideo && hasRemoteVideoTrack ? (
          <video ref={remoteVideoRef} autoPlay playsInline muted className="h-full w-full object-cover" />
        ) : (
          <div className="flex h-full w-full flex-col items-center justify-center gap-6 bg-gradient-to-b from-gray-800 to-gray-900">
            <Avatar src={remoteUser?.avatar} name={remoteUser?.username || "?"} size={120} />
            <div className="text-center">
              <h2 className="text-2xl font-bold">{remoteUser?.username || "Noma'lum"}</h2>
              <p className="text-gray-400 mt-2">
                {callState === "connected" ? formatCallDuration(duration) : "Ulanmoqda..."}
              </p>
            </div>
          </div>
        )}
      </div>

      {/* PiP (Small Window) */}
      {isVideo && localStream && (
        <div className="absolute top-20 right-4 z-30 w-32 h-44 md:w-40 md:h-56 rounded-2xl overflow-hidden shadow-2xl border-2 border-white/20 bg-black">
          {!isCameraOff ? (
            <video ref={localVideoRef} autoPlay playsInline muted className="h-full w-full object-cover" />
          ) : (
            <div className="flex h-full w-full items-center justify-center bg-gray-800">
              <Avatar src={localUser?.avatar} name={localUser?.username} size={50} />
            </div>
          )}
        </div>
      )}

      {/* Controls */}
      <div className="relative z-20 mt-auto pb-12 flex justify-center gap-6 bg-gradient-to-t from-black/80 to-transparent pt-12">
        <button onClick={onToggleMute} className={`w-14 h-14 rounded-full flex items-center justify-center transition-all ${isMuted ? "bg-white text-gray-900" : "bg-white/10 text-white hover:bg-white/20"}`}>
          <i className={`fas ${isMuted ? "fa-microphone-slash" : "fa-microphone"} text-xl`} />
        </button>

        {/* REJIMNI ALMASHTIRISH TUGMASI (DOIM KO'RINADI) */}
        <button onClick={() => onSwitchCallMode?.(!isVideo)} className="w-14 h-14 rounded-full flex items-center justify-center bg-white/10 text-white hover:bg-white/20 transition-all border border-white/10">
          <i className={`fas ${isVideo ? "fa-phone" : "fa-video"} text-xl`} />
        </button>

        {isVideo && (
          <button onClick={onToggleCamera} className={`w-14 h-14 rounded-full flex items-center justify-center transition-all ${isCameraOff ? "bg-white text-gray-900" : "bg-white/10 text-white hover:bg-white/20"}`}>
            <i className={`fas ${isCameraOff ? "fa-video-slash" : "fa-video"} text-xl`} />
          </button>
        )}

        <button onClick={onHangUp} className="w-16 h-16 rounded-full bg-red-500 hover:bg-red-600 text-white flex items-center justify-center shadow-lg transition-transform active:scale-90">
          <i className="fas fa-phone-slash text-2xl" />
        </button>
      </div>
    </div>
  );
}