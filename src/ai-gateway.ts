import { Env, AIGLog, FetchLogsOptions, CloudflareAPIResponse } from './types';
import { Logger } from './logger';

/**
 * Fetch logs from Cloudflare AI Gateway Logs API
 */
export async function fetchLogs(
  env: Env,
  options: FetchLogsOptions,
  logger: Logger
): Promise<AIGLog[]> {
  const baseUrl = `https://api.cloudflare.com/client/v4/accounts/${env.CF_ACCOUNT_ID}/ai-gateway/gateways/${env.AIG_GATEWAY_ID}/logs`;
  const perPage = parseInt(env.LOGS_PER_PAGE || '50');
  let page = 1;
  const allLogs: AIGLog[] = [];

  while (page <= options.maxPages) {
    const params = new URLSearchParams();
    params.set('per_page', String(perPage));
    params.set('page', String(page));
    params.set('order_by', 'created_at');
    params.set('order_by_direction', options.asc ? 'asc' : 'desc');

    // Timestamp filter
    params.append(
      'filters',
      JSON.stringify({
        key: 'created_at',
        operator: options.op,
        value: [options.ts],
      })
    );

    // ID comparison filter (for same timestamp handling)
    if (options.idCmp) {
      params.append(
        'filters',
        JSON.stringify({
          key: 'id',
          operator: options.idCmp.kind,
          value: [options.idCmp.id],
        })
      );
    }

    const url = `${baseUrl}?${params}`;
    logger.debug(`Fetching logs from: ${url}`);

    try {
      const response = await fetch(url, {
        headers: {
          Authorization: `Bearer ${env.CF_API_TOKEN}`,
          'Content-Type': 'application/json',
        },
      });

      if (!response.ok) {
        const errorText = await response.text();
        logger.error(`CF Logs API error: ${response.status}`, errorText);
        throw new Error(`CF Logs API returned ${response.status}: ${errorText}`);
      }

      const json = await response.json<CloudflareAPIResponse<AIGLog[]>>();

      if (!json.success) {
        const errors = json.errors?.map(e => e.message).join(', ') || 'Unknown error';
        throw new Error(`CF Logs API error: ${errors}`);
      }

      const logs = json.result || [];
      
      if (logs.length === 0) {
        logger.debug(`No logs found on page ${page}`);
        break;
      }

      logger.debug(`Fetched ${logs.length} logs from page ${page}`);
      allLogs.push(...logs);

      // If fewer logs than perPage, no more pages
      if (logs.length < perPage) {
        break;
      }

      page++;
    } catch (error) {
      logger.error(`Failed to fetch logs from page ${page}`, error);
      throw error;
    }
  }

  logger.info(`Total logs fetched: ${allLogs.length}`);
  return allLogs;
}

/**
 * Sort logs by timestamp and ID
 */
export function sortLogs(logs: AIGLog[], ascending: boolean = true): AIGLog[] {
  return [...logs].sort((a, b) => {
    const tsCompare = a.created_at.localeCompare(b.created_at);
    if (tsCompare !== 0) {
      return ascending ? tsCompare : -tsCompare;
    }
    const idCompare = a.id.localeCompare(b.id);
    return ascending ? idCompare : -idCompare;
  });
}