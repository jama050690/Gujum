# Bootchat Flutter

Bu katalog Bootchat frontendining Flutter varianti uchun tayyorlangan.

## Nima bor

- `lib/` ichida auth, OTP, forgot-password, private chat, do'stlar, group/channel, profil va sozlamalar oqimlari mavjud.
- Backend sifatida repo ichidagi `backend/` servisi ishlatiladi.
- React frontend o'chirilmagan, Flutter app unga parallel qo'shilgan.

## Muhim cheklov

Bu ish muhiti ichida Flutter SDK `PATH` da yo'q edi, shuning uchun:

- `flutter create`
- `flutter pub get`
- `flutter run`

buyruqlari bu yerda bajarilmadi.

## Ishga tushirish

1. Flutter SDK o'rnating va `flutter` buyruq ishlashini tekshiring.
2. Shu katalog ichida platform runnerlarni yarating:

```bash
flutter create . --platforms=android,ios,web,windows
```

3. Paketlarni o'rnating:

```bash
flutter pub get
```

4. Backendni ishga tushiring:

```bash
cd ../backend
npm run dev
```

5. Flutter appni ishga tushiring:

```bash
flutter run
```

## API manzil

App ichida drawer orqali `API Base URL` ni o'zgartirish mumkin.

- Android emulator: `http://10.0.2.2:3003`
- iOS simulator / desktop: `http://127.0.0.1:3003`
- Real device: `http://<kompyuter-ip-manzili>:3003`
