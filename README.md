# وين نلقاو؟ — Win Nalkaw

Arabic-first (Tunisian Arabic, RTL) and French (LTR) local-services marketplace for Tunisia. Built with React, TypeScript, Vite, Supabase/PostgreSQL and Netlify.

## What is implemented

- Responsive bilingual marketplace interface (Arabic default; French switch).
- Service search and category filters.
- Browser geolocation with permission and failure handling.
- Radius-based provider search through PostGIS when provider coordinates are saved.
- OpenStreetMap embedded map centered on the user's current location.
- Supabase email/password sign-up and sign-in.
- Provider onboarding: business, first service, staff member, opening hours and availability.
- Provider listings loaded from the database after admin approval.
- Persistent favorites for signed-in users.
- Customer quotation request persistence.
- Database-backed booking creation with server-side validation.
- Live available slots from the database based on opening hours, service duration, staff schedule, breaks, closures and existing bookings.
- Customer booking history and status actions; provider-side accept/reject/complete actions are authorized by a database RPC.
- Basic admin queue for approving unpublished businesses.
- Database migrations and Row Level Security policies.
- Netlify SPA routing and build configuration.

## External setup still required

This source package cannot create or configure third-party accounts on your behalf. Production use requires your own Supabase project and Netlify site. Transactional email, SMS/WhatsApp, online payments, business geocoding, legal terms, monitoring and production security review must be configured before public launch. A deployment is not considered production-ready until migrations and acceptance tests have run against your own staging project.

## Requirements

- Node.js 20 or newer
- npm
- Supabase project with Postgres/PostGIS support
- Netlify account for hosted deployment

## Run locally

```bash
npm install
cp .env.example .env.local
npm run dev
```

PowerShell:

```powershell
Copy-Item .env.example .env.local
npm install
npm run dev
```

The development preview may show sample cards when Supabase is not configured. Sample data is illustrative only and must not be presented as real providers or availability.

## Configure Supabase

1. Create a project at https://supabase.com/.
2. Open SQL Editor and run these files in order:
   - `supabase/migrations/001_initial_schema.sql`
   - `supabase/migrations/002_booking_and_provider_workflows.sql`
   - `supabase/migrations/003_live_availability_and_geo.sql`
3. In Project Settings → API, copy the project URL and publishable/anon key.
4. Add them to `.env.local`:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY
```

5. In Supabase Authentication → URL Configuration, add the local URL and deployed Netlify URL to allowed redirect URLs.
6. Configure email confirmation and a production SMTP provider.
7. Create a test customer and a test provider account before trying bookings.

Never put the Supabase service-role key in a `VITE_` variable or frontend code.

### Configure an administrator safely

Do not let users self-assign admin privileges. After creating the intended admin account, run a statement like the following manually in the trusted Supabase SQL Editor, replacing the email with the account you control:

```sql
insert into public.user_roles(user_id, role)
select id, 'admin'::public.app_role
from auth.users
where lower(email) = lower('admin@example.com')
on conflict do nothing;
```

The admin button appears only for an account whose database role is `admin`. Keep admin accounts protected with a strong password and MFA where available.

### Provider location

For real radius search, a provider's `businesses.location` geography point must be saved. A provider can use the homepage's location button while physically at the business before submitting onboarding; the coordinates are saved for that business. Providers without coordinates remain discoverable by text/city search but are not returned as nearby results when the customer searches using GPS.

The current OpenStreetMap embed displays the user's location area; it is not a commercial map SDK with individual provider pins. For a high-traffic production deployment, choose a supported mapping/geocoding provider and comply with its terms, quotas, and privacy rules.

## Deploy to Netlify

1. Push the `winnalkaw` folder to a Git repository.
2. In Netlify, choose **Add new site → Import an existing project**.
3. Build command: `npm run build`.
4. Publish directory: `dist`.
5. Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in Site configuration → Environment variables.
6. Deploy and add the Netlify domain to Supabase Auth redirect URLs.

`netlify.toml` contains the build and SPA fallback settings. Supabase stores persistent data; Netlify's filesystem is not used as a database.

## Booking safety

Customers submit appointments through `public.create_booking(...)`. The function checks that the business and service are published, validates business opening hours, staff schedule, closures, breaks and overlapping bookings, and writes the booking, booking item, history and notification in one transaction. The live slot list comes from `public.get_available_slots(...)`; the booking RPC checks availability again when confirming the request to prevent race conditions.

Providers and customers change booking statuses through `public.change_booking_status(...)`, which checks authorization. Do not bypass these RPCs with direct client updates.

## Pre-launch checklist

- [ ] Apply all three migrations in a clean Supabase staging project.
- [ ] Test customer signup, email confirmation, login and logout.
- [ ] Test provider onboarding and ensure new businesses are not publicly visible before approval.
- [ ] Create an admin account using the trusted SQL procedure above; approve a test business.
- [ ] Add coordinates to a test business and verify search by radius.
- [ ] Test available slots with multiple staff members, breaks, closures and existing appointments.
- [ ] Run concurrent booking attempts against the same slot; only one must succeed.
- [ ] Test cancellation, provider acceptance/rejection and completion with separate customer/provider accounts.
- [ ] Review every RLS policy with separate accounts and verify that one customer cannot read another customer's private records.
- [ ] Configure transactional email and appointment reminders.
- [ ] Select and test a payment gateway that supports your Tunisian merchant account before enabling online payment.
- [ ] Publish real Terms of Service and Privacy Policy and define data-retention rules.
- [ ] Configure backups, monitoring, error reporting, rate limits and incident recovery.
- [ ] Run `npm run build` and end-to-end tests in CI and on the deployed staging site.

## Brand

**وين نلقاو؟ — Win Nalkaw** is Tunisian dialect for “Where can we find it?”. Check trademark, domain and social-handle availability before commercial use.

## Marketplace + team + QR queue (migration 004)

The latest update adds:

- Multi-employee salon teams with weekday availability created through the server-side `add_business_staff` RPC.
- Booking QR tokens generated by the database; the QR is shown to the customer only after the booking is confirmed.
- Salon QR workflow: `check_in` (arrival), `start_service` (chair/service started), and `complete` (service finished). The server validates salon-team permissions and refreshes queue waiting estimates after scans.
- Classified ads for sale, rent, wanted items, lost/found, property, cars, spare parts and other goods. New ads are submitted as `pending` and require admin moderation before public listing.
- Local tradesperson profiles (blacksmith/metalworker, carpenter, mechanic, painter, plumber, electrician, bodywork and others). Profiles are not presented as verified until an admin verifies them.
- User-created marketplace alerts and in-app notifications when a matching listing is published. Radius matching uses coordinates when the user and listing have them; otherwise matching falls back to city.
- Admin moderation queues for listings and tradesperson verification.

### Apply database migrations

On a fresh Supabase project, apply all migrations in order:

1. `supabase/migrations/001_initial_schema.sql`
2. `supabase/migrations/002_booking_and_provider_workflows.sql`
3. `supabase/migrations/003_live_availability_and_geo.sql`
4. `supabase/migrations/004_marketplace_queue_staff.sql`

Migration 003 requires PostGIS support in Supabase. Test all migrations in a staging project before applying to production.

### QR check-in workflow

1. Customer signs in and books a real appointment.
2. Salon staff confirms the booking.
3. Customer opens **My bookings** and shows the personal QR code.
4. Authorized salon staff opens **Scanner QR**, chooses the action and scans the QR with the device camera (HTTPS required) or enters the scanned token using a USB QR scanner.
5. First scan: customer arrived. Second: service started. Third: service completed.
6. Queue wait estimates are recalculated server-side after each scan. These are estimates, not guarantees; staff should update status promptly when a service runs late.

### Marketplace moderation

A new listing is not public immediately. It remains `pending` until an administrator approves it. Configure at least one trusted admin using the project instructions and never grant admin status based on a client-side flag.

### Important production checklist

- Set the real Supabase project URL and anon key in `.env.local` and Netlify environment variables.
- Run migrations in staging first and test RLS as anonymous, customer, business owner, employee, and admin users.
- Configure Supabase Auth email templates and allowed redirect URLs.
- Use HTTPS for camera QR scanning.
- Configure transactional email/SMS separately if you need external push reminders. Current marketplace alerts are persisted as in-app notifications; external delivery requires a trusted server-side notification provider and scheduled dispatch.
- Configure an image upload bucket with size/type restrictions before accepting customer-uploaded photos. The current classifieds form accepts image URLs rather than uploading files.
- Confirm payment gateway availability and merchant approval before enabling online payments.
- Run `npm install` and `npm run build`; execute concurrent-booking and authorization tests before public launch.

## Android installation: PWA + Capacitor

This project is prepared for two Android installation paths:

1. **PWA from Netlify:** users visit the HTTPS site in Chrome and choose **Install app** or **⋮ → Add to Home screen**. The web manifest, 192/512 px icons, service worker, and in-app install prompt are included. PWA offline support is limited to the cached app shell; Supabase authentication, bookings, listings, and notifications still require internet.
2. **Native Android wrapper (APK/AAB) using Capacitor:** the Capacitor configuration and dependencies are included. Android Studio/SDK is required to generate and sign the APK; a prebuilt APK is not included in this source ZIP.

### A. Deploy the PWA to Netlify

1. Upload/push this project folder to the Git repository connected to Netlify.
2. Confirm the Netlify build settings are **Build command:** `npm run build` and **Publish directory:** `dist`.
3. In Netlify → Site configuration → Environment variables, set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` for the production deploy context.
4. Trigger **Deploys → Trigger deploy → Clear cache and deploy site** so the new manifest and service worker are published.
5. Open the deployed site in Android Chrome over HTTPS. Use the install prompt in the page when it appears, or Chrome menu **⋮ → Install app** / **Add to Home screen**. The browser controls the exact wording and eligibility display.
6. To verify, open Chrome DevTools on desktop → Application → Manifest and Service Workers, or use Lighthouse → Progressive Web App checks. After service-worker changes, clear the site's data or use the Clear cache deploy to avoid an old cached shell.

On iPhone/iPad, open the site in Safari → Share → **Add to Home Screen**. iOS does not expose the same install prompt API as Android Chrome.

### B. Build an Android APK with Capacitor (Windows)

**Install these tools first:** Node.js 20+, Android Studio, Android SDK Platform/Build Tools supported by the installed Capacitor version, and a JDK version recommended by that Android Studio release. In Android Studio SDK Manager, install the Android SDK and platform tools. Keep Android Studio and Gradle versions compatible; accept SDK licences when prompted.

Open PowerShell in the project folder (`winnalkaw`) and run:

```powershell
npm install
npm run build
npx cap add android
npx cap sync android
npx cap open android
```

- `npx cap add android` is needed only the first time and creates the `android/` native project.
- `npx cap sync android` copies the latest built web app into the native Android project and syncs native dependencies. Run it after every web-code change before rebuilding the APK.
- Android Studio opens the native project. Wait for Gradle sync to finish, connect a device with USB debugging enabled or create an emulator, then press **Run** to test.

**Create a debug APK for direct testing:** in Android Studio, choose **Build → Build Bundle(s) / APK(s) → Build APK(s)**. The APK is usually created at:

`android\app\build\outputs\apk\debug\app-debug.apk`

Copy that APK to your Android phone and open it to install. If Android blocks the installation, allow installation from that file manager/browser for this test device. Do not share a debug APK as a production release.

**Create a signed release:** in Android Studio choose **Build → Generate Signed Bundle / APK**, select **APK** for direct distribution or **Android App Bundle (AAB)** for Google Play, create and securely back up a release keystore, and finish the wizard. Never commit the keystore or passwords to Git. Google Play normally expects an AAB; APK is useful for direct testing/distribution.

**Repeat after web changes:**

```powershell
npm run build
npx cap sync android
```

Then rebuild from Android Studio. You can also use the included `npm run cap:sync` script to build the web app and sync Capacitor in one step.

### C. Supabase configuration for Android

The app calls Supabase over HTTPS from the bundled web UI. In Supabase → Authentication → URL Configuration, keep your deployed Netlify URL in the allowed redirect URLs and add this local Capacitor origin for email confirmation redirects:

`https://localhost/**`

The current sign-up flow uses `window.location.origin` as its email redirect target. Test the complete confirmation flow on a real device; if your chosen Supabase email template/provider does not return to the app correctly, configure a dedicated Capacitor deep link and matching Supabase redirect URL before public distribution. Never place the Supabase service-role key in the app.

### D. Camera/QR and permissions

The booking QR scanner uses the browser camera API. Test camera permission on a physical Android device; web camera access is secure-context-only. Capacitor's local HTTPS origin generally provides a secure context, but if camera access is denied, verify app camera permission in Android settings and review the WebView permission behavior on the target Android version. Do not enable broad storage or location permissions unless a feature requires them.

### E. Important distinction

Netlify publishes the **PWA website**. It does not compile an APK. Capacitor packages the compiled `dist` UI into an Android project, which must then be built and signed with Android tooling. Supabase remains the hosted backend for both versions.
