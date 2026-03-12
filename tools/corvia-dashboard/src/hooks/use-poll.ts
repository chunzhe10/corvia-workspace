import { useState, useEffect, useRef, useCallback } from "preact/hooks";

export function usePoll<T>(
  fetcher: () => Promise<T>,
  intervalMs = 3000,
): { data: T | null; error: string | null; loading: boolean } {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const mounted = useRef(true);

  const poll = useCallback(async () => {
    try {
      const result = await fetcher();
      if (mounted.current) {
        setData(result);
        setError(null);
        setLoading(false);
      }
    } catch (e: any) {
      if (mounted.current) {
        setError(e.message || "fetch failed");
        setLoading(false);
      }
    }
  }, [fetcher]);

  useEffect(() => {
    mounted.current = true;
    poll();
    const id = setInterval(poll, intervalMs);
    return () => {
      mounted.current = false;
      clearInterval(id);
    };
  }, [poll, intervalMs]);

  return { data, error, loading };
}
