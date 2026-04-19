import Avatar from "@/components/common/Avatar";

export default function IncomingCall({ caller, isVideo, onAccept, onReject }) {
  if (!caller) return null;

  return (
    <div className="fixed inset-0 z-[100] bg-black/80 backdrop-blur-md flex flex-col items-center justify-center">
      <div className="text-center animate-pulse">
        <Avatar src={caller.avatar} name={caller.username} size={100} className="mx-auto mb-4" />
        <h2 className="text-2xl font-bold text-white">{caller.username}</h2>
        <p className="text-gray-300 mt-2">
          <i className={`fas ${isVideo ? "fa-video" : "fa-phone"} mr-2`} />
          {isVideo ? "Video qo'ng'iroq" : "Audio qo'ng'iroq"}
        </p>
      </div>

      <div className="flex gap-8 mt-12">
        {/* Reject */}
        <button
          onClick={onReject}
          className="w-16 h-16 rounded-full bg-red-500 hover:bg-red-600 text-white flex items-center justify-center transition-colors shadow-lg"
        >
          <i className="fas fa-phone-slash text-2xl" />
        </button>

        {/* Accept */}
        <button
          onClick={onAccept}
          className="w-16 h-16 rounded-full bg-green-500 hover:bg-green-600 text-white flex items-center justify-center transition-colors shadow-lg animate-bounce"
        >
          <i className={`fas ${isVideo ? "fa-video" : "fa-phone"} text-2xl`} />
        </button>
      </div>
    </div>
  );
}
