export type RunnerStatus = 'idle' | 'working' | 'done';

export interface RunnerSnapshot {
  id: number;
  status: RunnerStatus;
  url: string;
  pages_done: number;
  pages_failed: number;
}

export interface ProgressEvent {
  phase: 'round_start' | 'round_end';
  total_done: number;
  total_queued: number;
  runners: RunnerSnapshot[];
}

export interface PageEvent {
  url: string;
  status: number;
  scores: Scores;
  findings: number;
}

export interface Scores {
  performance: number;
  accessibility: number;
  best_practices: number;
  seo: number;
  gdpr: number;
  keyword: number;
  aeo: number;
}

export interface DoneEvent {
  total_pages: number;
  total_findings: number;
  critical: number;
  warning: number;
  info: number;
}

export interface ErrorEvent {
  message: string;
}

export type SseEvent =
  | { type: 'progress'; data: ProgressEvent }
  | { type: 'page'; data: PageEvent }
  | { type: 'done'; data: DoneEvent }
  | { type: 'error'; data: ErrorEvent };

export function parseSseEvent(eventType: string, dataLine: string): SseEvent | null {
  try {
    const data = JSON.parse(dataLine);
    switch (eventType) {
      case 'progress': return { type: 'progress', data: data as ProgressEvent };
      case 'page':     return { type: 'page',     data: data as PageEvent };
      case 'done':     return { type: 'done',     data: data as DoneEvent };
      case 'error':    return { type: 'error',    data: data as ErrorEvent };
      default:         return null;
    }
  } catch {
    return null;
  }
}
