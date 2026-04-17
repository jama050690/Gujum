# Bootchat Flutter

Bu katalog Bootchat frontendining Flutter varianti uchun tayyorlangan.

## Nima bor

- `lib/` ichida auth, OTP, forgot-password, private chat, do'stlar, group/channel, profil va sozlamalar oqimlari mavjud.
- Backend sifatida repo ichidagi `backend/` servisi ishlatiladi.
- React frontend o'chirilmagan, Flutter app unga parallel qo'shilgan.

## Muhim cheklov

Bu ish muhiti ichida Flutter SDK `PATH` da yo'q edi, shuning uchun yakuniy
`flutter analyze` va `flutter build` tekshiruvlari shu kompyuterda terminaldan
bajarilmadi.

## Ishga tushirish

1. Flutter SDK o'rnating va `flutter` buyruq ishlashini tekshiring.
2. Paketlarni o'rnating:

```bash
flutter pub get
```

3. Backendni ishga tushiring:

```bash
cd ../backend
npm run dev
```

4. Flutter appni debug rejimda ishga tushiring:

```bash
flutter run
```

5. Android telefon uchun kichik release APK larni yig'ing:

```bash
flutter build apk --release --split-per-abi
```

Bu build ikki alohida APK beradi:

- `app-armeabi-v7a-release.apk`
- `app-arm64-v8a-release.apk`

Shu usul bilan APK hajmi odatda 50 MB dan ancha kichik bo'ladi.
Android minimum versiyasi: 6.0+ (`minSdk 23`).

## API manzil

App ichida drawer orqali `API Base URL` ni o'zgartirish mumkin.

- Android emulator: `http://10.0.2.2:4000`
- iOS simulator / desktop: `http://127.0.0.1:4000`
- Real device: `http://<kompyuter-ip-manzili>:4000`
