import { Env, CursorState, AIGLog } from './types';
import { fetchLogs } from './ai-gateway';
import { dedupAndFilter } from './dedup';
import { bqInsertAll } from './bigquery';
import { Logger } from './logger';

export default {
  async scheduled(
    controller: ScheduledController,
    env: Env,
    ctx: ExecutionContext
  ): Promise<void> {
    const logger = new Logger(env.LOG_LEVEL || 'info');

    try {
      // Hourly execution (0 * * * *) for backfill process
      if (controller.cron === '0 * * * *') {
        logger.info('Starting backfill process');
        ctx.waitUntil(runBackfill(env, logger));
      } else {
        // Every minute execution (*/1 * * * *) for forward process
        logger.info('Starting forward process');
        ctx.waitUntil(runForward(env, logger));
      }
    } catch (error) {
      logger.error('Scheduled job failed', error);
      throw error;
    }
  },
};

/**
 * Forward process: Fetch latest logs and send to BigQuery
 */
async function runForward(env: Env, logger: Logger): Promise<void> {
  const startTime = Date.now();

  try {
    // Default to fetching from 10 minutes ago
    const nowMinus10m = new Date(Date.now() - 10 * 60 * 1000).toISOString();
    
    // Get previous cursor position
    const cursor = await env.STATE_KV.get<CursorState>('forward', 'json');
    let lastTs = cursor?.ts ?? nowMinus10m;
    let lastId = cursor?.id ?? '';

    logger.debug(`Forward cursor: ts=${lastTs}, id=${lastId}`);

    // Phase 1: Fetch remaining logs with same timestamp (ID > lastId)
    const phase1 = await fetchLogs(env, {
      op: 'eq',
      ts: lastTs,
      idCmp: { kind: 'gt', id: lastId },
      asc: true,
      maxPages: 5,
    }, logger);

    // Phase 2: Fetch logs with newer timestamps
    const phase2 = await fetchLogs(env, {
      op: 'gt',
      ts: lastTs,
      asc: true,
      maxPages: parseInt(env.FORWARD_MAX_PAGES || '20'),
    }, logger);

    // Combine all logs and deduplicate
    const allLogs = [...phase1, ...phase2];
    const toSend = await dedupAndFilter(env, allLogs, logger);

    if (toSend.length > 0) {
      logger.info(`Sending ${toSend.length} logs to BigQuery`);

      // Send to BigQuery
      await bqInsertAll(env, toSend, logger);

      // Update cursor (save position of last log)
      const lastLog = toSend[toSend.length - 1];
      await env.STATE_KV.put(
        'forward',
        JSON.stringify({ ts: lastLog.created_at, id: lastLog.id })
      );

      // Record oldest timestamp on first run
      const oldestKey = 'oldest';
      if (!(await env.STATE_KV.get(oldestKey))) {
        await env.STATE_KV.put(oldestKey, toSend[0].created_at);
      }

      logger.info(`Forward process completed successfully in ${Date.now() - startTime}ms`);
    } else {
      logger.info(`No new logs to send (${Date.now() - startTime}ms)`);
    }
  } catch (error) {
    logger.error('Forward process failed', error);
    throw error;
  }
}

/**
 * Backfill process: Fetch historical logs backwards
 */
async function runBackfill(env: Env, logger: Logger): Promise<void> {
  const startTime = Date.now();

  try {
    // Get oldest timestamp
    const oldest = await env.STATE_KV.get('oldest');
    if (!oldest) {
      logger.info('No oldest timestamp found, skipping backfill');
      return;
    }

    // Get backfill stop point (default: 1970)
    const stopAt = (await env.STATE_KV.get('backfill_stop_at')) || '1970-01-01T00:00:00Z';

    logger.debug(`Backfill from ${oldest}, stop at ${stopAt}`);

    // Fetch historical logs
    const batch = await fetchLogs(env, {
      op: 'lt',
      ts: oldest,
      asc: false,
      maxPages: parseInt(env.BACKFILL_MAX_PAGES || '40'),
    }, logger);

    if (batch.length === 0) {
      logger.info('No more logs to backfill');
      // Backfill complete
      await env.STATE_KV.delete('oldest');
      return;
    }

    // Sort chronologically
    const sortedLogs = [...batch].sort((a, b) =>
      a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id)
    );

    // Deduplicate
    const toSend = await dedupAndFilter(env, sortedLogs, logger);

    if (toSend.length > 0) {
      logger.info(`Backfilling ${toSend.length} logs to BigQuery`);

      // Send to BigQuery
      await bqInsertAll(env, toSend, logger);

      // Update new oldest timestamp
      const newOldest = toSend[0].created_at;

      if (newOldest <= stopAt) {
        // Reached stop point
        logger.info('Backfill reached stop point');
        await env.STATE_KV.delete('oldest');
      } else {
        await env.STATE_KV.put('oldest', newOldest);
      }

      logger.info(`Backfill process completed successfully in ${Date.now() - startTime}ms`);
    } else {
      logger.info(`No logs to backfill (${Date.now() - startTime}ms)`);
    }
  } catch (error) {
    logger.error('Backfill process failed', error);
    throw error;
  }
}