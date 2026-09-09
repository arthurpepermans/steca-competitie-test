import { supabase } from "./supabase";
import type { Match, Standing, Team } from "./types";

export type SupportersData = {
  matches: Match[];
  klassement: Standing[];
  ploegen: Pick<Team, "ploegid" | "naam" | "reeks" | "terrein" | "kleuren">[];
};

export async function haalSupportersData(): Promise<SupportersData> {
  // De database geeft uitsluitend expliciet toegestane openbare velden terug.
  const { data, error } = await supabase.rpc("openbare_clubinfo");
  if (error) throw new Error("De wedstrijdinformatie kon niet geladen worden. Probeer opnieuw.");
  return data as SupportersData;
}
