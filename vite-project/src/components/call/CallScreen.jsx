import { useEffect, useRef, useState } from "react";
import { formatCallDuration } from "@/utils/formatters";
import Avatar from "@/components/common/Avatar";

export default function CallScreen({
  callState, // "calling" | "ringing" | "connecting" | "connected" | null
  callError,
  remoteUser,
  isVideo,
  localStream,
  remoteStream,
  onHangUp,
  onToggleMute,
  onToggleCamera,
  isMuted,
  isCameraOff,
}) {
  const localVideoRef = useRef(null);
  const remoteVideoRef = useRef(null);
  const remoteAudioRef = useRef(null);
  const [duration, setDuration] = useState(0);

  // Local video
  useEffect(() => {
    if (localVideoRef.current && localStream) {
      localVideoRef.current.srcObject = localStream;
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
  }, [remoteStream, isVideo]);

  // Call duration timer
  useEffect(() => {
    if (callState !== "connected") {
      setDuration(0);
      return;
    }
    const interval = setInterval(() => setDuration((d) => d + 1), 1000);
    return () => clearInterval(interval);
  }, [callState]);

  if (!callState) return null;

  return (
    <div className="fixed inset-0 z-[100] bg-gray-900 flex flex-col">
      {/* Hidden audio element for remote voice */}
      <audio ref={remoteAudioRef} autoPlay playsInline />

      {/* Video background */}
      {isVideo && remoteStream ? (
        <video
          ref={remoteVideoRef}
          autoPlay
          playsInline
          muted
          className="absolute inset-0 w-full h-full object-cover"
        />
      ) : (
        <div className="absolute inset-0 bg-gradient-to-b from-gray-800 to-gray-900" />
      )}

      {/* Top info */}
      <div className="relative z-10 flex flex-col items-center pt-16 pb-8">
        {(!isVideo || !remoteStream) && (
          <Avatar src={remoteUser?.avatar} name={remoteUser?.username} size={100} className="mb-4" />
        )}
        <h2 className="text-2xl font-bold text-white">{remoteUser?.username || "Noma'lum"}</h2>
        <p className="text-gray-300 mt-1">
          {callState === "calling" && "Qo'ng'iroq qilinmoqda..."}
          {callState === "ringing" && "Javob kutilmoqda..."}
          {callState === "connecting" && "Ulanmoqda..."}
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
            <div className="w-full h-full bg-gray-800 flex items-center justify-center">
              <i className="fas fa-video-slash text-gray-500 text-xl" />
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
