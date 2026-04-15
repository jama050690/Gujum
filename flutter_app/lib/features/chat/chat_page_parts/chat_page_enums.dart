part of '../chat_page.dart';

enum _InboxAction {
  open,
  archive,
  pin,
  mute,
  markUnread,
  clearHistory,
  deleteChat,
  block,
  reportSpam,
}

enum _MessageAction {
  reply,
  edit,
  pin,
  forward,
  delete,
  select,
}
