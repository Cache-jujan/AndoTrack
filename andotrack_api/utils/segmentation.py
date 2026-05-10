import math
from statistics import mean


def assign_segments(results: list) -> list:
    """
    Mutates each RaceResult's segment field in-memory.
    Call this BEFORE db.commit() inside POST /races/{race_id}/finish.
    """
    total = len(results)
    if total == 0:
        return results

    competitive_cutoff  = math.ceil(0.20 * total)
    recreational_cutoff = math.ceil(0.70 * total)

    for result in results:
        if result.rank <= competitive_cutoff:
            result.segment = "competitive"
        elif result.rank <= recreational_cutoff:
            result.segment = "recreational"
        else:
            result.segment = "casual"

    return results


def compute_analytics(results: list, race_runners: list, race) -> dict:
    """
    Computes the full analytics payload for GET /races/{race_id}/analytics.
    Called on every read — nothing extra is stored.
    """
    total_registered = len(race_runners)
    total_checkedin  = sum(1 for rr in race_runners if rr.is_present)
    total_finishers  = len(results)
    total_dnf        = sum(1 for rr in race_runners if rr.race_status == "dnf")
    total_dns        = sum(1 for rr in race_runners if rr.race_status == "dns")

    no_show_rate = round(
        ((total_registered - total_checkedin) / total_registered * 100), 1
    ) if total_registered > 0 else 0.0

    dnf_rate = round(
        (total_dnf / total_checkedin * 100), 1
    ) if total_checkedin > 0 else 0.0

    def segment_stats(label: str) -> dict:
        rows  = [r for r in results if r.segment == label]
        paces = [r.pace_min_per_km for r in rows if r.pace_min_per_km is not None]
        avg   = mean(paces) if paces else None

        def fmt(p):
            if p is None:
                return None
            mins = int(p)
            secs = round((p - mins) * 60)
            return f"{mins}:{secs:02d} /km"

        return {
            "count":               len(rows),
            "avg_pace_min_per_km": round(avg, 2) if avg else None,
            "avg_pace_formatted":  fmt(avg),
        }

    comp = segment_stats("competitive")
    comp["cutoff_rank"]   = math.ceil(0.20 * total_finishers)
    comp["percentile_top"] = 20

    rec = segment_stats("recreational")
    rec["percentile_range"] = "20–70"

    cas = segment_stats("casual")
    cas["percentile_range"] = "70–100"

    return {
        "race_id":   race.id,
        "race_name": race.name,
        "status":    race.status,
        "participation_funnel": {
            "registered":   total_registered,
            "checked_in":   total_checkedin,
            "finishers":    total_finishers,
            "dnf":          total_dnf,
            "dns":          total_dns,
            "no_show_rate": no_show_rate,
            "dnf_rate":     dnf_rate,
        },
        "segments": {
            "competitive":  comp,
            "recreational": rec,
            "casual":       cas,
        },
    }