import { useEffect, useRef, useState } from "react";
import { formatCallDuration } from "@/utils/formatters";
import Avatar from "@/components/common/Avatar";

export default function CallScreen({
  callState,
  callError,
  remoteUser, // Bu aynan qarshi taraf bo'lishi shart!
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

  // 1. Local video (O'zingizning kichik oynangiz)
  useEffect(() => {
    if (localVideoRef.current && localStream) {
      localVideoRef.current.srcObject = localStream;
      localVideoRef.current.muted = true;
    }
  }, [localStream]);

  // 2. Remote audio (Qarshi taraf ovozi)
  useEffect(() => {
    if (!remoteAudioRef.current || !remoteStream) return;
    
    if (remoteAudioRef.current.srcObject !== remoteStream) {
      remoteAudioRef.current.srcObject = remoteStream;
    }
    
    const playPromise = remoteAudioRef.current.play();
    if (playPromise !== undefined) {
      playPromise.catch(e => console.warn("Audio autoplay error:", e));
    }
  }, [remoteStream]);

  // 3. Remote video va Track holatini tekshirish
  useEffect(() => {
    if (!remoteStream) {
      setHasRemoteVideoTrack(false);
      return;
    }

    const updateVideoTrackStatus = () => {
      const videoTracks = remoteStream.getVideoTracks();
      const isActive = videoTracks.some(t => t.enabled && t.readyState === 'live');
      setHasRemoteVideoTrack(isActive);
      
      if (isActive && remoteVideoRef.current && isVideo) {
        if (remoteVideoRef.current.srcObject !== remoteStream) {
          remoteVideoRef.current.srcObject = remoteStream;
        }
      }
    };

    updateVideoTrackStatus();
    
    // Track qo'shilganda yoki holati o'zgarganda yangilash
    remoteStream.onaddtrack = updateVideoTrackStatus;
    remoteStream.onremovetrack = updateVideoTrackStatus;
    remoteStream.getVideoTracks().forEach(track => {
      track.onmute = updateVideoTrackStatus;
      track.onunmute = updateVideoTrackStatus;
    });

    return () => {
      remoteStream.onaddtrack = null;
      remoteStream.onremovetrack = null;
    };
  }, [remoteStream, isVideo]);

  // 4. Timer
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

  const showRemoteVideo = isVideo && hasRemoteVideoTrack;

  return (
    <div className="fixed inset-0 z-[100] bg-gray-900 flex flex-col overflow-hidden">
      <audio ref={remoteAudioRef} autoPlay playsInline />

      {/* Header Controls */}
      <div className="relative z-20 flex items-center justify-between px-4 pt-4">
        <div className="flex items-center gap-2">
          {canOpenMessages && (
            <button onClick={onOpenMessages} className="rounded-full bg-white/10 px-4 py-2 text-sm text-white hover:bg-white/20">
              <i className="fas fa-comments mr-2" /> Xabarlar
            </button>
          )}
          <button onClick={onOpenUsers} className="rounded-full bg-white/10 px-4 py-2 text-sm text-white hover:bg-white/20">
            <i className="fas fa-users mr-2" /> Foydalanuvchilar
          </button>
        </div>
        <button onClick={onMinimize} className="rounded-full bg-white/10 px-4 py-2 text-sm text-white hover:bg-white/20">
          <i className="fas fa-chevron-down mr-2" /> Yig'ish
        </button>
      </div>

      {/* MAIN VIEW (Qarshi taraf) */}
      <div className="absolute inset-0 z-0">
        {showRemoteVideo ? (
          <video
            ref={remoteVideoRef}
            autoPlay
            playsInline
            muted // Audio alohida elementda bo'lgani uchun
            className="h-full w-full object-cover"
          />
        ) : (
          <div className="flex h-full w-full flex-col items-center justify-center gap-6 bg-gradient-to-b from-gray-800 to-gray-900">
            <Avatar src={remoteUser?.avatar} name={remoteUser?.username || "?"} size={120} />
            <div className="text-center">
              <h2 className="text-2xl font-bold text-white">{remoteUser?.username || "Noma'lum"}</h2>
              <p className="text-gray-400 mt-2">
                {callState === "calling" && "Qo'ng'iroq qilinmoqda..."}
                {callState === "ringing" && "Javob kutilmoqda..."}
                {callState === "connecting" && "Ulanmoqda..."}
                {callState === "connected" && formatCallDuration(duration)}
              </p>
            </div>
          </div>
        )}
      </div>

      {/* PIP VIEW (Sizning kichik oynangiz) */}
      {isVideo && localStream && (
        <div className="absolute top-20 right-4 z-30 w-32 h-44 md:w-40 md:h-56 rounded-2xl overflow-hidden shadow-2xl border-2 border-white/20 bg-black">
          <div className="absolute left-2 top-2 z-10 rounded-full bg-black/50 px-2 py-0.5 text-[10px] text-white">Siz</div>
          {!isCameraOff ? (
            <video ref={localVideoRef} autoPlay playsInline muted className="h-full w-full object-cover" />
          ) : (
            <div className="flex h-full w-full items-center justify-center bg-gray-800">
              <Avatar src={localUser?.avatar} name={localUser?.username} size={50} />
            </div>
          )}
        </div>
      )}

      {/* Bottom Controls */}
      <div className="relative z-20 mt-auto pb-12 flex justify-center gap-6 bg-gradient-to-t from-black/60 to-transparent pt-10">
        <button onClick={onToggleMute} className={`w-14 h-14 rounded-full flex items-center justify-center ${isMuted ? "bg-white text-gray-900" : "bg-white/10 text-white"}`}>
          <i className={`fas ${isMuted ? "fa-microphone-slash" : "fa-microphone"} text-xl`} />
        </button>

        {isVideo && (
          <button onClick={onToggleCamera} className={`w-14 h-14 rounded-full flex items-center justify-center ${isCameraOff ? "bg-white text-gray-900" : "bg-white/10 text-white"}`}>
            <i className={`fas ${isCameraOff ? "fa-video-slash" : "fa-video"} text-xl`} />
          </button>
        )}

        <button onClick={onHangUp} className="w-16 h-16 rounded-full bg-red-500 hover:bg-red-600 text-white flex items-center justify-center shadow-lg">
          <i className="fas fa-phone-slash text-2xl" />
        </button>
      </div>
    </div>
  );
}

