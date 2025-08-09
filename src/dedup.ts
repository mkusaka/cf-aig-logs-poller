import { Env, AIGLog } from './types';
import { Logger } from './logger';

/**
 * Deduplicate logs and filter out already processed ones
 * Uses both in-memory Set and KV store for deduplication
 */
export async function dedupAndFilter(
  env: Env,
  logs: AIGLog[],
  logger: Logger
): Promise<AIGLog[]> {
  const startTime = Date.now();
  const seen = new Set<string>();
  const output: AIGLog[] = [];

  // TTL for deduplication entries (in seconds)
  const ttlDays = parseInt(env.DEDUP_TTL_DAYS || '45', 10);
  const ttlSeconds = ttlDays * 24 * 60 * 60;

  logger.debug(`Starting deduplication for ${logs.length} logs`);

  for (const log of logs) {
    // Skip logs without ID
    if (!log.id) {
      logger.warn('Log without ID detected', log);
      continue;
    }

    // Skip if already seen in this batch
    if (seen.has(log.id)) {
      logger.debug(`Duplicate in batch: ${log.id}`);
      continue;
    }
    seen.add(log.id);

    // Check if already processed (in KV store)
    const kvKey = `id:${log.id}`;
    const existing = await env.IDS_KV.get(kvKey);
    
    if (existing) {
      logger.debug(`Already processed: ${log.id}`);
      continue;
    }

    // Add to output
    output.push(log);
  }

  // Mark these logs as processed in KV store
  if (output.length > 0) {
    logger.debug(`Marking ${output.length} logs as processed`);
    
    // Batch KV operations for better performance
    const kvPromises = output.map(log => {
      const kvKey = `id:${log.id}`;
      return env.IDS_KV.put(kvKey, '1', {
        expirationTtl: ttlSeconds,
      }).catch(error => {
        // Log error but don't fail the entire operation
        logger.warn(`Failed to mark ${log.id} as processed`, error);
      });
    });

    await Promise.all(kvPromises);
  }

  const elapsed = Date.now() - startTime;
  logger.info(
    `Deduplication complete: ${logs.length} input, ${output.length} output, ${elapsed}ms`
  );

  return output;
}

/**
 * Clear deduplication cache (for maintenance/debugging)
 */
export async function clearDedupCache(
  env: Env,
  logger: Logger
): Promise<void> {
  logger.warn('Clearing deduplication cache - this may cause duplicates');
  
  // KV doesn't have a clear all method, so we need to list and delete
  // This is a maintenance operation that should be used carefully
  
  let cursor: string | undefined;
  let deleted = 0;

  do {
    const listResult = await env.IDS_KV.list({
      prefix: 'id:',
      limit: 1000,
      cursor,
    });

    const deletePromises = listResult.keys.map(key =>
      env.IDS_KV.delete(key.name)
    );

    await Promise.all(deletePromises);
    deleted += listResult.keys.length;

    cursor = listResult.cursor;
  } while (cursor);

  logger.info(`Cleared ${deleted} entries from deduplication cache`);
}

/**
 * Get deduplication cache statistics
 */
export async function getDedupStats(
  env: Env,
  logger: Logger
): Promise<{
  totalEntries: number;
  sampleIds: string[];
}> {
  let totalEntries = 0;
  const sampleIds: string[] = [];
  let cursor: string | undefined;

  do {
    const listResult = await env.IDS_KV.list({
      prefix: 'id:',
      limit: 1000,
      cursor,
    });

    totalEntries += listResult.keys.length;

    // Collect sample IDs (first 10)
    if (sampleIds.length < 10) {
      for (const key of listResult.keys) {
        if (sampleIds.length >= 10) break;
        sampleIds.push(key.name.replace('id:', ''));
      }
    }

    cursor = listResult.cursor;
  } while (cursor);

  logger.info(`Dedup cache stats: ${totalEntries} entries`);

  return {
    totalEntries,
    sampleIds,
  };
}