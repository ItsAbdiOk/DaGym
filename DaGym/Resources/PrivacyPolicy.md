# Privacy Policy

**Last updated: 13 September 2026**

DaGym is a free, open-source strength training app. It has no accounts, no analytics, and no
ads. This page explains, in plain language, what data the app keeps and where it lives.

## What data exists

DaGym stores the training data you enter yourself: your routines, workouts, sets, reps,
weights, effort ratings, bodyweight, and progress photos. It also stores your app settings
(units, rest timer, reminders, and similar preferences).

## Where it lives

- **Your device.** All of your training data lives in a local database on your iPhone.
- **iCloud (your private database).** If you have iCloud sync turned on, that same training
  data is copied to your personal iCloud private database so it can sync across your own
  devices. This is Apple's standard CloudKit private database — only you can read it, and we
  (the developer) have no access to it.
- **Apple Health.** If you turn on Apple Health, DaGym can read your bodyweight to keep your
  training data up to date, and can write your completed workouts and bodyweight back to
  Health. This only happens if you grant permission, and you can revoke it at any time in the
  Health app or iOS Settings.
- **Progress photos.** Progress photos are stored in a separate, local-only store on your
  device. They are never included in iCloud sync and never leave your phone unless you
  explicitly share or export a photo yourself.
- **Calendar.** If you turn on Calendar sync, DaGym creates, updates, and deletes events in a
  "DaGym" calendar on your device so your scheduled workouts show up alongside the rest of your
  day. DaGym only writes to its own calendar — it does not read your other events.
- **Notifications.** If you turn on notifications, the reminders and their content (such as
  your weekly progress) are generated and scheduled entirely on your device.
- **Gym card.** If you save your gym's membership barcode, only its number and code type are
  stored, alongside your other training data. Choosing "Add to Apple Wallet" builds and signs
  the pass on your phone and hands it straight to Apple Wallet — nothing about the card is sent
  to us or to any server.

## What leaves your phone, and when

By default, **nothing leaves your phone.** DaGym has no backend server and sends nothing to us
or to any third party.

Two things can cause data to leave your device, both of which are actions you take yourself:

1. **Bring-your-own AI key.** DaGym may offer on-device AI features (Apple Foundation Models),
   which run entirely on your phone. If you choose to add your own API key for a third-party AI
   provider, the specific training data needed for that feature is sent to the provider you
   selected, under that provider's own terms. This is off by default and only happens if you
   set it up yourself. Today that means the coach chat: with your own OpenRouter key saved in
   Settings, each question you ask sends a short profile (units, goal, bodyweight, equipment),
   the conversation so far, and whatever the coach then looks up — workouts, exercise history,
   routines, schedule, records, recovery, body measurements — to OpenRouter and the model you
   picked. You are asked to agree before the first question and can revoke that agreement or
   remove the key in Settings → Coach. Your key is stored in the Keychain; chats are kept on
   your phone only and never sync through iCloud.
2. **Sharing a file.** If you export or share a routine, program, or other file yourself (for
   example, via Messages, AirDrop, or Files), that file leaves your phone because you chose to
   share it.

Aside from these two cases, and your own iCloud private database and Apple Health sync
described above, your data stays on your device.

## What we can see

We can't see any of it. DaGym has no accounts, no analytics, and no tracking. The developer has
no way to view your training data, your iCloud private database, your Apple Health data, or
your progress photos.

## How to delete everything

- Delete the app to remove all data stored on your device.
- Delete your iCloud data for DaGym from iOS Settings → your name → iCloud → Manage Account
  Storage (or Manage Storage) → DaGym, to remove the copy stored in your iCloud private
  database.
- Progress photos are removed when you delete the app, since they are never synced anywhere
  else.

## Contact

Questions about this policy or your data: mo.abdirahman99@gmail.com
