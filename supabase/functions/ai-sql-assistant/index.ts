import "jsr:@supabase/functions-js/edge-runtime.d.ts";

interface SqlAiGenerateRequest {
  prompt: string;
  mode?: "generate" | "fix";
  currentSql?: string;
  metadata?: {
    schemas?: string[];
    tables?: Array<{
      tableSchema: string;
      tableName: string;
      columns?: Array<{ name: string; dataType: string }>;
    }>;
    foreignKeys?: Array<{
      sourceSchema: string;
      sourceTable: string;
      sourceColumn: string;
      targetSchema: string;
      targetTable: string;
      targetColumn: string;
      constraintName: string;
    }>;
  };
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function trimMetadata(metadata?: SqlAiGenerateRequest["metadata"]) {
  return {
    schemas: metadata?.schemas?.slice(0, 12) ?? [],
    tables: (metadata?.tables ?? []).slice(0, 16).map((table) => ({
      schema: table.tableSchema,
      table: table.tableName,
      columns: (table.columns ?? []).slice(0, 16).map((column) => ({
        name: column.name,
        type: column.dataType,
      })),
    })),
    foreignKeys: (metadata?.foreignKeys ?? []).slice(0, 24).map((item) => ({
      from: `${item.sourceSchema}.${item.sourceTable}.${item.sourceColumn}`,
      to: `${item.targetSchema}.${item.targetTable}.${item.targetColumn}`,
      constraint: item.constraintName,
    })),
  };
}

function extractSql(payload: string) {
  const fenced = payload.match(/```(?:sql)?\s*([\s\S]*?)```/i);
  if (fenced?.[1]) return fenced[1].trim();
  return payload.trim();
}

function tryParseJson<T>(content: string): T | null {
  try {
    return JSON.parse(content) as T;
  } catch {
    return null;
  }
}

function extractMessageContent(content: unknown): string {
  if (typeof content === "string") return content;

  if (Array.isArray(content)) {
    return content
      .map((item) => {
        if (typeof item === "string") return item;
        if (item && typeof item === "object" && "text" in item && typeof item.text === "string") {
          return item.text;
        }
        return "";
      })
      .join("\n")
      .trim();
  }

  return "";
}

function parseAiPayload(content: string) {
  const direct = tryParseJson<{ sql?: string; summary?: string; warnings?: string[] }>(content);
  if (direct?.sql) {
    return {
      sql: extractSql(direct.sql),
      summary: direct.summary || "AI generated PostgreSQL based on the current schema.",
      warnings: Array.isArray(direct.warnings) ? direct.warnings : [],
    };
  }

  const objectMatch = content.match(/\{[\s\S]*\}/);
  if (objectMatch) {
    const recovered = tryParseJson<{ sql?: string; summary?: string; warnings?: string[] }>(objectMatch[0]);
    if (recovered?.sql) {
      return {
        sql: extractSql(recovered.sql),
        summary: recovered.summary || "AI generated PostgreSQL based on the current schema.",
        warnings: Array.isArray(recovered.warnings) ? recovered.warnings : [],
      };
    }
  }

  const sql = extractSql(content);
  return {
    sql,
    summary: "AI generated PostgreSQL based on the current schema.",
    warnings: [],
  };
}

function classifyProviderError(errorText: string, status: number) {
  if (/insufficient_quota/i.test(errorText) || status === 402) return "insufficient_quota";
  if (/invalid api key|incorrect api key|authentication|unauthorized/i.test(errorText) || status === 401 || status === 403) {
    return "invalid_api_key";
  }
  if (/model.*not found|unknown model/i.test(errorText) || status === 404) return "model_not_found";
  if (/timeout|timed out|ENOTFOUND|fetch failed|network/i.test(errorText) || status === 502 || status === 503 || status === 504) {
    return "provider_unreachable";
  }
  if (status === 422) return "validation_error";
  return "provider_error";
}

function formatResponseHeaders(response: Response) {
  const interesting = [
    "content-type",
    "www-authenticate",
    "x-request-id",
    "x-nvcf-request-id",
    "x-trace-id",
  ];

  return interesting
    .map((key) => {
      const value = response.headers.get(key);
      return value ? `${key}: ${value}` : null;
    })
    .filter(Boolean)
    .join("; ");
}

function buildProviderErrorMessage(response: Response, bodyText: string) {
  const headerText = formatResponseHeaders(response);
  const trimmedBody = bodyText.trim();

  if (trimmedBody) {
    return `HTTP ${response.status} ${response.statusText}: ${trimmedBody}`;
  }

  return headerText
    ? `HTTP ${response.status} ${response.statusText}. Response headers: ${headerText}`
    : `HTTP ${response.status} ${response.statusText}. Provider returned an empty body.`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = (await req.json()) as SqlAiGenerateRequest;
    const prompt = body?.prompt?.trim();

    if (!prompt) {
      return json({ message: "Prompt is required" }, 400);
    }

    const apiKey = Deno.env.get("OPENAI_API_KEY") || Deno.env.get("AI_API_KEY");
    const baseUrl = (Deno.env.get("OPENAI_BASE_URL") || Deno.env.get("AI_BASE_URL") || "https://api.openai.com/v1").replace(/\/$/, "");
    const model = Deno.env.get("OPENAI_MODEL") || Deno.env.get("AI_MODEL") || "gpt-4.1-mini";

    if (!apiKey) {
      return json({ code: "missing_secret", message: "Missing OPENAI_API_KEY or AI_API_KEY in Supabase secrets" }, 500);
    }

    const systemPrompt = [
      "You are a senior PostgreSQL assistant inside a SQL workbench.",
      "Return a JSON object with keys: sql, summary, warnings.",
      "sql must be executable PostgreSQL.",
      "summary must be one short sentence.",
      "warnings must be an array of short strings.",
      "Prefer explicit JOIN clauses, aliases, LIMIT for exploratory queries, and safe filters.",
      "Do not wrap the final response outside JSON.",
    ].join(" ");

    const userPrompt = JSON.stringify(
      {
        mode: body.mode || "generate",
        request: prompt,
        currentSql: body.currentSql || "",
        metadata: trimMetadata(body.metadata),
      },
      null,
      2,
    );

    const requestBody: Record<string, unknown> = {
      model,
      temperature: 0.2,
      max_tokens: 1200,
      stream: false,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
    };

    requestBody.response_format = { type: "json_object" };

    let response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(requestBody),
    });

    if (!response.ok) {
      const firstErrorText = await response.text();
      console.error("provider first attempt failed", {
        status: response.status,
        statusText: response.statusText,
        body: firstErrorText,
        headers: formatResponseHeaders(response),
      });

      const looksLikeCompatibilityIssue =
        response.status === 400 &&
        /response_format|json_object|unsupported|schema|invalid request/i.test(firstErrorText);

      if (looksLikeCompatibilityIssue) {
        delete requestBody.response_format;
        response = await fetch(`${baseUrl}/chat/completions`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(requestBody),
        });
      } else {
        return json(
          {
            code: classifyProviderError(firstErrorText, response.status),
            message: `LLM request failed: ${buildProviderErrorMessage(response, firstErrorText)}`,
          },
          500,
        );
      }
    }

    if (!response.ok) {
      const secondErrorText = await response.text();
      console.error("provider second attempt failed", {
        status: response.status,
        statusText: response.statusText,
        body: secondErrorText,
        headers: formatResponseHeaders(response),
      });

      return json(
        {
          code: classifyProviderError(secondErrorText, response.status),
          message: `LLM request failed: ${buildProviderErrorMessage(response, secondErrorText)}`,
        },
        500,
      );
    }

    const result = await response.json();
    const rawContent = result?.choices?.[0]?.message?.content;
    const content = extractMessageContent(rawContent);

    if (!content) {
      return json({ code: "empty_response", message: "LLM response was empty" }, 500);
    }

    const parsed = parseAiPayload(content);
    if (!parsed.sql) {
      return json({ code: "invalid_payload", message: "LLM did not return SQL" }, 500);
    }

    return json(parsed);
  } catch (error) {
    return json(
      {
        code: "server_error",
        message: error instanceof Error ? error.message : "Unknown error",
      },
      500,
    );
  }
});