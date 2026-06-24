const std = @import("std");

/// Core Web Vitals and Lighthouse scores from Google PageSpeed Insights API v5.
/// All fields are optional — absent when the API did not return a value.
pub const PsiData = struct {
    strategy: []const u8,           // "mobile" | "desktop"
    lcp_ms: ?u64,                   // Largest Contentful Paint
    fcp_ms: ?u64,                   // First Contentful Paint
    cls_score: ?f32,                // Cumulative Layout Shift (unitless, lower=better)
    tbt_ms: ?u64,                   // Total Blocking Time
    speed_index_ms: ?u64,           // Speed Index
    inp_ms: ?u64,                   // Interaction to Next Paint
    lighthouse_performance: ?u8,    // 0–100
    lighthouse_accessibility: ?u8,  // 0–100
    lighthouse_best_practices: ?u8, // 0–100
    lighthouse_seo: ?u8,            // 0–100
    allocator: std.mem.Allocator,

    pub fn deinit(self: PsiData) void {
        self.allocator.free(self.strategy);
    }
};

// ── tests ─────────────────────────────────────────────────────────────────────

test "PsiData fields accessible" {
    const d = PsiData{
        .strategy = "mobile",
        .lcp_ms = 2500,
        .fcp_ms = 1200,
        .cls_score = 0.05,
        .tbt_ms = 150,
        .speed_index_ms = 3400,
        .inp_ms = null,
        .lighthouse_performance = 72,
        .lighthouse_accessibility = 88,
        .lighthouse_best_practices = 95,
        .lighthouse_seo = 91,
        .allocator = std.testing.allocator,
    };
    try std.testing.expectEqualStrings("mobile", d.strategy);
    try std.testing.expectEqual(@as(?u64, 2500), d.lcp_ms);
    try std.testing.expectEqual(@as(?u8, 72), d.lighthouse_performance);
    try std.testing.expectEqual(@as(?u64, null), d.inp_ms);
}

test "PsiData good thresholds: LCP < 2500ms = good" {
    const lcp: u64 = 2400;
    try std.testing.expect(lcp < 2500);
}

test "PsiData good thresholds: CLS < 0.1 = good" {
    const cls: f32 = 0.08;
    try std.testing.expect(cls < 0.1);
}
