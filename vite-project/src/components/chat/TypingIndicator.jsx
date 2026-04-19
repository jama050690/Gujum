export default function TypingIndicator({ username }) {
  if (!username) return null;

  return (
    <div className="flex items-center gap-2 px-4 py-1 text-sm text-blue-500">
      <span className="font-medium">{username}</span>
      <span>yozmoqda</span>
      <div className="flex gap-0.5">
        <span className="w-1.5 h-1.5 bg-blue-500 rounded-full animate-bounce" style={{ animationDelay: "0ms" }} />
        <span className="w-1.5 h-1.5 bg-blue-500 rounded-full animate-bounce" style={{ animationDelay: "150ms" }} />
        <span className="w-1.5 h-1.5 bg-blue-500 rounded-full animate-bounce" style={{ animationDelay: "300ms" }} />
      </div>
    </div>
  );
}
