# Deploying the Mataki cloud application

The first cloud-connected frontend is supplied as `index.html` in the Mataki Cloud Prospecting v1 package.

## Before publishing

1. Apply `supabase/migrations/202611060003_unvisited_status.sql` in Supabase SQL Editor. The initial schema and map-fields migrations have already been applied.
2. Upload `index.html` to the repository root on the `main` branch.
3. In GitHub repository Settings > Pages, select **Deploy from a branch**, branch `main`, folder `/(root)`, then Save.
4. Copy the published GitHub Pages URL. In Supabase Authentication > URL Configuration, set it as the Site URL and add it to Redirect URLs.
5. Confirm the Email provider is enabled under Authentication > Providers.
6. Open the published site and create the first Mataki owner account. Confirm the email if prompted, then sign in.

## First test

Create a dummy prospect, save it, refresh the page and check that the record reloads. Do not enter live customer records until this round-trip test passes.

## Security

The frontend contains the Supabase publishable key, which is intended to be public. Never commit a Supabase secret or service-role key. Keep Row Level Security enabled. Business data is stored in Supabase, not in this public repository.

## Current first-build scope

The map, OpenStreetMap building selection, prospect statuses, contact fields, cloud reload/save/delete, manual sync, and JSON backup import/export are included. Full visit history, task assignment, quote workflows, inspections and document uploads are planned follow-on modules.