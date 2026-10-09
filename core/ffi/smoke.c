/*
 * smoke.c — C-ABI smoke test for libaftab.
 *
 * Compiled and executed by CI (and by `cargo xtask`-style local runs) with:
 *
 *   gcc -std=c11 -Wall -Wextra -Icore/include core/ffi/smoke.c \
 *       -Lcore/target/release -laftab -lm -o /tmp/aftab-smoke && /tmp/aftab-smoke
 *
 * Every assertion exits non-zero with a message; CI turns that red. The
 * point of this file: prove the header and the library agree, from the
 * perspective of a plain C translation unit — the same view the Windows
 * runner and any future native consumer will have.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "aftab.h"

static int failures = 0;

#define CHECK(cond, msg)                                                    \
    do {                                                                    \
        if (!(cond)) {                                                      \
            fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__);         \
            failures++;                                                     \
        } else {                                                            \
            printf("ok  : %s\n", msg);                                      \
        }                                                                   \
    } while (0)

/* UTF-8 literals — Persian test vectors, byte-identical to the Rust tests. */
static int eq_str(const char *a, const char *b) {
    return a && b && strcmp(a, b) == 0;
}

int main(void) {
    /* ── Version ────────────────────────────────────────────────────── */
    const char *v = aftab_version();
    CHECK(v && v[0] >= '0' && v[0] <= '9', "version is a numeric semver");
    printf("     version = %s\n", v);

    /* ── Persian normalization ─────────────────────────────────────── */
    char *norm = aftab_normalize_persian("علي");
    CHECK(eq_str(norm, "علی"), "Arabic yeh folds to Farsi yeh");
    aftab_free_string(norm);

    norm = aftab_compact_key("آفتاب");
    CHECK(eq_str(norm, "افتاب"), "compact key folds alef madda");
    aftab_free_string(norm);

    CHECK(aftab_persian_equals("كاشي", "کاشی") == 1,
          "persian_equals across Arabic kaf/yeh");
    CHECK(aftab_persian_equals("تهران", "مشهد") == 0,
          "persian_equals rejects different words");

    /* ── Search scoring ────────────────────────────────────────────── */
    int32_t score = aftab_search_score("آفتاب", "افتاب مدیا");
    CHECK(score >= 25, "madda-folded query still matches");
    score = aftab_search_score("zzzz", "افتاب مدیا");
    CHECK(score == -1, "no match is -1");
    score = aftab_search_score(NULL, "افتاب");
    CHECK(score == -2, "bad input is -2, distinct from no-match");

    /* ── URL safety (IP literals — hermetic, no DNS) ───────────────── */
    CHECK(aftab_url_is_safe("https://93.184.216.34/v.mp4") == 1,
          "public IPv4 https is safe");
    CHECK(aftab_url_is_safe("http://[2606:4700::6810:84e5]/v.mp4") == 1,
          "public IPv6 literal is safe");
    CHECK(aftab_url_is_safe("http://127.0.0.1/v.mp4") == 0,
          "loopback is refused");
    CHECK(aftab_url_is_safe("http://[::1]:8080/v.mp4") == 0,
          "IPv6 loopback (with port) is refused");
    CHECK(aftab_url_is_safe("ftp://host/x") == 0, "ftp scheme is refused");
    CHECK(aftab_url_is_safe("javascript:alert(1)") == 0,
          "javascript scheme is refused");
    CHECK(aftab_last_error_code() == AFTAB_UNSUPPORTED_SCHEME,
          "last error code carries the reason");
    CHECK(aftab_last_error_message() != NULL, "last error message exists");

    char *redacted = aftab_redact_url("https://h.example:8443/p?token=1");
    CHECK(eq_str(redacted, "https://h.example:8443"),
          "redaction keeps the port, drops the path");
    aftab_free_string(redacted);

    /* ── Provider construction (no network) ────────────────────────── */
    AftabProvider *p = aftab_provider_default();
    CHECK(p != NULL, "default provider constructs");

    AftabProvider *bad = aftab_provider_new("https://x.example", "  ", NULL);
    CHECK(bad == NULL, "empty API key rejected");
    CHECK(aftab_last_error_code() == AFTAB_INVALID_ARGUMENT,
          "provider error code is INVALID_ARGUMENT");

    CHECK(aftab_provider_genres(NULL) == NULL, "null handle returns NULL");

    aftab_provider_free(p);
    aftab_provider_free(NULL); /* must not crash */

    /* ── Store roundtrip ───────────────────────────────────────────── */
    char pathbuf[256];
    snprintf(pathbuf, sizeof pathbuf, "/tmp/aftab-smoke-store-%ld.json",
             (long)getpid());
    AftabStore *s = aftab_store_open(pathbuf);
    CHECK(s != NULL, "store opens");

    CHECK(aftab_store_add_favorite(
              s,
              "{\"id\": 5, \"type\": \"movie\", \"title\": \"گوشه\","
              " \"image\": \"\", \"year\": 2024, \"added_at\": 1700000000}") == 1,
          "favorite is added");
    CHECK(aftab_store_is_favorite(s, "movie", 5) == 1, "favorite is visible");
    CHECK(aftab_store_is_favorite(s, "movie", 6) == 0, "unknown id not visible");
    CHECK(aftab_store_set_progress(s, "movie", 5, 300.0, 600.0) == 1,
          "progress is stored");

    char *prog = aftab_store_progress_json(s, "movie", 5);
    CHECK(prog && strstr(prog, "\"position\":300.0") != NULL,
          "progress JSON carries the position");
    aftab_free_string(prog);

    char *favs = aftab_store_favorites_json(s);
    CHECK(favs && strstr(favs, "گوشه") != NULL, "favorites JSON carries title");
    aftab_free_string(favs);

    CHECK(aftab_store_remove_favorite(s, "movie", 5) == 1, "favorite removed");
    CHECK(aftab_store_remove_favorite(s, "movie", 5) == 0, "removal is once");
    aftab_store_free(s);
    remove(pathbuf);

    /* ── Download guard ────────────────────────────────────────────── */
    CHECK(aftab_download_file("http://127.0.0.1:9/x.mp4", "/tmp/never.mp4", 0) == -1,
          "private-network download is refused");
    CHECK(aftab_last_error_code() == AFTAB_UNSAFE_URL,
          "download refusal reason is UNSAFE_URL");

    /* ── Summary ───────────────────────────────────────────────────── */
    if (failures > 0) {
        fprintf(stderr, "\n%d smoke check(s) FAILED\n", failures);
        return 1;
    }
    printf("\nall smoke checks passed\n");
    return 0;
}
