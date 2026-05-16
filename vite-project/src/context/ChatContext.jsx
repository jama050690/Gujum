import { createContext, useContext, useReducer } from "react";

const ChatContext = createContext(null);

const initialState = {
  users: [],
  activeChat: null,
  messages: [],
  onlineUsers: new Set(),
  lastActiveUsers: new Map(),
  typingUsers: new Map(),
  unreadMessages: new Map(),
  lastMessages: new Map(),
  showInfoPanel: false,
  mobileView: "users", // "users" | "chat"
};

function chatReducer(state, action) {
  switch (action.type) {
    case "SET_USERS":
      return { ...state, users: action.payload };
    case "SET_ACTIVE_CHAT":
      return { ...state, activeChat: action.payload, messages: [], mobileView: "chat" };
    case "CLOSE_CHAT":
      return { ...state, activeChat: null, messages: [], mobileView: "users", showInfoPanel: false };
    case "SET_MESSAGES":
      return { ...state, messages: action.payload };
    case "ADD_MESSAGE": {
      if (action.payload.id && state.messages.some(m => m.id === action.payload.id)) {
        return state;
      }
      return { ...state, messages: [...state.messages, action.payload] };
    }
    case "DELETE_MESSAGE":
      return { ...state, messages: state.messages.filter(m => m.id !== action.payload) };
    case "MARK_MESSAGES_READ":
      return { ...state, messages: state.messages.map(m => ({ ...m, read: true })) };
    case "SET_ONLINE_USERS": {
      const set = new Set();
      const lastActiveMap = new Map(state.lastActiveUsers);
      action.payload.forEach((u) => {
        if (u.online) set.add(u.username);
        if (u.lastActive) lastActiveMap.set(u.username, u.lastActive);
      });
      return { ...state, onlineUsers: set, lastActiveUsers: lastActiveMap, users: action.payload };
    }
    case "USER_STATUS_CHANGED": {
      const newSet = new Set(state.onlineUsers);
      const newLastActive = new Map(state.lastActiveUsers);
      if (action.payload.online) {
        newSet.add(action.payload.username);
      } else {
        newSet.delete(action.payload.username);
        if (action.payload.lastActive) {
          newLastActive.set(action.payload.username, action.payload.lastActive);
        }
      }
      return { ...state, onlineUsers: newSet, lastActiveUsers: newLastActive };
    }
    case "SET_TYPING": {
      const newMap = new Map(state.typingUsers);
      newMap.set(action.payload.user, Date.now());
      return { ...state, typingUsers: newMap };
    }
    case "CLEAR_TYPING": {
      const newMap = new Map(state.typingUsers);
      newMap.delete(action.payload);
      return { ...state, typingUsers: newMap };
    }
    case "SET_UNREAD": {
      const newMap = new Map(state.unreadMessages);
      newMap.set(action.payload.user, (newMap.get(action.payload.user) || 0) + 1);
      return { ...state, unreadMessages: newMap };
    }
    case "SET_UNREAD_COUNT": {
      const newMap = new Map(state.unreadMessages);
      const count = Number(action.payload.count) || 0;
      if (count > 0) newMap.set(action.payload.user, count);
      else newMap.delete(action.payload.user);
      return { ...state, unreadMessages: newMap };
    }
    case "CLEAR_UNREAD": {
      const newMap = new Map(state.unreadMessages);
      newMap.delete(action.payload);
      return { ...state, unreadMessages: newMap };
    }
    case "SET_LAST_MESSAGE": {
      const newMap = new Map(state.lastMessages);
      newMap.set(action.payload.user, action.payload.message);
      return { ...state, lastMessages: newMap };
    }
    case "CLEAR_LAST_MESSAGE": {
      const newMap = new Map(state.lastMessages);
      newMap.delete(action.payload);
      return { ...state, lastMessages: newMap };
    }
    case "SET_LAST_ACTIVE_BATCH": {
      const newLastActive = new Map(state.lastActiveUsers);
      action.payload.forEach(({ username, lastActive }) => {
        if (lastActive && !newLastActive.has(username)) {
          newLastActive.set(username, lastActive);
        }
      });
      return { ...state, lastActiveUsers: newLastActive };
    }
    case "TOGGLE_INFO_PANEL":
      return { ...state, showInfoPanel: !state.showInfoPanel };
    case "SET_MOBILE_VIEW":
      return { ...state, mobileView: action.payload };
    default:
      return state;
  }
}

export function ChatProvider({ children }) {
  const [state, dispatch] = useReducer(chatReducer, initialState);

  return (
    <ChatContext.Provider value={{ ...state, dispatch }}>
      {children}
    </ChatContext.Provider>
  );
}

export function useChat() {
  const ctx = useContext(ChatContext);
  if (!ctx) throw new Error("useChat must be used within ChatProvider");
  return ctx;
}
