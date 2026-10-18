<div align="center">
<img width="1200" height="475" alt="GHBanner" src="https://ai.google.dev/static/site-assets/images/share-ais-513315318.png" />
</div>

# Run and deploy your AI Studio app

This contains everything you need to run your app locally.

View your app in AI Studio: https://ai.studio/apps/f7ccb725-525b-4d91-ad4c-e0e9ee0e8227

## Run Locally

**Prerequisites:**  [Android Studio](https://developer.android.com/studio)

1. Open Android Studio
2. Select **Open** and choose the directory containing this project
3. Allow Android Studio to fix any incompatibilities as it imports the project.
4. Create a file named `.env` in the project directory and set `GEMINI_API_KEY` in that file to your Gemini API key (see `.env.example` for an example)
5. Remove this line from the app's `build.gradle.kts` file: `signingConfig = signingConfigs.getByName("debugConfig")`
6. Run the app on an emulator or physical device
7. If you have already published your app in AI Studio, please [request upload key reset](https://support.google.com/googleplay/android-developer/answer/9842756#zippy=%2Crequest-an-upload-key-reset) in Google Play Console.

## Supabase setup

Before using email sign-in, paste and run the latest `supabase-setup.sql` in the Supabase Dashboard SQL Editor. Re-run it after app updates that add database functions; it preserves existing rows and installs the matchmaking queue, Tic-Tac-Toe turn validation/state sync, leaderboard transaction, game-result, messaging, withdrawal status/refund workflow, and policy functions. Passwords are handled by Supabase Auth and are never written to the app's profiles table. The app polls Supabase for feed, chat, leaderboard, withdrawal, and Tic-Tac-Toe match-state updates; it does not use a persistent WebSocket Realtime subscription. Matchmaking room support exists for other game types, but their move-by-move multiplayer synchronization is not implemented yet.

Withdrawal requests enter `PENDING`. In the Supabase SQL Editor, use the request ID from `public.withdrawals` to approve a request or record a completed payout:

```sql
select * from public.admin_set_withdrawal_status('WITHDRAWAL_ID', 'APPROVED');
select * from public.admin_set_withdrawal_status('WITHDRAWAL_ID', 'PAID', 'PAYOUT_REFERENCE');
```

Only Supabase database administrators or authenticated users whose trusted `app_metadata.role` is `admin` can change statuses. Statuses move from `PENDING` to `APPROVED` or `REJECTED`, then from `APPROVED` to `PAID`. Rejection refunds the debited coins automatically. The app shows the user's real requests and refreshes status approximately every five seconds.

The app integrates the official Start.io Android SDK for banner, interstitial, and rewarded video requests. Ad fill still depends on a valid app ID, an approved Start.io account, network access, and available inventory; coins are issued only from the SDK's completed-video callback. No demo campaign or simulated ad is presented as a real impression.

## Release signing

The local release upload key is stored in `my-upload-key.jks`; its signing passwords are kept in the Git-ignored `keystore.properties` file. Back up both files securely. Losing the upload key can prevent future updates from being signed with the same key.
