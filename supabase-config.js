/* ============================================================================
   WeVois Vendor Settlement Portal - connection settings
   ----------------------------------------------------------------------------
   Paste the two values from your Supabase project:
     Project Settings -> API -> Project URL      => VS_URL
     Project Settings -> API -> anon public key  => VS_ANON

   The anon key is meant to be public - it is what the browser uses, and every
   table in this database is protected by row-level policies regardless of it.
   NEVER paste the service_role key here. That one bypasses every policy.
   ========================================================================== */

window.VS_URL  = "PASTE_YOUR_PROJECT_URL_HERE";
window.VS_ANON = "PASTE_YOUR_ANON_PUBLIC_KEY_HERE";

/* Optional: shown in the top bar. */
window.VS_ORG  = "WeVois";
