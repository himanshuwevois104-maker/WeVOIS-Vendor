/* ============================================================================
   WeVois Vendor Settlement Portal - connection settings

   These two values come from Supabase: Project Settings -> API.
   The anon key is meant to be public - it is what the browser uses, and every
   table in this database is protected by row-level policies regardless of it.
   NEVER put the service_role key here. That one bypasses every policy.
   ========================================================================== */

window.VS_URL  = "https://rooqoqtliaqycscjkfxt.supabase.co";
window.VS_ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJvb3FvcXRsaWFxeWNzY2prZnh0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwNjM4OTksImV4cCI6MjEwMTYzOTg5OX0.nd4M0hFmT65KndnC1h9cLR3FljaNJviZbke-xMWUpQ0";

/* Shown in the top bar. */
window.VS_ORG  = "WeVois";
