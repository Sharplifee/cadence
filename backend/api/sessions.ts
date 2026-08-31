// POST /api/sessions — the only ingest endpoint Cadence has.
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.CADENCE_SUPABASE_URL!,
  process.env.CADENCE_SUPABASE_SERVICE_KEY!
);

export const config = { api: { bodyParser: { sizeLimit: '8mb' } } };

export default async function handler(req: any, res: any) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  const auth = req.headers.authorization ?? '';
  if (auth !== `Bearer ${process.env.CADENCE_API_KEY}`) {
    return res.status(401).json({ error: 'unauthorized' });
  }

  const { summary, frames } = req.body ?? {};
  if (!summary?.id) return res.status(400).json({ error: 'missing summary.id' });

  const { error: sErr } = await supabase.from('cadence_sessions').upsert({
    id: summary.id,
    started_at: summary.startedAt,
    duration_seconds: summary.duration,
    talk_share: summary.talkShare,
    interruptions: summary.interruptions,
    correction_rate: summary.correctionRate ?? null,
  });
  if (sErr) return res.status(500).json({ error: sErr.message });

  if (Array.isArray(frames) && frames.length) {
    // Chunked so an hour-long session does not blow the statement limit.
    for (let i = 0; i < frames.length; i += 2000) {
      const rows = frames.slice(i, i + 2000).map((f: any) => ({
        session_id: summary.id,
        t: f.t, speaker: f.speaker, dbfs: f.dbfs,
        f0: f.f0, syllable_rate: f.syllableRate, centroid: f.centroid,
      }));
      const { error } = await supabase.from('cadence_frames').insert(rows);
      if (error) return res.status(500).json({ error: error.message });
    }
  }

  if (Array.isArray(summary.cues) && summary.cues.length) {
    const rows = summary.cues.map((c: any) => ({
      session_id: summary.id,
      t: c.t,
      code: c.code,
      rate_ratio: c.divergence?.rateRatio,
      loudness_delta: c.divergence?.loudnessDelta,
      pitch_delta: c.divergence?.pitchDelta,
      turn_length_ratio: c.divergence?.turnLengthRatio,
      talk_share: c.divergence?.talkShare,
      interrupt_rate: c.divergence?.interruptRate,
      corrected: c.corrected ?? null,
    }));
    const { error } = await supabase.from('cadence_cues').insert(rows);
    if (error) return res.status(500).json({ error: error.message });
  }

  return res.status(200).json({ ok: true, session: summary.id, frames: frames?.length ?? 0 });
}
