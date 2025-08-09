import { Env, AIGLog, BigQueryInsertRow, BigQueryInsertResponse } from './types';
import { Logger } from './logger';
import { getGoogleAccessToken } from './google-auth';

/**
 * Batch insert logs to BigQuery
 */
export async function bqInsertAll(
  env: Env,
  logs: AIGLog[],
  logger: Logger
): Promise<void> {
  if (logs.length === 0) {
    return;
  }

  const startTime = Date.now();

  try {
    // Get Google OAuth2 access token
    const accessToken = await getGoogleAccessToken(
      env,
      'https://www.googleapis.com/auth/bigquery.insertdata'
    );

    // BigQuery insertAll endpoint
    const url = `https://bigquery.googleapis.com/bigquery/v2/projects/${env.GCP_BQ_PROJECT}/datasets/${env.GCP_BQ_DATASET}/tables/${env.GCP_BQ_TABLE}/insertAll`;

    // Convert logs to BigQuery row format
    const rows: BigQueryInsertRow[] = logs.map(log => ({
      insertId: log.id, // ID for deduplication (best-effort)
      json: {
        id: log.id,
        created_at: log.created_at, // ISO-8601 format is OK
        provider: log.provider,
        model: log.model,
        model_type: log.model_type || null,
        success: log.success,
        status_code: log.status_code,
        cached: log.cached,
        duration: log.duration,
        tokens_in: log.tokens_in || null,
        tokens_out: log.tokens_out || null,
        cost: log.cost || null,
        request_type: log.request_type || null,
        request_content_type: log.request_content_type || null,
        response_content_type: log.response_content_type || null,
        path: log.path || null,
        step: log.step || null,
        ingested_at: new Date().toISOString(),
      },
    }));

    // BigQuery insertAll request
    const requestBody = {
      kind: 'bigquery#tableDataInsertAllRequest',
      skipInvalidRows: false, // Error on invalid rows
      ignoreUnknownValues: false, // Error on unknown fields
      rows,
    };

    logger.debug(`Sending ${rows.length} rows to BigQuery`);

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(requestBody),
    });

    if (!response.ok) {
      const errorText = await response.text();
      logger.error(`BigQuery insertAll error: ${response.status}`, errorText);
      throw new Error(`BigQuery insertAll returned ${response.status}: ${errorText}`);
    }

    const result = await response.json<BigQueryInsertResponse>();

    // Log any insert errors
    if (result.insertErrors && result.insertErrors.length > 0) {
      logger.warn('BigQuery insert errors detected', result.insertErrors);
      
      // Log error details
      for (const insertError of result.insertErrors) {
        const failedLog = logs[insertError.index];
        logger.error(
          `Failed to insert log ${failedLog?.id}`,
          insertError.errors
        );
      }

      // Continue even with partial failures (adjust as needed)
      const errorCount = result.insertErrors.length;
      const successCount = logs.length - errorCount;
      logger.info(`BigQuery insert: ${successCount} success, ${errorCount} failed`);
    } else {
      logger.info(`Successfully inserted ${logs.length} logs to BigQuery in ${Date.now() - startTime}ms`);
    }
  } catch (error) {
    logger.error('BigQuery insertAll failed', error);
    throw error;
  }
}

/**
 * Check if BigQuery table exists (optional)
 */
export async function checkBigQueryTable(
  env: Env,
  logger: Logger
): Promise<boolean> {
  try {
    const accessToken = await getGoogleAccessToken(
      env,
      'https://www.googleapis.com/auth/bigquery'
    );

    const url = `https://bigquery.googleapis.com/bigquery/v2/projects/${env.GCP_BQ_PROJECT}/datasets/${env.GCP_BQ_DATASET}/tables/${env.GCP_BQ_TABLE}`;

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    });

    if (response.status === 404) {
      logger.warn(`BigQuery table ${env.GCP_BQ_TABLE} does not exist`);
      return false;
    }

    if (!response.ok) {
      const errorText = await response.text();
      logger.error(`Failed to check BigQuery table: ${response.status}`, errorText);
      return false;
    }

    logger.info(`BigQuery table ${env.GCP_BQ_TABLE} exists`);
    return true;
  } catch (error) {
    logger.error('Failed to check BigQuery table', error);
    return false;
  }
}