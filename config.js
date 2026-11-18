/* ═══════════════════════════════════════════════════════════════
   TRADMATHS — branchement de la base du mode « Salle élèves » (facultatif)
   Conçu par Tom Rougeaud — fichier rédigé avec l’aide de Claude Opus 5.5 (Anthropic).
   1. Dans Supabase : SQL Editor › New query › collez tradmaths_salle.sql › Run.
   2. Supabase › Project Settings › API (ou bouton « Connect ») : copiez la « Project URL »
      et la clé publique « anon » (ou « publishable ») entre les guillemets ci-dessous.
   3. Enregistrez (« Commit changes » sur GitHub), attendez une minute, rechargez TradMaths.
   La clé anon / publishable est publique par conception : elle peut figurer ici.
   Ne collez JAMAIS la clé « service_role » ni une clé « secret ».
   Laissés vides, ces champs désactivent seulement le mode salle : le reste fonctionne.
═══════════════════════════════════════════════════════════════ */
var TRADMATHS_CONFIG = {
  SUPABASE_URL: "",
  SUPABASE_ANON_KEY: ""
};
