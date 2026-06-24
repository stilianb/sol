const std = @import("std");
pub const fetcher = @import("fetcher.zig");
pub const xml_helpers = @import("xml_helpers.zig");
pub const parser = struct {
    pub const html = @import("parser/html.zig");
};
pub const crawler = struct {
    pub const robots = @import("crawler/robots.zig");
    pub const sitemap = @import("crawler/sitemap.zig");
    pub const crawler = @import("crawler/crawler.zig");
    pub const pool = @import("crawler/pool.zig");
};
pub const server = struct {
    pub const router = @import("server/router.zig");
    pub const sse = @import("server/sse.zig");
};
pub const auditor = struct {
    pub const wcag = @import("auditor/wcag.zig");
    pub const performance = @import("auditor/performance.zig");
    pub const cookies = @import("auditor/cookies.zig");
    pub const seo = @import("auditor/seo.zig");
    pub const best_practices = @import("auditor/best_practices.zig");
    pub const keywords = @import("auditor/keywords.zig");
    pub const aeo = @import("auditor/aeo.zig");
    pub const scorer = @import("auditor/scorer.zig");
};
pub const audit = @import("audit.zig");
pub const baseline = @import("baseline.zig");
pub const psi = struct {
    pub const types = @import("psi/types.zig");
    pub const client = @import("psi/client.zig");
    pub const parser = @import("psi/parser.zig");
};
pub const goals = struct {
    pub const goals = @import("goals/goals.zig");
    pub const tracker = @import("goals/tracker.zig");
};

test {
    _ = @import("fetcher.zig");
    _ = @import("xml_helpers.zig");
    _ = @import("parser/html.zig");
    _ = @import("crawler/robots.zig");
    _ = @import("crawler/sitemap.zig");
    _ = @import("auditor/wcag.zig");
    _ = @import("auditor/performance.zig");
    _ = @import("auditor/cookies.zig");
    _ = @import("auditor/seo.zig");
    _ = @import("auditor/best_practices.zig");
    _ = @import("auditor/keywords.zig");
    _ = @import("auditor/aeo.zig");
    _ = @import("auditor/scorer.zig");
    _ = @import("audit.zig");
    _ = @import("baseline.zig");
    _ = @import("psi/types.zig");
    _ = @import("psi/client.zig");
    _ = @import("psi/parser.zig");
    _ = @import("crawler/crawler.zig");
    _ = @import("crawler/pool.zig");
    _ = @import("server/router.zig");
    _ = @import("server/sse.zig");
    _ = @import("goals/goals.zig");
    _ = @import("goals/tracker.zig");
}
