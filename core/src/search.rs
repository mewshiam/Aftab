//! Persian-aware search ranking.
//!
//! The query and every candidate go through [`crate::persian::compact_key`],
//! so `آفتاب` matches `افتاب`, `كاشي` matches `کاشی`, and `سرزمین‌ها`
//! matches `سرزمینها` before any scoring even starts. Scoring is then purely
//! structural:
//!
//! | Relation of query key to candidate key | Score |
//! |---|---|
//! | exact equality                         | 100   |
//! | word-prefix (`"aftab"` in `"aftab media"`) | 85 |
//! | candidate starts with query            | 80 + length bonus |
//! | candidate contains query               | 60 + position bonus |
//! | query is a subsequence of candidate    | 25 + coverage bonus |
//! | otherwise                              | no match |
//!
//! Subsequence matching is what makes T9-style typing ("slm" → "سلطان
//! محمود") work on twelve-key remotes — essential for the Android TV build.

use crate::persian::compact_key;

/// Minimum viable score returned for any match (subsequence floor).
const SUBSEQUENCE_FLOOR: u32 = 25;
/// Exact-equality score.
const EXACT: u32 = 100;
/// Word-boundary prefix score.
const WORD_PREFIX: u32 = 85;
/// Plain prefix base score.
const PREFIX: u32 = 80;
/// Plain substring base score.
const SUBSTRING: u32 = 60;

/// Score `query` against `candidate`. Returns `None` when there is no match
/// at all, otherwise a score in `SUBSEQUENCE_FLOOR..=EXACT`.
///
/// The score is deterministic and stable: equal inputs always produce equal
/// scores, and ties are broken by insertion order in [`rank`].
pub fn score_match(query: &str, candidate: &str) -> Option<u32> {
    let q = compact_key(query);
    let c = compact_key(candidate);
    if q.is_empty() {
        // An empty query "matches" nothing — callers render the full catalog.
        return None;
    }
    if c.is_empty() {
        return None;
    }
    if q == c {
        return Some(EXACT);
    }
    if let Some(score) = word_prefix_score(&q, &c) {
        return Some(score);
    }
    if c.starts_with(&q) {
        return Some(PREFIX + length_bonus(&q, &c));
    }
    if let Some(pos) = c.find(&q) {
        let start_bonus = if pos == 0 { 10 } else { 5 };
        return Some(SUBSTRING + start_bonus + length_bonus(&q, &c));
    }
    subsequence_score(&q, &c)
}

/// `q` is a prefix of one of `c`'s whitespace-separated words.
fn word_prefix_score(q: &str, c: &str) -> Option<u32> {
    let hit = c.split_whitespace().any(|word| {
        // A single-letter query would otherwise prefix-match nearly every
        // word; require at least two characters for the word bonus.
        word.starts_with(q) && q.chars().count() >= 2
    });
    if hit {
        Some(WORD_PREFIX + length_bonus(q, c))
    } else {
        None
    }
}

/// Small bonus rewarding shorter candidates (titles, not essays).
fn length_bonus(q: &str, c: &str) -> u32 {
    let ql = q.chars().count().max(1) as u32;
    let cl = c.chars().count().max(1) as u32;
    // Up to +10: the closer the candidate is in length to the query, the
    // more likely it is exactly the thing the user asked for.
    let ratio = (ql * 10).saturating_div(cl);
    ratio.min(10)
}

/// Ordered subsequence test with a coverage-scaled score.
fn subsequence_score(q: &str, c: &str) -> Option<u32> {
    let q_chars: Vec<char> = q.chars().collect();
    if q_chars.is_empty() {
        return None;
    }
    let mut qi = 0usize;
    for cc in c.chars() {
        if cc == q_chars[qi] {
            qi += 1;
            if qi == q_chars.len() {
                break;
            }
        }
    }
    if qi < q_chars.len() {
        return None;
    }
    // Coverage: how much of the candidate did the query consume?
    let coverage = (q_chars.len() * 100) / c.chars().count().max(1);
    let cov_bonus = (coverage as u32).min(30) / 3;
    Some(SUBSEQUENCE_FLOOR + cov_bonus)
}

/// Rank candidates: returns `(original_index, score)` pairs, best first.
/// Ties keep the caller's original order (stable sort).
pub fn rank<S: AsRef<str>>(query: &str, candidates: &[S]) -> Vec<(usize, u32)> {
    let mut scored: Vec<(usize, u32)> = candidates
        .iter()
        .enumerate()
        .filter_map(|(i, c)| score_match(query, c.as_ref()).map(|s| (i, s)))
        .collect();
    scored.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    scored
}

#[cfg(test)]
mod tests {
    use super::*;

    const TITLES: &[&str] = &[
        "آفتاب مدیا",
        "افتاب MEDIA",
        "سلطان محمود",
        "گوشه",
        "El Cid",
        "سرزمین‌ها",
        "یک، دو، سه",
    ];

    #[test]
    fn exact_match_scores_highest() {
        assert_eq!(score_match("آفتاب مدیا", "آفتاب مدیا"), Some(100));
    }

    #[test]
    fn persian_folding_happens_before_scoring() {
        // آ → ا folding means the query without madda still matches exactly.
        assert_eq!(score_match("افتاب مدیا", "آفتاب مدیا"), Some(100));
        // Arabic kaf/yeh in the candidate:
        assert_eq!(score_match("کاشی", "كاشي"), Some(100));
    }

    #[test]
    fn zwnj_insensitive_matching() {
        assert!(score_match("سرزمینها", "سرزمین‌ها").is_some());
        assert!(score_match("سرزمین‌ها", "سرزمینها").unwrap() >= 60);
    }

    #[test]
    fn prefix_scores_above_substring() {
        let prefix = score_match("گوشه", "گوشه‌های تاریک").unwrap();
        let substring = score_match("وشه", "گوشه‌های تاریک").unwrap();
        assert!(
            prefix > substring,
            "prefix {prefix} must beat substring {substring}"
        );
    }

    #[test]
    fn word_prefix_beats_mid_word_substring() {
        // "مدیا" hits a whole word of "افتاب مدیا"…
        let word = score_match("مدیا", "افتاب مدیا").unwrap();
        // …while "دیا" only appears mid-word, so it scores as a substring.
        let substring = score_match("دیا", "افتاب مدیا").unwrap();
        assert!(
            word > substring,
            "word-prefix {word} should beat mid-word substring {substring}"
        );
    }

    #[test]
    fn subsequence_matches_t9_style() {
        // Persian subsequence: dropped letters still find the title — the
        // twelve-key remote / sloppy-typing case.
        let score = score_match("سطن", "سلطان");
        assert!(score.is_some(), "سطن should subsequence-match سلطان");
        // ASCII subsequence through a Latin title needs the letters in order.
        assert!(score_match("eid", "El Cid").is_some());
    }

    #[test]
    fn subsequence_rejects_out_of_order() {
        assert_eq!(score_match("dci", "El Cid"), None);
        assert_eq!(score_match("mahmud", "سلطان محمود"), None);
    }

    #[test]
    fn empty_query_matches_nothing() {
        assert_eq!(score_match("", "هرچی"), None);
        assert_eq!(
            score_match("   ", "هرچی"),
            None,
            "whitespace-only query is empty"
        );
    }

    #[test]
    fn empty_candidate_matches_nothing() {
        assert_eq!(score_match("x", ""), None);
    }

    #[test]
    fn no_match_returns_none() {
        assert_eq!(score_match("زulia", "El Cid"), None);
    }

    #[test]
    fn digits_and_case_fold_in_queries() {
        assert!(score_match("el cid", "El Cid").is_some());
        assert!(score_match("قسمت 14", "قسمت ۱۴").is_some());
    }

    #[test]
    fn rank_orders_best_first_and_is_stable() {
        let ranked = rank("آفتاب", TITLES);
        assert!(!ranked.is_empty());
        // Best must be one of the two آفتاب variants.
        let best = TITLES[ranked[0].0];
        assert!(best.contains("آفتاب") || best.contains("افتاب"));
        // Scores are non-increasing.
        for w in ranked.windows(2) {
            assert!(w[0].1 >= w[1].1);
        }
        // Indices are unique and in range.
        let mut idxs: Vec<usize> = ranked.iter().map(|(i, _)| *i).collect();
        idxs.sort();
        idxs.dedup();
        assert_eq!(idxs.len(), ranked.len());
        assert!(idxs[0] < TITLES.len());
    }

    #[test]
    fn rank_keeps_original_order_on_ties() {
        // Identical candidates must come back in input order.
        let ranked = rank("گوشه", &["گوشه", "گوشه", "گوشه"]);
        assert_eq!(ranked, vec![(0, 100), (1, 100), (2, 100)]);
    }

    #[test]
    fn rank_with_no_hits_is_empty() {
        assert!(rank("zzzz", TITLES).is_empty());
    }

    #[test]
    fn single_char_word_prefix_gets_no_word_bonus_but_can_subsequence() {
        // One-letter queries fall through to prefix/subsequence scoring.
        let s = score_match("e", "El Cid");
        assert!(s.is_some());
        assert!(
            s.unwrap() < 85,
            "single letters must not get the word-prefix score"
        );
    }
}
