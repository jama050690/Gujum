import { useState, useEffect, useCallback } from "react";
import { useAuth } from "@/context/AuthContext";
import { useChat } from "@/context/ChatContext";
import { useSocket } from "@/context/SocketContext";
import { useWebRTC } from "@/hooks/useWebRTC";
import { fetchJSON } from "@/utils/api";

import UsersPanel from "@/components/chat/UsersPanel";
import ChatPanel from "@/components/chat/ChatPanel";
import InfoPanel from "@/components/info/InfoPanel";
import Sidebar from "@/components/layout/Sidebar";
import CallScreen from "@/components/call/CallScreen";
import IncomingCall from "@/components/call/IncomingCall";

import NewGroupModal from "@/components/modals/NewGroupModal";
import NewChannelModal from "@/components/modals/NewChannelModal";
import AddMemberModal from "@/components/modals/AddMemberModal";
import PortfolioModal from "@/components/modals/PortfolioModal";
import EditProfileModal from "@/components/modals/EditProfileModal";
import ContactsModal from "@/components/modals/ContactsModal";
import SettingsModal from "@/components/modals/SettingsModal";
import CallsModal from "@/components/modals/CallsModal";
import AddFriendModal from "@/components/modals/AddFriendModal";
import FriendRequestsModal from "@/components/modals/FriendRequestsModal";
import CommunitiesModal from "@/components/modals/CommunitiesModal";

export default function ChatPage() {
  const { user } = useAuth();
  const { activeChat, showInfoPanel, mobileView, dispatch } = useChat();
  const { socket } = useSocket();

  // Sidebar
  const [sidebarOpen, setSidebarOpen] = useState(false);

  // Modals
  const [showNewGroup, setShowNewGroup] = useState(false);
  const [showNewChannel, setShowNewChannel] = useState(false);
  const [showAddMember, setShowAddMember] = useState(false);
  const [addMemberType, setAddMemberType] = useState(null);
  const [addMemberTargetId, setAddMemberTargetId] = useState(null);
  const [showPortfolio, setShowPortfolio] = useState(false);
  const [showEditProfile, setShowEditProfile] = useState(false);
  const [showContacts, setShowContacts] = useState(false);
  const [showCommunities, setShowCommunities] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [showCalls, setShowCalls] = useState(false);
  const [showAddFriend, setShowAddFriend] = useState(false);
  const [showFriendRequests, setShowFriendRequests] = useState(false);
  const [friendRequestCount, setFriendRequestCount] = useState(0);

  // WebRTC
  const webrtc = useWebRTC(socket, user);

  // Friend request count
  const loadFriendRequestCount = useCallback(async () => {
    try {
      const data = await fetchJSON("/api/friends/requests");
      setFriendRequestCount(data.length);
    } catch {
      setFriendRequestCount(0);
    }
  }, []);

  useEffect(() => {
    if (user) loadFriendRequestCount();
  }, [user, loadFriendRequestCount]);

  useEffect(() => {
    if (!socket) return;
    const handleFriendRequest = () => {
      setFriendRequestCount((prev) => prev + 1);
    };
    const handleFriendAccepted = () => {
      loadFriendRequestCount();
    };
    socket.on("FRIEND_REQUEST", handleFriendRequest);
    socket.on("FRIEND_ACCEPTED", handleFriendAccepted);
    return () => {
      socket.off("FRIEND_REQUEST", handleFriendRequest);
      socket.off("FRIEND_ACCEPTED", handleFriendAccepted);
    };
  }, [socket, loadFriendRequestCount]);

  const handleBack = () => {
    dispatch({ type: "CLOSE_CHAT" });
  };

  const handleInfo = () => {
    dispatch({ type: "TOGGLE_INFO_PANEL" });
  };

  const handleAddMember = (type, targetId) => {
    setAddMemberType(type);
    setAddMemberTargetId(targetId);
    setShowAddMember(true);
  };

  const handleDeleteChat = async () => {
    if (!activeChat) return;
    dispatch({ type: "CLOSE_CHAT" });
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
              onAddMember={handleAddMember}
              onDelete={handleDeleteChat}
            />
          </div>
          <div className="hidden lg:flex lg:w-[360px] shrink-0 h-full">
            <InfoPanel
              chat={activeChat}
              isOnline={false}
              onClose={handleInfo}
              onOpenSidebar={() => setSidebarOpen(true)}
              onAddMember={handleAddMember}
              onDelete={handleDeleteChat}
            />
          </div>
        </>
      )}

      {/* Sidebar */}
      <Sidebar
        isOpen={sidebarOpen}
        onClose={() => setSidebarOpen(false)}
        onProfile={() => setShowPortfolio(true)}
        onFriends={() => setShowContacts(true)}
        onCommunities={() => setShowCommunities(true)}
        onNewGroup={() => setShowNewGroup(true)}
        onNewChannel={() => setShowNewChannel(true)}
        onContacts={() => setShowContacts(true)}
        onCalls={() => setShowCalls(true)}
        onSettings={() => setShowSettings(true)}
        onSavedMessages={handleOpenSavedMessages}
        onAddFriend={() => setShowAddFriend(true)}
        onFriendRequests={() => setShowFriendRequests(true)}
        friendRequestCount={friendRequestCount}
      />

      {/* Modals */}
      <NewGroupModal isOpen={showNewGroup} onClose={() => setShowNewGroup(false)} />
      <NewChannelModal isOpen={showNewChannel} onClose={() => setShowNewChannel(false)} />
      <AddMemberModal
        isOpen={showAddMember}
        onClose={() => setShowAddMember(false)}
        type={addMemberType}
        targetId={addMemberTargetId}
      />
      <PortfolioModal
        isOpen={showPortfolio}
        onClose={() => setShowPortfolio(false)}
        onEdit={() => { setShowPortfolio(false); setShowEditProfile(true); }}
      />
      <EditProfileModal isOpen={showEditProfile} onClose={() => setShowEditProfile(false)} />
      <ContactsModal isOpen={showContacts} onClose={() => setShowContacts(false)} onSelectUser={handleContactSelect} />
      <CommunitiesModal
        isOpen={showCommunities}
        onClose={() => setShowCommunities(false)}
        onSelectChat={handleContactSelect}
        onCreateGroup={() => setShowNewGroup(true)}
        onCreateChannel={() => setShowNewChannel(true)}
      />
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
      <AddFriendModal isOpen={showAddFriend} onClose={() => setShowAddFriend(false)} />
      <FriendRequestsModal isOpen={showFriendRequests} onClose={() => { setShowFriendRequests(false); loadFriendRequestCount(); }} />

      {/* Call Screen */}
      <CallScreen
        callState={webrtc.callState}
        callError={webrtc.callError}
        remoteUser={webrtc.remoteUser}
        isVideo={webrtc.isVideo}
        localStream={webrtc.localStream}
        remoteStream={webrtc.remoteStream}
        onHangUp={webrtc.hangUp}
        onToggleMute={webrtc.toggleMute}
        onToggleCamera={webrtc.toggleCamera}
        isMuted={webrtc.isMuted}
        isCameraOff={webrtc.isCameraOff}
      />

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
