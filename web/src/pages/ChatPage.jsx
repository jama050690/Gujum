import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "@/context/AuthContext";
import { useLanguage } from "@/context/LanguageContext";
import { useChat } from "@/context/ChatContext";
import { useSocket } from "@/context/SocketContext";
import { useWebRTC } from "@/hooks/useWebRTC";

import UsersPanel from "@/components/chat/UsersPanel";
import ChatPanel from "@/components/chat/ChatPanel";
import InfoPanel from "@/components/info/InfoPanel";
import Sidebar from "@/components/layout/Sidebar";
import CallScreen from "@/components/call/CallScreen";
import IncomingCall from "@/components/call/IncomingCall";

import ProfileModal from "@/components/modals/ProfileModal";
import EditProfileModal from "@/components/modals/EditProfileModal";
import ContactsModal from "@/components/modals/ContactsModal";
import SettingsModal from "@/components/modals/SettingsModal";
import CallsModal from "@/components/modals/CallsModal";
import Avatar from "@/components/common/Avatar";

export default function ChatPage() {
  const { user } = useAuth();
  const { lang } = useLanguage();
  const { activeChat, showInfoPanel, mobileView, dispatch } = useChat();
  const { socket } = useSocket();
  const navigate = useNavigate();

  // Sidebar
  const [sidebarOpen, setSidebarOpen] = useState(false);

  // Modals
  const [showProfileModal, setShowProfileModal] = useState(false);
  const [showEditProfile, setShowEditProfile] = useState(false);
  const [showContacts, setShowContacts] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [showCalls, setShowCalls] = useState(false);
  const [isCallMinimized, setIsCallMinimized] = useState(false);

  // WebRTC
  const webrtc = useWebRTC(socket, user);

  const handleBack = () => {
    dispatch({ type: "CLOSE_CHAT" });
  };

  const handleInfo = () => {
    dispatch({ type: "TOGGLE_INFO_PANEL" });
  };

  const handleCall = (targetUser) => {
    webrtc.startCall(targetUser, false);
  };

  const handleVideoCall = (targetUser) => {
    webrtc.startCall(targetUser, true);
  };

  const handleContactSelect = (contact) => {
    dispatch({ type: "SET_ACTIVE_CHAT", payload: contact });
  };

  const hasActiveCallScreen = Boolean(webrtc.callState);

  useEffect(() => {
    if (webrtc.callState || webrtc.incomingCall) {
      setIsCallMinimized(false);
    }
  }, [webrtc.callState, webrtc.incomingCall]);

  const handleOpenMessagesFromCall = () => {
    if (!activeChat) return;
    dispatch({ type: "SET_MOBILE_VIEW", payload: "chat" });
    setIsCallMinimized(true);
  };

  const handleOpenUsersFromCall = () => {
    dispatch({ type: "SET_MOBILE_VIEW", payload: "users" });
    setIsCallMinimized(true);
  };

  const handleOpenSavedMessages = () => {
    dispatch({
      type: "SET_ACTIVE_CHAT",
      payload: {
        username: "__SAVED_MESSAGES__",
        type: "saved",
        online: true,
      },
    });
  };

  return (
    <div className="h-[100dvh] min-h-[100dvh] flex bg-white dark:bg-[#0e1621] overflow-hidden">
      {/* Users Panel */}
      <div
        className={`${
          mobileView === "users" || !activeChat ? "flex" : "hidden"
        } md:flex w-full md:w-[320px] lg:w-[360px] flex-col h-full shrink-0 border-r border-gray-200 dark:border-gray-700`}
      >
        <UsersPanel onOpenSidebar={() => setSidebarOpen(true)} />
      </div>

      {/* Chat Panel */}
      <div
        className={`${
          mobileView === "chat" && activeChat ? "flex" : "hidden"
        } md:flex flex-1 flex-col h-full min-w-0 min-h-0`}
      >
        <ChatPanel
          onBack={handleBack}
          onOpenSidebar={() => setSidebarOpen(true)}
          onInfo={handleInfo}
          onCall={handleCall}
          onVideoCall={handleVideoCall}
        />
      </div>

      {/* Info Panel */}
      {showInfoPanel && activeChat && (
        <>
          <button
            type="button"
            onClick={handleInfo}
            className="lg:hidden fixed inset-0 z-40 bg-black/40"
            aria-label="Close info panel overlay"
          />
          <div className="fixed lg:hidden inset-y-0 right-0 z-50 w-full sm:w-[360px]">
            <InfoPanel
              chat={activeChat}
              isOnline={false}
              onClose={handleInfo}
              onOpenSidebar={() => setSidebarOpen(true)}
            />
          </div>
          <div className="hidden lg:flex lg:w-[360px] shrink-0 h-full">
            <InfoPanel
              chat={activeChat}
              isOnline={false}
              onClose={handleInfo}
              onOpenSidebar={() => setSidebarOpen(true)}
            />
          </div>
        </>
      )}

      {/* Sidebar */}
      <Sidebar
        isOpen={sidebarOpen}
        onClose={() => setSidebarOpen(false)}
        onProfile={() => setShowProfileModal(true)}
        onContacts={() => setShowContacts(true)}
        onCalls={() => setShowCalls(true)}
        onSettings={() => setShowSettings(true)}
        onSavedMessages={handleOpenSavedMessages}
        onAdminDashboard={() => navigate(`/${lang}/admin`)}
      />

      {/* Modals */}
      <ProfileModal
        isOpen={showProfileModal}
        onClose={() => setShowProfileModal(false)}
        onEdit={() => { setShowProfileModal(false); setShowEditProfile(true); }}
      />
      <EditProfileModal isOpen={showEditProfile} onClose={() => setShowEditProfile(false)} />
      <ContactsModal isOpen={showContacts} onClose={() => setShowContacts(false)} onSelectUser={handleContactSelect} />
      <SettingsModal isOpen={showSettings} onClose={() => setShowSettings(false)} />
      <CallsModal
        isOpen={showCalls}
        onClose={() => setShowCalls(false)}
        onStartCall={(targetUser) => {
          if (!targetUser) return;
          setShowCalls(false);
          handleCall(targetUser);
        }}
      />

      {/* Call Screen */}
      {hasActiveCallScreen && !isCallMinimized && (
        <CallScreen
          callState={webrtc.callState}
          callError={webrtc.callError}
          remoteUser={webrtc.remoteUser}
          localUser={user}
          callStartedAt={webrtc.callStartedAt}
          isVideo={webrtc.isVideo}
          localStream={webrtc.localStream}
          remoteStream={webrtc.remoteStream}
          onHangUp={webrtc.hangUp}
          onToggleMute={webrtc.toggleMute}
          onToggleCamera={webrtc.toggleCamera}
          onSwitchCallMode={webrtc.switchCallMode}
          onMinimize={() => setIsCallMinimized(true)}
          onOpenMessages={handleOpenMessagesFromCall}
          onOpenUsers={handleOpenUsersFromCall}
          canOpenMessages={Boolean(activeChat)}
          isMuted={webrtc.isMuted}
          isCameraOff={webrtc.isCameraOff}
        />
      )}

      {hasActiveCallScreen && isCallMinimized && (
        <button
          type="button"
          onClick={() => setIsCallMinimized(false)}
          className="fixed bottom-5 right-5 z-[100] flex items-center gap-3 rounded-full bg-gray-900/95 px-4 py-3 text-left text-white shadow-2xl ring-1 ring-white/10 backdrop-blur"
        >
          <div className="relative">
            <span className="absolute -inset-1 rounded-full bg-green-500/30" />
            <Avatar
              src={webrtc.remoteUser?.avatar}
              name={webrtc.remoteUser?.username || "Call"}
              size={40}
              className="relative"
            />
          </div>
          <div className="min-w-0">
            <div className="truncate text-sm font-semibold">
              {webrtc.remoteUser?.username || "Qo'ng'iroq"}
            </div>
            <div className="text-xs text-white/70">
              {webrtc.callState === "connected" ? "Qo'ng'iroq davom etmoqda" : "Qo'ng'iroq ochiq"}
            </div>
          </div>
          <i className="fas fa-up-right-and-down-left-from-center text-sm text-white/70" />
        </button>
      )}

      {/* Incoming Call */}
      <IncomingCall
        caller={webrtc.incomingCall?.caller}
        isVideo={webrtc.incomingCall?.isVideo}
        onAccept={webrtc.acceptCall}
        onReject={webrtc.rejectCall}
      />
    </div>
  );
}
