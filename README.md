# Kulcskód — Flutter + Supabase starter

A repository includes an Android-capable Flutter client, Supabase SQL schema/RLS, and CI build workflow. It is intentionally **not represented as a production-ready secure messenger**: Signal Protocol session/key-store integration is not completed, so the chat UI fails closed and sending messages is disabled. No plaintext message is ever submitted by this client. The database stores a `ciphertext` field and is prepared for encrypted payloads, but a schema column name is not encryption.

## Current status

- Flutter source and Supabase client wiring: implemented; Android platform scaffolding is generated with `scripts/bootstrap_android.sh`. Not compiled in the authoring environment (Flutter/Dart SDK unavailable).
- Supabase Auth flows: implemented in client; email confirmation/password reset depend on project Auth settings.
- Username profile trigger, search RPC, direct conversation RPC, RLS, ciphertext message table, device key table: migration provided; not applied to a live project here.
- Realtime subscription to message inserts: client code provided; requires the migration and Supabase project.
- End-to-end encryption: **NOT IMPLEMENTED**. `libsignal_protocol_dart` is a possible implementation candidate, but production E2EE requires persistent Signal stores, identity/key verification, pre-key lifecycle, replay/rollback handling, and multi-device tests. Do not remove the send guard until these are implemented and reviewed.
- Push notifications: not implemented. Add a trusted server/Edge Function + FCM after secure key registration and privacy review; never send plaintext message bodies in push payloads.
- APK, two-user test, and security audit: not produced/performed in this environment.

## Prerequisites

- Flutter stable with Dart 3.4+ and Android SDK (Flutter 3.24+ recommended; package versions may require a newer SDK).
- A Supabase project.
- Android device/emulator or Android build runner.

## Configure Supabase

1. Create a Supabase project.
2. In **Authentication → Providers → Email**, enable email/password. For production, keep email confirmation enabled and configure SMTP.
3. Apply `supabase/migrations/202610230001_initial.sql` with Supabase CLI (`supabase link`, then `supabase db push`) or run it in the SQL editor.
4. In Database → Replication, confirm `messages` is included in `supabase_realtime` publication. The migration adds it; if it already exists in the publication, skip/reconcile that statement.
5. Copy the project URL and publishable/anon client key from Project Settings → API. Never use `service_role` in the mobile app.
6. Fetch dependencies and run:

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
```

For release builds:

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
```

APK path: `build/app/outputs/flutter-apk/app-release.apk`.

`.env.example` documents configuration names but is not loaded automatically; use `--dart-define` or configure equivalent CI secrets. A public Supabase client key is expected to ship in the app; RLS is the security boundary. Never put service-role credentials in app configuration.

## CI

`.github/workflows/android.yml` runs `flutter analyze`, `flutter test`, and builds an APK on pushes and pull requests. Add repository variables `SUPABASE_URL` and `SUPABASE_ANON_KEY` if you want CI to build a configured artifact. The default CI build can compile without a live backend, but it will show the setup screen.

## Data model

- `profiles`: public username/profile identity; auth user ID is the owner key.
- `conversations` and `conversation_participants`: private direct conversation membership.
- `messages`: opaque ciphertext, sender, timestamps, delivery status and idempotency key.
- `device_keys`: public identity/prekeys only; private keys must remain on-device.
- `user_blocks`, `abuse_reports`: blocking and basic abuse reporting.

RLS policies gate conversations/messages by membership. Message inserts require `sender_id = auth.uid()`. SQL column grants restrict message updates to `delivery_status`. Do not treat this starter schema as audited; review and test policies in a separate Supabase project before real use. The `profiles` table exposes usernames to signed-in users to support search.

## Security work required before real use

1. Integrate a maintained Signal Protocol implementation (candidate: [`libsignal_protocol_dart`](https://pub.dev/packages/libsignal_protocol_dart), currently a pure Dart implementation; review its license and threat model before adoption).
2. Implement durable encrypted Signal identity/session/prekey stores; private keys should be encrypted at rest with Android Keystore-backed key material, and backup/restore must not silently roll back ratchets.
3. Publish/fetch signed prekey bundles through authenticated RPC/Edge Functions; verify signatures and provide safety-number/fingerprint verification. Implement key changes and multi-device identity behavior.
4. Encrypt before writing to `messages.ciphertext`, authenticate/decrypt after receiving, and reject malformed/authentication-failing messages. Keep send disabled until all of this is tested.
5. Add idempotent delivery receipts, read receipts, block enforcement for existing conversations, rate limits, abuse-report workflow, and retention/deletion rules.
6. Add FCM through a server-side function. Push payloads should contain no message body; store tokens per device with RLS and revoke them on logout.
7. Test two real accounts/devices, offline/reconnect behavior, duplicate submissions, authorization bypass attempts, invalid ciphertext, key rotation, device loss, and account deletion. Arrange an independent security review.

## Tests and limitations

The included widget test verifies that missing configuration is disclosed. No Flutter/Dart executable was available in the creation environment, so no analyzer, test, dependency resolution, Android build, live-backend test, or E2EE test has been run. Treat this as a starter project, not a finished secure messenger or an APK delivery.
