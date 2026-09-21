// A test-only reader for the function's `text/event-stream` answer. It buffers
// the whole response, which a real client must not do. The production reader
// is `app/lib/features/import/data/remote_import_repository.dart`.

export interface SseEvent {
  event: string;
  data: unknown;
}

/** Every event in a finished SSE response, in order. */
export async function collectSse(res: Response): Promise<SseEvent[]> {
  const body = await res.text();
  const events: SseEvent[] = [];
  for (const frame of body.split("\n\n")) {
    if (frame.trim() === "") continue;
    let event = "message";
    const data: string[] = [];
    for (const line of frame.split("\n")) {
      if (line.startsWith("event:")) event = line.slice(6).trim();
      else if (line.startsWith("data:")) data.push(line.slice(5).trim());
    }
    events.push({ event, data: JSON.parse(data.join("\n")) });
  }
  return events;
}
