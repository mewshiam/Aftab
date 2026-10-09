//! Persian (Farsi) text normalization and compact search keys.
//!
//! Real-world Persian catalog titles mix Arabic and Farsi codepoints,
//! Arabic-Indic and Extended Arabic-Indic digits, ZWNJ (نیم‌فاصله), tatweel,
//! and stray diacritics. Two functions solve two different problems:
//!
//! * [`normalize_persian`] — canonical *display/storage* form: folds Arabic
//!   codepoints to their Farsi equivalents, unifies digits, strips tatweel
//!   and combining diacritics, and squeezes whitespace. ZWNJ is **kept**,
//!   because `می‌روم` and `میروم` are different renderings but the stored
//!   form should stay the typographically correct one.
//! * [`compact_key`] — *matching* form: everything above, plus ZWNJ removed,
//!   ASCII lowercased, all whitespace collapsed to a single space. Two titles
//!   match iff their compact keys are equal.
//!
//! Folding rules (see the test suite for each):
//!
//! | Input (codepoint)                | Output                |
//! |----------------------------------|-----------------------|
//! | U+0623 أ, U+0625 إ, U+0671 ٱ     | U+0627 ا              |
//! | U+0622 آ (alef madda)            | U+0627 ا *(compact only)* |
//! | U+0649 ى, U+064A ي               | U+06CC ی              |
//! | U+0643 ك                         | U+06A9 ک              |
//! | U+0629 ة                         | U+0647 ه              |
//! | U+0624 ؤ                         | U+0648 و              |
//! | U+0626 ئ                         | U+06CC ی              |
//! | U+06C0 هٔ                        | U+0647 ه              |
//! | U+0640 ـ (tatweel)               | removed               |
//! | U+064B–U+0652, U+0670 (harakat)  | removed               |
//! | U+06F0–U+06F9 ۰-۹, U+0660–U+0669 ٠-٩ | ASCII 0–9        |

/// Characters that carry no lexical weight and are always removed.
const STRIP_ALWAYS: &[char] = &[
    '\u{0640}', // tatweel / kashida
    '\u{064B}', '\u{064C}', '\u{064D}', '\u{064E}', // fathatan, dammatan, kasratan, fatha
    '\u{064F}', '\u{0650}', '\u{0651}', '\u{0652}', // damma, kasra, shadda, sukun
    '\u{0670}', // superscript alef
    '\u{0653}', '\u{0654}', '\u{0655}', '\u{0656}', // madda, hamza above/below, subscript
];

/// One canonical character-folding pass shared by both normalization forms.
fn fold_char(c: char) -> Option<char> {
    let folded = match c {
        '\u{0649}' | '\u{064A}' | '\u{0626}' => '\u{06CC}', // ى ي ئ → ی
        '\u{0643}' => '\u{06A9}',                           // ك → ک
        '\u{0623}' | '\u{0625}' | '\u{0671}' => '\u{0627}', // أ إ ٱ → ا
        '\u{0629}' | '\u{06C0}' => '\u{0647}',              // ة هٔ → ه
        '\u{0624}' => '\u{0648}',                           // ؤ → و
        '\u{06F0}'..='\u{06F9}' => return Some(fold_digit(c)), // ۰-۹
        '\u{0660}'..='\u{0669}' => return Some(fold_digit(c)), // ٠-٩
        _ => c,
    };
    Some(folded)
}

fn fold_digit(c: char) -> char {
    // Both Persian (U+06F0..) and Arabic-Indic (U+0660..) digits map to the
    // same ASCII range by subtracting their block base.
    let base = if c >= '\u{06F0}' { 0x06F0 } else { 0x0660 };
    char::from_u32((c as u32 - base) + b'0' as u32).expect("digit fold is total")
}

fn strip_char(c: char) -> bool {
    STRIP_ALWAYS.contains(&c)
}

/// Collapse any run of Unicode whitespace into a single ASCII space.
fn squeeze_whitespace(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_ws = false;
    for c in s.chars() {
        if c.is_whitespace() {
            if !in_ws {
                out.push(' ');
                in_ws = true;
            }
        } else {
            out.push(c);
            in_ws = false;
        }
    }
    out.trim().to_string()
}

/// Canonical storage/display form. ZWNJ is preserved; alef madda (آ) is
/// preserved because it is phonemically distinct in Persian.
pub fn normalize_persian(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for c in input.chars() {
        if strip_char(c) {
            continue;
        }
        if let Some(folded) = fold_char(c) {
            out.push(folded);
        }
    }
    squeeze_whitespace(&out)
}

/// Aggressive matching key: `normalize_persian`, plus ZWNJ removal, alef
/// madda folded onto plain alef, ASCII lowercasing.
pub fn compact_key(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for c in normalize_persian(input).chars() {
        match c {
            '\u{200C}' => continue,             // ZWNJ — نیم‌فاصله must not block matching
            '\u{0622}' => out.push('\u{0627}'), // آ → ا for matching only
            c => out.push(c.to_ascii_lowercase()),
        }
    }
    out
}

/// Compare two user-visible strings the way a Persian speaker would expect:
/// equal after normalization, digit folding, and ZWNJ/spacing tolerance.
pub fn persian_equals(a: &str, b: &str) -> bool {
    compact_key(a) == compact_key(b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arabic_yeh_folds_to_farsi_yeh() {
        assert_eq!(normalize_persian("علي"), normalize_persian("علی"));
        assert_eq!(normalize_persian("علي"), "علی");
    }

    #[test]
    fn alef_maksura_folds_to_farsi_yeh() {
        // موسی vs موسى — same word, different yeh.
        assert_eq!(compact_key("موسى"), compact_key("موسی"));
    }

    #[test]
    fn arabic_kaf_folds_to_farsi_keheh() {
        assert_eq!(normalize_persian("يك"), "یک");
    }

    #[test]
    fn hamza_alef_variants_fold_to_plain_alef() {
        assert_eq!(normalize_persian("أحمد"), "احمد");
        assert_eq!(normalize_persian("إيران"), "ایران");
        assert_eq!(normalize_persian("ٱول"), "اول");
    }

    #[test]
    fn alef_madda_is_distinct_in_display_but_equal_in_matching() {
        // آفتاب starts with alef madda — it must survive display normalization
        // (otherwise the product's own name would render wrong) …
        assert!(normalize_persian("آفتاب").starts_with('\u{0622}'));
        // … yet match a lazily-typed افتاب in search.
        assert_eq!(compact_key("آفتاب"), compact_key("افتاب"));
    }

    #[test]
    fn teh_marbuta_folds_to_heh() {
        // ة→ه AND the Arabic yeh in the input folds to Farsi ی as well.
        assert_eq!(normalize_persian("دقيقة"), "دقیقه");
    }

    #[test]
    fn zwnj_survives_normalization() {
        // می‌روم keeps its نیم‌فاصله in the canonical form…
        assert!(normalize_persian("می\u{200C}روم").contains('\u{200C}'));
        // …but stops mattering for matching.
        assert!(persian_equals("می\u{200C}روم", "میروم"));
    }

    #[test]
    fn zwnj_insensitive_matching_via_compact_key() {
        // The regression this guards: house سرزمین‌ها vs سرزمینها.
        assert_eq!(compact_key("سرزمین\u{200C}ها"), compact_key("سرزمینها"));
    }

    #[test]
    fn persian_digits_fold_to_ascii() {
        assert_eq!(normalize_persian("فصل ۲"), "فصل 2");
        assert_eq!(compact_key("قسمت ۱۴"), compact_key("قسمت 14"));
    }

    #[test]
    fn arabic_indic_digits_fold_to_ascii() {
        assert_eq!(normalize_persian("سال ٢٠٢٣"), "سال 2023");
    }

    #[test]
    fn digit_blocks_are_both_equal_after_folding() {
        // ۱۲۳ vs ١٢٣ vs 123 — all the same key.
        assert_eq!(compact_key("۱۲۳"), "123");
        assert_eq!(compact_key("١٢٣"), "123");
        assert_eq!(compact_key("123"), "123");
    }

    #[test]
    fn tatweel_is_removed() {
        assert_eq!(normalize_persian("عـليـ"), "علی");
    }

    #[test]
    fn diacritics_are_removed() {
        // fatha, sukun, shadda on the same letters.
        assert_eq!(normalize_persian("مُحَمَّد"), "محمد");
    }

    #[test]
    fn whitespace_runs_collapse() {
        assert_eq!(normalize_persian("  hello   world  "), "hello world");
        // full-width / NBSP / tab all count as whitespace
        assert_eq!(compact_key("a\t\u{00A0}b"), "a b");
    }

    #[test]
    fn waw_hamza_and_yeh_hamza_fold() {
        assert_eq!(normalize_persian("ؤ"), "و");
        assert_eq!(normalize_persian("ئ"), "ی");
    }

    #[test]
    fn ascii_lowercase_in_compact_key_only() {
        assert_eq!(compact_key("ALADDIN"), "aladdin");
        assert_eq!(normalize_persian("ALADDIN"), "ALADDIN");
    }

    #[test]
    fn mixed_persian_english_title_normalizes() {
        let a = compact_key("El Cid فصل ۱");
        let b = compact_key("el cid فصل 1");
        assert_eq!(a, b);
    }

    #[test]
    fn persian_equals_handles_all_common_confusions() {
        assert!(persian_equals("كاشي", "کاشی"));
        assert!(persian_equals("سریال تهران", "سریال  تهران"));
        assert!(!persian_equals("تهران", "مشهد"));
    }

    #[test]
    fn empty_and_punctuation_only_inputs() {
        assert_eq!(normalize_persian(""), "");
        assert_eq!(compact_key(""), "");
        assert_eq!(normalize_persian("   "), "");
    }
}
