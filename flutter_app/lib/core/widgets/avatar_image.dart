import 'package:flutter/widgets.dart';

/// Avatar rasmini cheklangan o'lchamda dekodlaydi.
///
/// `NetworkImage` rasmni asl o'lchamida xotiraga ochadi: 4000×3000 lik
/// surat 40 pikselli doira uchun ham ~48 MB joy egallaydi. `ResizeImage`
/// dekodlashning o'zini cheklaydi, shuning uchun ro'yxatdagi o'nlab
/// avatarlar endi bir necha yuz kilobayt bilan cheklanadi.
const int kAvatarDecodeWidth = 160;

ImageProvider avatarImage(String url, {int width = kAvatarDecodeWidth}) {
  return ResizeImage(
    NetworkImage(url),
    width: width,
    // Balandlik null: nisbat saqlanadi.
    policy: ResizeImagePolicy.fit,
  );
}

