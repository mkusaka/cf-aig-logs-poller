export interface Env {
  // Cloudflare settings
  CF_API_TOKEN: string;
  CF_ACCOUNT_ID: string;
  AIG_GATEWAY_ID: string;

  // KV Namespaces
  STATE_KV: KVNamespace;
  IDS_KV: KVNamespace;

  // GCP settings
  GCP_TOKEN_URI: string;
  GCP_SA_EMAIL: string;
  GCP_SA_PRIVATE_KEY_PEM: string;
  GCP_BQ_PROJECT: string;
  GCP_BQ_DATASET: string;
  GCP_BQ_TABLE: string;

  // Configuration
  DEDUP_TTL_DAYS?: string;
  LOG_LEVEL?: string;
  FORWARD_MAX_PAGES?: string;
  BACKFILL_MAX_PAGES?: string;
  LOGS_PER_PAGE?: string;
}

export interface AIGLog {
  id: string;
  created_at: string;
  provider: string;
  model: string;
  model_type?: string;
  success: boolean;
  status_code: number;
  cached: boolean;
  duration: number;
  tokens_in?: number;
  tokens_out?: number;
  cost?: number;
  request_type?: string;
  request_content_type?: string;
  response_content_type?: string;
  path?: string;
  step?: number;
}

export interface CursorState {
  ts: string;
  id: string;
}

export interface FetchLogsOptions {
  op: 'eq' | 'gt' | 'lt';
  ts: string;
  idCmp?: {
    kind: 'gt' | 'lt';
    id: string;
  };
  asc: boolean;
  maxPages: number;
}

export interface CloudflareAPIResponse<T> {
  result: T;
  success: boolean;
  errors: Array<{ code: number; message: string }>;
  messages: Array<{ code: number; message: string }>;
  result_info?: {
    page: number;
    per_page: number;
    total_pages: number;
    count: number;
    total_count: number;
  };
}

export interface BigQueryInsertRow {
  insertId?: string;
  json: Record<string, any>;
}

export interface BigQueryInsertResponse {
  kind: string;
  insertErrors?: Array<{
    index: number;
    errors: Array<{
      reason: string;
      location: string;
      debugInfo: string;
      message: string;
    }>;
  }>;
}