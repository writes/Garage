import { onCall, HttpsError } from "firebase-functions/v2/https";

type OilAnalysisResponse = {
  labName: string;
  pdfPath?: string | null;
  aluminum?: number | null;
  chromium?: number | null;
  iron?: number | null;
  copper?: number | null;
  lead?: number | null;
  tin?: number | null;
  molybdenum?: number | null;
  nickel?: number | null;
  manganese?: number | null;
  silver?: number | null;
  titanium?: number | null;
  silicon?: number | null;
  sodium?: number | null;
  potassium?: number | null;
  viscosity?: string | null;
  insolubles?: number | null;
  milesOnOil?: number | null;
  labRecommendation?: string | null;
};

export const parseOilAnalysis = onCall({ region: "us-central1" }, async (request): Promise<OilAnalysisResponse> => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const pdfBase64 = request.data?.pdfBase64 as string | undefined;
  if (!pdfBase64) {
    throw new HttpsError("invalid-argument", "PDF data is required.");
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new HttpsError("failed-precondition", "Anthropic API key is not configured.");
  }

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-20250514",
      max_tokens: 2000,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "document",
              source: {
                type: "base64",
                media_type: "application/pdf",
                data: pdfBase64,
              },
            },
            {
              type: "text",
              text: "Extract all oil analysis fields from this report and return structured JSON only.",
            },
          ],
        },
      ],
    }),
  });

  if (!response.ok) {
    throw new HttpsError("internal", `Claude request failed with ${response.status}.`);
  }

  const payload = await response.json() as { content?: Array<{ text?: string }> };
  const text = payload.content?.[0]?.text ?? "{}";

  try {
    return JSON.parse(text.replace(/```json|```/g, "").trim()) as OilAnalysisResponse;
  } catch {
    throw new HttpsError("internal", "Claude returned malformed JSON.");
  }
});
