import { useEffect, useRef, useState } from "react";
import { formatCallDuration } from "@/utils/formatters";
import Avatar from "@/components/common/Avatar";

export default function CallScreen({
  callState, // "calling" | "ringing" | "connecting" | "reconnecting" | "connected" | null
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
  isMuted,
  isCameraOff,
}) {
  const localVideoRef = useRef(null);
  const remoteVideoRef = useRef(null);
  const remoteAudioRef = useRef(null);
  const [duration, setDuration] = useState(0);
  const [hasRemoteVideoTrack, setHasRemoteVideoTrack] = useState(false);

  // Local video
  useEffect(() => {
    if (localVideoRef.current && localStream) {
      localVideoRef.current.srcObject = localStream;
      localVideoRef.current.muted = true;
    }
  }, [localStream]);

  // Remote audio: keep playback on dedicated <audio> for both audio/video calls
  useEffect(() => {
    if (!remoteAudioRef.current) return;

    if (!remoteStream) {
      remoteAudioRef.current.srcObject = null;
      return;
    }

    if (remoteAudioRef.current.srcObject !== remoteStream) {
      remoteAudioRef.current.srcObject = remoteStream;
    }
    remoteAudioRef.current.muted = false;
    remoteAudioRef.current.volume = 1;

    const playPromise = remoteAudioRef.current.play?.();
    if (playPromise && typeof playPromise.catch === "function") {
      playPromise.catch((err) => {
        console.warn("Remote audio autoplay blocked:", err);
      });
    }
  }, [remoteStream]);

  // Remote video: only for video calls, only update if changed
  useEffect(() => {
    if (!remoteStream || !isVideo || !remoteVideoRef.current) return;
    if (remoteVideoRef.current.srcObject !== remoteStream) {
      remoteVideoRef.current.srcObject = remoteStream;
    }
    remoteVideoRef.current.muted = true;

    const playPromise = remoteVideoRef.current.play?.();
    if (playPromise && typeof playPromise.catch === "function") {
      playPromise.catch((err) => {
        console.warn("Remote video autoplay blocked:", err);
      });
    }
  }, [remoteStream, isVideo]);

  useEffect(() => {
    if (!remoteStream || !isVideo) {
      setHasRemoteVideoTrack(false);
      return undefined;
    }

    const syncVideoState = () => {
      const videoTracks = remoteStream.getVideoTracks();
      setHasRemoteVideoTrack(
        videoTracks.some((track) => track.readyState === "live" && !track.muted),
      );
    };

    syncVideoState();
    const bindTrackListeners = () => {
      remoteStream.getVideoTracks().forEach((track) => {
        track.addEventListener("mute", syncVideoState);
        track.addEventListener("unmute", syncVideoState);
        track.addEventListener("ended", syncVideoState);
      });
    };
    const unbindTrackListeners = () => {
      remoteStream.getVideoTracks().forEach((track) => {
        track.removeEventListener("mute", syncVideoState);
        track.removeEventListener("unmute", syncVideoState);
        track.removeEventListener("ended", syncVideoState);
      });
    };

    bindTrackListeners();
    remoteStream.addEventListener?.("addtrack", syncVideoState);
    remoteStream.addEventListener?.("removetrack", syncVideoState);

    return () => {
      remoteStream.removeEventListener?.("addtrack", syncVideoState);
      remoteStream.removeEventListener?.("removetrack", syncVideoState);
      unbindTrackListeners();
    };
  }, [remoteStream, isVideo]);

  // Call duration timer
  useEffect(() => {
    if (!callState) {
      setDuration(0);
      return;
    }
    if (callState !== "connected") return undefined;

    const syncDuration = () => {
      if (!callStartedAt) {
        setDuration(0);
        return;
      }
      setDuration(Math.max(0, Math.floor((Date.now() - callStartedAt) / 1000)));
    };

    syncDuration();
    const interval = setInterval(syncDuration, 1000);
    return () => clearInterval(interval);
  }, [callStartedAt, callState]);

  if (!callState) return null;

  const showRemoteVideo = isVideo && hasRemoteVideoTrack;

  return (
    <div className="fixed inset-0 z-[100] bg-gray-900 flex flex-col">
      {/* Hidden audio element for remote voice */}
      <audio ref={remoteAudioRef} autoPlay playsInline />

      {/* Video background */}
      {showRemoteVideo ? (
        <video
          ref={remoteVideoRef}
          autoPlay
          playsInline
          muted
          className="absolute inset-0 w-full h-full object-cover"
        />
      ) : (
        <div className="absolute inset-0 bg-gradient-to-b from-gray-800 to-gray-900">
          <div className="flex h-full w-full flex-col items-center justify-center gap-5">
            <Avatar
              src={remoteUser?.avatar}
              name={remoteUser?.username}
              size={112}
            />
            {isVideo && (
              <div className="flex items-center gap-2 rounded-full bg-black/25 px-4 py-2 text-sm text-white/85">
                <i className="fas fa-video-slash text-xs" />
                <span>Kamera o'chirilgan</span>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Top info */}
      <div className="relative z-10 flex flex-col items-center pt-16 pb-8">
        {!showRemoteVideo && (
          <Avatar src={remoteUser?.avatar} name={remoteUser?.username} size={100} className="mb-4" />
        )}
        <h2 className="text-2xl font-bold text-white">{remoteUser?.username || "Noma'lum"}</h2>
        <p className="text-gray-300 mt-1">
          {callState === "calling" && "Qo'ng'iroq qilinmoqda..."}
          {callState === "ringing" && "Javob kutilmoqda..."}
          {callState === "connecting" && "Ulanmoqda..."}
          {callState === "reconnecting" && "Aloqa qayta tiklanmoqda..."}
          {callState === "connected" && formatCallDuration(duration)}
        </p>
        {callError && (
          <div className="mt-3 bg-red-500/80 text-white text-sm px-4 py-2 rounded-lg max-w-xs text-center">
            <i className="fas fa-exclamation-triangle mr-2" />
            {callError}
          </div>
        )}
      </div>

      {/* Local video (PiP) */}
      {isVideo && localStream && (
        <div className="absolute top-4 right-4 z-20 w-28 h-40 md:w-36 md:h-48 rounded-2xl overflow-hidden shadow-2xl border-2 border-white/20">
          <video
            ref={localVideoRef}
            autoPlay
            playsInline
            muted
            className={`w-full h-full object-cover ${isCameraOff ? "hidden" : ""}`}
          />
          {isCameraOff && (
            <div className="w-full h-full bg-gradient-to-b from-gray-800 to-gray-900 flex flex-col items-center justify-center gap-3">
              <Avatar
                src={localUser?.avatar}
                name={localUser?.username}
                size={56}
              />
              <i className="fas fa-video-slash text-gray-400 text-lg" />
            </div>
          )}
        </div>
      )}

      {/* Controls */}
      <div className="relative z-10 mt-auto pb-12 flex justify-center gap-6">
        {/* Mute */}
        <button
          onClick={onToggleMute}
          className={`w-14 h-14 rounded-full flex items-center justify-center transition-colors ${
            isMuted ? "bg-white text-gray-900" : "bg-white/20 text-white"
          }`}
        >
          <i className={`fas ${isMuted ? "fa-microphone-slash" : "fa-microphone"} text-xl`} />
        </button>

        {/* Camera toggle (video only) */}
        {isVideo && (
          <button
            onClick={onToggleCamera}
            className={`w-14 h-14 rounded-full flex items-center justify-center transition-colors ${
              isCameraOff ? "bg-white text-gray-900" : "bg-white/20 text-white"
            }`}
          >
            <i className={`fas ${isCameraOff ? "fa-video-slash" : "fa-video"} text-xl`} />
          </button>
        )}

        <button
          onClick={() => onSwitchCallMode?.(!isVideo)}
          className="w-14 h-14 rounded-full flex items-center justify-center transition-colors bg-white/20 text-white"
          title={isVideo ? "Audio qo'ng'iroqqa o'tish" : "Video qo'ng'iroqqa o'tish"}
        >
          <i className={`fas ${isVideo ? "fa-phone" : "fa-video"} text-xl`} />
        </button>

        {/* Hang up */}
        <button
          onClick={onHangUp}
          className="w-16 h-16 rounded-full bg-red-500 hover:bg-red-600 text-white flex items-center justify-center transition-colors"
        >
          <i className="fas fa-phone-slash text-2xl" />
        </button>
      </div>
    </div>
  );
}
