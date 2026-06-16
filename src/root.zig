const std = @import("std");
pub const fetcher = @import("fetcher.zig");
pub const xml_helpers = @import("xml_helpers.zig");
pub const parser = struct {
    pub const html = @import("parser/html.zig");
};
pub const crawler = struct {
    pub const robots = @import("crawler/robots.zig");
    pub const sitemap = @import("crawler/sitemap.zig");
};
pub const auditor = struct {
    pub const wcag = @import("auditor/wcag.zig");
    pub const performance = @import("auditor/performance.zig");
    pub const cookies = @import("auditor/cookies.zig");
};
pub const audit = @import("audit.zig");

test {
    _ = @import("fetcher.zig");
    _ = @import("xml_helpers.zig");
    _ = @import("parser/html.zig");
    _ = @import("crawler/robots.zig");
    _ = @import("crawler/sitemap.zig");
    _ = @import("auditor/wcag.zig");
    _ = @import("auditor/performance.zig");
    _ = @import("auditor/cookies.zig");
}
