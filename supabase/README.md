# Supabase setup

This repository contains Mataki's initial database migration.

## Apply the migration

1. Open the Mataki project in the Supabase Dashboard.
2. Open **SQL Editor** from the left-hand navigation.
3. Select **New query**.
4. Open the migration file in GitHub:
   `supabase/migrations/202611060001_initial_schema.sql`
5. Copy the entire file contents into the SQL Editor.
6. Click **Run** once and wait for the success message.

Run this migration only once on a new Mataki project. If it reports an error, stop and share the exact error text rather than trying to rerun parts of the script.

## Apply the map extension migration

After the initial schema succeeds, apply these two scripts in order, each in a new SQL Editor query:

1. `migrations/202611060002_prospecting_map_fields.sql`
2. `migrations/202611060003_unvisited_status.sql`

The map-fields migration adds the OpenStreetMap way reference, captured map tags, prospect priority, quote workflow status, racking estimate, visit date and follow-up date. The status migration makes **Unvisited** distinct from **Potential client** on the map. Run each once, in order.

## What the initial migration creates

- Organisations and organisation memberships
- Businesses and buildings, including map coordinates and GeoJSON building footprints
- Contacts, visits and follow-up tasks
- Quotes with GST calculations
- Inspection records and Mataki Bronze / Gold / Diamond ratings
- Document metadata for future Supabase Storage or Box integration
- Row Level Security policies that restrict records to signed-in members of their organisation

The migration also creates a `create_workspace(workspace_name)` database function. The application will call this after the first user signs in to create the Mataki workspace and make that first user its owner.

## Security notes

- The application will use the Supabase publishable (or legacy anon) key only. That key is expected to be visible in browser applications.
- Never put the Supabase `service_role` or secret key in this repository or in browser code.
- Do not disable Row Level Security.
- The current membership roles are `owner`, `admin`, and `member`. Fine-grained role permissions and invitations will be added before inviting other staff.
