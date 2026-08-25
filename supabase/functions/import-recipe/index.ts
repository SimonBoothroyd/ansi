// Edge function: import-recipe.
// Orchestrates the pipeline (import-and-matching.md §3): extract → normalize →
// match cascade → return a reconciliation payload the app renders.
//
// STUB — returns 501 until built (roadmap step 8). Wiring shape only.

Deno.serve((_req: Request) => {
  return new Response(
    JSON.stringify({ error: "import-recipe not implemented (roadmap step 8)" }),
    { status: 501, headers: { "content-type": "application/json" } },
  );
});
